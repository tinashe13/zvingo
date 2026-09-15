"""Reconciliation: detecting money that has gone missing between systems."""

from types import SimpleNamespace

import pytest

from app.finance import reconciliation as rec
from app.payment.models import PaymentStatus, RefundStatus
from app.time_utils import utc_now


def _matches(row, query):
    """Tiny subset of the Mongo query language, enough for these checks."""
    for field, condition in query.items():
        value = getattr(row, field, None)
        if hasattr(value, "value"):
            value = value.value
        if isinstance(condition, dict):
            for op, operand in condition.items():
                if op == "$in" and value not in operand:
                    return False
                if op == "$lt" and not (value is not None and value < operand):
                    return False
                if op == "$gte" and not (value is not None and value >= operand):
                    return False
        elif value != condition:
            return False
    return True


class Collection:
    """Stand-in for a Beanie document class backed by a list."""

    def __init__(self, rows):
        self.rows = rows

    def find(self, query=None):
        rows = [r for r in self.rows if _matches(r, query or {})]

        class Query:
            async def to_list(_self):
                return rows

        return Query()

    def find_all(self):
        return self.find({})


def payment(**overrides):
    values = {
        "id": "p1",
        "order_id": "o1",
        "consumer_id": "c1",
        "status": PaymentStatus.PAID,
        "updated_at": utc_now(),
        "paynow_reference": "ref",
        "charge_amount_minor": 3150,
        "charge_currency": "USD",
        "display_amount": lambda: "$31.50",
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def order(**overrides):
    values = {
        "id": "o1",
        "state": "DELIVERED",
        "consumer_id": "c1",
        "merchant_id": "m1",
        "is_pickup": False,
        "created_at": utc_now(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def entry(**overrides):
    values = {
        "id": "e1",
        "posting_id": "post-1",
        "payment_id": "p1",
        "order_id": "o1",
        "currency": "USD",
        "amount_minor": 0,
        "describe": lambda: "CHARGE",
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def refund(**overrides):
    values = {
        "id": "r1",
        "payment_id": "p1",
        "order_id": "o1",
        "consumer_id": "c1",
        "amount_minor": 3150,
        "currency": "USD",
        "status": RefundStatus.PENDING_MANUAL,
        "requested_at": utc_now(),
        "reason": "cold food",
        "display_amount": lambda: "$31.50",
    }
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
async def test_stuck_payments_are_only_those_past_the_cutoff(monkeypatch):
    from datetime import timedelta

    fresh = payment(id="fresh", status=PaymentStatus.AWAITING_DELIVERY, updated_at=utc_now())
    stale = payment(
        id="stale",
        status=PaymentStatus.AWAITING_DELIVERY,
        updated_at=utc_now() - timedelta(hours=3),
    )
    settled = payment(id="settled", status=PaymentStatus.PAID,
                      updated_at=utc_now() - timedelta(hours=3))
    monkeypatch.setattr(rec, "Payment", Collection([fresh, stale, settled]))

    found = await rec.stuck_payments(minutes=30)
    assert [f["payment_id"] for f in found] == ["stale"]
    assert found[0]["amount"] == "$31.50"
    assert found[0]["status"] == "AWAITING_DELIVERY"


@pytest.mark.asyncio
async def test_orders_being_fulfilled_without_a_settled_payment_are_flagged(monkeypatch):
    """The free-food signature: an order in flight with nothing paid for it."""
    import app.order.models as order_models

    paid_order = order(id="paid")
    unpaid_order = order(id="unpaid", state="PICKED_UP")
    failed_order = order(id="failed", state="ACCEPTED")
    created_order = order(id="created", state="CREATED")  # before the payment gate

    monkeypatch.setattr(
        order_models,
        "Order",
        Collection([paid_order, unpaid_order, failed_order, created_order]),
    )
    monkeypatch.setattr(
        rec,
        "Payment",
        Collection([
            payment(id="p-paid", order_id="paid", status=PaymentStatus.PAID),
            payment(id="p-failed", order_id="failed", status=PaymentStatus.FAILED),
        ]),
    )

    findings = {f["order_id"]: f for f in await rec.orders_paid_without_payment()}
    assert set(findings) == {"unpaid", "failed"}
    assert findings["unpaid"]["has_payment_record"] is False
    assert findings["failed"]["has_payment_record"] is True
    assert findings["unpaid"]["state"] == "PICKED_UP"


@pytest.mark.asyncio
async def test_a_refund_pending_payment_still_counts_as_settled(monkeypatch):
    import app.order.models as order_models

    monkeypatch.setattr(order_models, "Order", Collection([order(id="o1")]))
    monkeypatch.setattr(
        rec,
        "Payment",
        Collection([payment(order_id="o1", status=PaymentStatus.REFUND_PENDING)]),
    )
    assert await rec.orders_paid_without_payment() == []


@pytest.mark.asyncio
async def test_no_orders_in_flight_is_not_an_issue(monkeypatch):
    import app.order.models as order_models

    monkeypatch.setattr(order_models, "Order", Collection([]))
    monkeypatch.setattr(rec, "Payment", Collection([]))
    assert await rec.orders_paid_without_payment() == []


@pytest.mark.asyncio
async def test_settled_payments_missing_their_ledger_entries_are_flagged(monkeypatch):
    with_ledger = payment(id="with", status=PaymentStatus.PAID)
    without_ledger = payment(id="without", status=PaymentStatus.PAID)
    unsettled = payment(id="pending", status=PaymentStatus.PENDING)

    monkeypatch.setattr(
        rec, "Payment", Collection([with_ledger, without_ledger, unsettled])
    )
    monkeypatch.setattr(rec, "LedgerEntry", Collection([entry(payment_id="with")]))

    findings = await rec.payments_missing_ledger()
    assert [f["payment_id"] for f in findings] == ["without"]

    monkeypatch.setattr(rec, "Payment", Collection([]))
    assert await rec.payments_missing_ledger() == []


@pytest.mark.asyncio
async def test_unbalanced_postings_are_detected(monkeypatch):
    balanced = [
        entry(id="a", posting_id="ok", amount_minor=-1000),
        entry(id="b", posting_id="ok", amount_minor=1000),
    ]
    broken = [
        entry(id="c", posting_id="bad", amount_minor=-1000),
        entry(id="d", posting_id="bad", amount_minor=900),
    ]
    monkeypatch.setattr(rec, "LedgerEntry", Collection(balanced + broken))

    findings = await rec.unbalanced_postings()
    assert len(findings) == 1
    assert findings[0]["posting_id"] == "bad"
    assert findings[0]["residual_minor"] == -100
    assert findings[0]["residual"] == "-$1.00"


@pytest.mark.asyncio
async def test_mixed_currency_postings_are_balanced_per_currency(monkeypatch):
    monkeypatch.setattr(
        rec,
        "LedgerEntry",
        Collection([
            entry(id="a", posting_id="mix", amount_minor=-1000, currency="USD"),
            entry(id="b", posting_id="mix", amount_minor=1000, currency="ZIG"),
        ]),
    )
    findings = await rec.unbalanced_postings()
    assert {f["currency"] for f in findings} == {"USD", "ZIG"}


@pytest.mark.asyncio
async def test_pending_refunds_are_money_we_still_owe(monkeypatch):
    monkeypatch.setattr(
        rec,
        "RefundRequest",
        Collection([
            refund(id="owed", status=RefundStatus.PENDING_MANUAL),
            refund(id="done", status=RefundStatus.COMPLETED),
        ]),
    )
    findings = await rec.pending_manual_refunds()
    assert [f["refund_id"] for f in findings] == ["owed"]
    assert findings[0]["amount"] == "$31.50"


@pytest.mark.asyncio
async def test_run_reconciliation_reports_healthy_when_everything_lines_up(monkeypatch):
    import app.order.models as order_models

    monkeypatch.setattr(order_models, "Order", Collection([order(id="o1")]))
    monkeypatch.setattr(rec, "Payment", Collection([payment(order_id="o1")]))
    monkeypatch.setattr(
        rec,
        "LedgerEntry",
        Collection([
            entry(id="a", amount_minor=-3150),
            entry(id="b", amount_minor=3150),
        ]),
    )
    monkeypatch.setattr(rec, "RefundRequest", Collection([]))

    report = await rec.run_reconciliation()
    assert report["healthy"] is True
    assert report["issue_count"] == 0
    for check in (
        "stuck_payments",
        "orders_paid_without_payment",
        "payments_missing_ledger",
        "unbalanced_postings",
        "pending_manual_refunds",
    ):
        assert report[check]["count"] == 0


@pytest.mark.asyncio
async def test_run_reconciliation_surfaces_issues_and_survives_a_broken_check(monkeypatch):
    import app.order.models as order_models

    monkeypatch.setattr(order_models, "Order", Collection([order(id="unpaid")]))
    monkeypatch.setattr(rec, "Payment", Collection([]))
    monkeypatch.setattr(rec, "RefundRequest", Collection([refund()]))

    class Exploding:
        def find_all(self):
            raise RuntimeError("ledger offline")

        def find(self, *args, **kwargs):
            raise RuntimeError("ledger offline")

    monkeypatch.setattr(rec, "LedgerEntry", Exploding())

    report = await rec.run_reconciliation()
    assert report["healthy"] is False
    assert report["orders_paid_without_payment"]["count"] == 1
    assert report["pending_manual_refunds"]["count"] == 1
    # A check that cannot run is reported as an issue, not swallowed.
    assert report["unbalanced_postings"]["error"] == "ledger offline"
    assert report["unbalanced_postings"]["count"] is None
