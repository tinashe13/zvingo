"""Payment money representation, guarded transitions and webhook idempotency."""

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from pymongo.errors import DuplicateKeyError

from app.payment.models import (
    NotificationSource,
    Payment,
    PaymentMethod,
    PaymentStatus,
)
from app.payment.paynow_client import PaynowState, classify_status
from app.payment.state_machine import (
    InvalidPaymentTransition,
    TransitionKind,
    classify_transition,
    is_terminal,
    validate_transition,
)


# ── money representation on the document ────────────────────────────


def test_legacy_float_amounts_are_folded_into_minor_units():
    """Documents written before the migration must still read correctly."""
    folded = Payment._fold_legacy_float_amounts(
        {"amount_usd": 10.1, "amount_local": 136.35, "currency": "ZIG"}
    )
    assert folded["amount_usd_cents"] == 1010   # not 1009 (the binary value)
    assert folded["amount_local_cents"] == 13635
    assert "amount_usd" not in folded
    assert "amount_local" not in folded


def test_legacy_usd_only_record_gets_a_local_amount():
    folded = Payment._fold_legacy_float_amounts({"amount_usd": 7.5})
    assert folded["amount_usd_cents"] == 750
    assert folded["amount_local_cents"] == 750


def test_explicit_minor_units_win_over_legacy_floats():
    folded = Payment._fold_legacy_float_amounts(
        {"amount_usd": 10.0, "amount_usd_cents": 999}
    )
    assert folded["amount_usd_cents"] == 999


def test_an_unknown_currency_does_not_change_the_scale():
    folded = Payment._fold_legacy_float_amounts(
        {"amount_usd": 10.0, "amount_local": 10.0, "currency": "GBP"}
    )
    assert folded["amount_local_cents"] == 1000


def test_float_views_are_derived_from_cents():
    payment = Payment.model_construct(
        order_id="o1",
        consumer_id="c1",
        amount_usd_cents=3150,
        amount_local_cents=42525,
        currency="ZIG",
        method=PaymentMethod.ECOCASH,
        status=PaymentStatus.PENDING,
    )
    assert payment.amount_usd == 31.5
    assert payment.amount_local == 425.25
    assert payment.charge_amount_minor == 42525
    assert payment.charge_currency == "ZIG"
    assert payment.display_amount() == "ZiG425.25"


def test_an_unsupported_currency_falls_back_to_usd_for_display():
    payment = Payment.model_construct(
        order_id="o1", consumer_id="c1", amount_usd_cents=1000,
        amount_local_cents=1000, currency="GBP",
        method=PaymentMethod.CARD, status=PaymentStatus.PENDING,
    )
    assert payment.charge_currency == "USD"
    assert payment.amount_local == 10.0


# ── state machine ───────────────────────────────────────────────────


def test_settlement_path_is_allowed():
    assert validate_transition(
        PaymentStatus.PENDING, PaymentStatus.AWAITING_DELIVERY
    ) is TransitionKind.APPLY
    assert validate_transition(
        PaymentStatus.AWAITING_DELIVERY, PaymentStatus.PAID
    ) is TransitionKind.APPLY
    assert validate_transition(
        PaymentStatus.PAID, PaymentStatus.REFUND_PENDING
    ) is TransitionKind.APPLY
    assert validate_transition(
        PaymentStatus.REFUND_PENDING, PaymentStatus.REFUNDED
    ) is TransitionKind.APPLY
    # A rejected refund returns the payment to PAID: the money never moved.
    assert validate_transition(
        PaymentStatus.REFUND_PENDING, PaymentStatus.PAID
    ) is TransitionKind.APPLY


def test_a_repeat_of_the_current_state_is_a_noop_not_an_error():
    """A retried webhook is normal traffic, not a failure."""
    assert classify_transition(PaymentStatus.PAID, PaymentStatus.PAID) is TransitionKind.NOOP


def test_settled_payments_cannot_be_walked_backwards():
    for target in (
        PaymentStatus.FAILED,
        PaymentStatus.CANCELLED,
        PaymentStatus.EXPIRED,
        PaymentStatus.AWAITING_DELIVERY,
        PaymentStatus.PENDING,
    ):
        assert classify_transition(PaymentStatus.PAID, target) is TransitionKind.INVALID
        with pytest.raises(InvalidPaymentTransition):
            validate_transition(PaymentStatus.PAID, target)


def test_terminal_states_have_no_exits():
    for state in (
        PaymentStatus.REFUNDED,
        PaymentStatus.FAILED,
        PaymentStatus.CANCELLED,
        PaymentStatus.EXPIRED,
    ):
        assert is_terminal(state)
        for target in PaymentStatus:
            if target is state:
                continue
            assert classify_transition(state, target) is TransitionKind.INVALID


def test_paynow_status_strings_are_classified_exhaustively():
    assert classify_status("Paid") is PaynowState.PAID
    assert classify_status("Awaiting Delivery") is PaynowState.PAID
    assert classify_status("Delivered") is PaynowState.PAID
    assert classify_status("Sent") is PaynowState.PENDING
    assert classify_status("Created") is PaynowState.PENDING
    assert classify_status("Cancelled") is PaynowState.CANCELLED
    assert classify_status("Failed") is PaynowState.FAILED
    assert classify_status("Disputed") is PaynowState.DISPUTED
    assert classify_status("Refunded") is PaynowState.REFUNDED
    assert classify_status("Expired") is PaynowState.EXPIRED
    # Anything unrecognised is never treated as success.
    assert classify_status("Martian") is PaynowState.UNKNOWN
    assert classify_status(None) is PaynowState.UNKNOWN
    assert classify_status("") is PaynowState.UNKNOWN


# ── service-level idempotency and guards ────────────────────────────


def a_payment(**overrides):
    values = {
        "id": "p1",
        "order_id": "o1",
        "consumer_id": "c1",
        "paynow_reference": "ZVINGO-abc12345",
        "poll_url": "https://www.paynow.co.zw/interface/poll/abc",
        "amount_usd_cents": 3150,
        "amount_local_cents": 3150,
        "currency": "USD",
        "charge_amount_minor": 3150,
        "charge_currency": "USD",
        "breakdown": None,
        "fx_rate_micros": None,
        "refund_request_id": None,
        "status": PaymentStatus.AWAITING_DELIVERY,
        "updated_at": None,
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def install_payment(monkeypatch, module, payment, seen_keys=None):
    seen = set(seen_keys or ())

    class FakePayment:
        get = AsyncMock(return_value=payment)

        class _Field:
            def __eq__(self, other):
                return ("eq", other)

        paynow_reference = _Field()
        order_id = _Field()
        find_one = AsyncMock(return_value=payment)

    notifications = []

    class FakeNotification:
        """Enforces the unique dedupe_key index the real collection carries."""

        class _Field:
            def __eq__(self, other):
                return ("eq", other)

        dedupe_key = _Field()

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.anomaly = None

        async def insert(self):
            if self.dedupe_key in seen:
                raise DuplicateKeyError("dedupe_key_1")
            notifications.append(self)
            seen.add(self.dedupe_key)
            return self

        async def save(self):
            return self

        @classmethod
        async def find_one(cls, criteria):
            key = criteria[1]
            return object() if key in seen else None

    monkeypatch.setattr(module, "Payment", FakePayment)
    monkeypatch.setattr(module, "PaymentNotification", FakeNotification)
    return notifications


@pytest.mark.asyncio
async def test_a_retried_webhook_settles_only_once(monkeypatch):
    """Paynow retries until it gets a 2xx. The second delivery must do nothing."""
    import app.payment.service as module

    payment = a_payment()
    notifications = install_payment(monkeypatch, module, payment)
    settle_hook = AsyncMock()
    monkeypatch.setattr(module.PaymentService, "_on_payment_success", settle_hook)
    monkeypatch.setattr(module.PaymentService, "_record_settlement_ledger", AsyncMock())

    fields = dict(reference="ZVINGO-abc12345", status="Paid", amount="31.50")
    await module.PaymentService.handle_webhook(
        reference=fields["reference"], status="Paid", poll_url="",
        amount="31.50", paynow_reference="1234567", signature_verified=True,
        payload=fields,
    )
    assert payment.status == PaymentStatus.PAID
    settle_hook.assert_awaited_once()

    # Delivery two: same notification, logged as seen, nothing re-run.
    await module.PaymentService.handle_webhook(
        reference=fields["reference"], status="Paid", poll_url="",
        amount="31.50", paynow_reference="1234567", signature_verified=True,
        payload=fields,
    )
    settle_hook.assert_awaited_once()
    assert len(notifications) == 1

    # Even if the dedupe log were unavailable entirely, the state machine
    # refuses the repeat: PAID -> PAID is a no-op.
    monkeypatch.setattr(
        module.PaymentService,
        "_claim_notification",
        AsyncMock(return_value=(None, True)),
    )
    await module.PaymentService.handle_webhook(
        reference=fields["reference"], status="Paid", poll_url="",
        amount="31.50", paynow_reference="1234567", signature_verified=True,
        payload=fields,
    )
    settle_hook.assert_awaited_once()


@pytest.mark.asyncio
async def test_a_paid_notification_with_the_wrong_amount_is_rejected(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    notifications = install_payment(monkeypatch, module, payment)
    settle_hook = AsyncMock()
    monkeypatch.setattr(module.PaymentService, "_on_payment_success", settle_hook)
    monkeypatch.setattr(module.PaymentService, "_record_settlement_ledger", AsyncMock())

    await module.PaymentService.handle_webhook(
        reference="ZVINGO-abc12345", status="Paid", poll_url="",
        amount="0.01", signature_verified=True,
    )
    assert payment.status == PaymentStatus.AWAITING_DELIVERY
    settle_hook.assert_not_awaited()
    assert notifications[-1].anomaly.startswith("rejected:")
    assert "amount mismatch" in notifications[-1].anomaly


@pytest.mark.asyncio
async def test_a_late_failure_on_a_settled_payment_is_an_anomaly(monkeypatch):
    import app.payment.service as module

    payment = a_payment(status=PaymentStatus.PAID)
    notifications = install_payment(monkeypatch, module, payment)

    await module.PaymentService.handle_webhook(
        reference="ZVINGO-abc12345", status="Cancelled", poll_url="",
        signature_verified=True,
    )
    assert payment.status == PaymentStatus.PAID
    assert notifications[-1].anomaly == "anomaly:failure-after-settlement"


@pytest.mark.asyncio
async def test_disputes_and_provider_refunds_are_flagged_not_applied(monkeypatch):
    import app.payment.service as module

    payment = a_payment(status=PaymentStatus.PAID)
    notifications = install_payment(monkeypatch, module, payment)

    await module.PaymentService.handle_webhook(
        reference="ZVINGO-abc12345", status="Disputed", poll_url="",
        signature_verified=True,
    )
    assert payment.status == PaymentStatus.PAID
    assert notifications[-1].anomaly == "anomaly:disputed"

    await module.PaymentService.handle_webhook(
        reference="ZVINGO-abc12345", status="Refunded", poll_url="",
        signature_verified=True, paynow_reference="other",
    )
    assert payment.status == PaymentStatus.PAID
    assert notifications[-1].anomaly == "anomaly:provider-refund"


@pytest.mark.asyncio
async def test_cancellation_is_recorded_distinctly_from_failure(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    install_payment(monkeypatch, module, payment)
    await module.PaymentService.handle_webhook(
        reference="ZVINGO-abc12345", status="Cancelled", poll_url="",
        signature_verified=True,
    )
    assert payment.status == PaymentStatus.CANCELLED


@pytest.mark.asyncio
async def test_the_webhook_supplied_poll_url_is_never_followed(monkeypatch):
    """A forged pollurl must not redirect the server at an attacker endpoint."""
    import app.payment.service as module

    payment = a_payment(poll_url="https://evil.example.com/always-paid")
    install_payment(monkeypatch, module, payment)
    check = AsyncMock(return_value=SimpleNamespace(paid=True, status="Paid"))
    monkeypatch.setattr(module.paynow_client, "check_status", check)

    result = await module.PaymentService.check_payment_status("p1")
    assert result is payment
    assert payment.status == PaymentStatus.AWAITING_DELIVERY
    check.assert_not_awaited()


@pytest.mark.asyncio
async def test_polling_a_paynow_url_settles_the_payment(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    install_payment(monkeypatch, module, payment)
    monkeypatch.setattr(
        module.paynow_client,
        "check_status",
        AsyncMock(return_value=SimpleNamespace(
            paid=True, status="Paid", state=PaynowState.PAID, amount_minor=3150
        )),
    )
    monkeypatch.setattr(module.PaymentService, "_on_payment_success", AsyncMock())
    monkeypatch.setattr(module.PaymentService, "_record_settlement_ledger", AsyncMock())

    await module.PaymentService.check_payment_status("p1")
    assert payment.status == PaymentStatus.PAID


@pytest.mark.asyncio
async def test_unknown_reference_is_logged_and_returns_nothing(monkeypatch):
    import app.payment.service as module

    notifications = install_payment(monkeypatch, module, None)
    module.Payment.find_one.return_value = None
    assert await module.PaymentService.handle_webhook(
        reference="nope", status="Paid", poll_url="", signature_verified=True
    ) is None
    assert notifications[-1].action == "unknown-payment"
    assert notifications[-1].accepted is False


def test_dedupe_key_is_stable_and_discriminating():
    from app.payment.service import build_dedupe_key

    a = build_dedupe_key("p1", "Paid", 3150, "pn-1")
    assert a == build_dedupe_key("p1", " paid ", 3150, "pn-1")
    assert a != build_dedupe_key("p1", "Paid", 3151, "pn-1")
    assert a != build_dedupe_key("p2", "Paid", 3150, "pn-1")
    assert a != build_dedupe_key("p1", "Cancelled", 3150, "pn-1")


def test_the_audit_payload_redacts_the_signature():
    from app.payment.service import _safe_payload

    cleaned = _safe_payload({"status": "Paid", "hash": "SECRET", "amount": "31.50"})
    assert cleaned["hash"] == "<redacted>"
    assert cleaned["status"] == "Paid"
    assert _safe_payload(None) == {}
    # Values that cannot be serialised are stringified rather than dropped.
    assert isinstance(_safe_payload({"x": object()})["x"], str)


# ── charging the right amount ───────────────────────────────────────


@pytest.mark.asyncio
async def test_initiate_charges_the_whole_order_not_just_the_subtotal(monkeypatch):
    import app.payment.router as module

    order = SimpleNamespace(
        consumer_id="c1", total_amount=20.00, delivery_fee=10.00,
        service_fee=1.50, tax_amount=1.00, tip_amount=2.00, discount_amount=3.00,
    )

    class FakeOrder:
        get = AsyncMock(return_value=order)

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(
        module.PaymentService, "get_payment_for_order", AsyncMock(return_value=None)
    )
    initiate = AsyncMock(
        return_value=Payment.model_construct(
            order_id="o1", consumer_id="c1", amount_usd_cents=3150,
            amount_local_cents=3150, currency="USD", method=PaymentMethod.ECOCASH,
            status=PaymentStatus.AWAITING_DELIVERY, paynow_reference="r",
            created_at=__import__("datetime").datetime(2026, 9, 15),
            breakdown=None, id="p1",
        )
    )
    monkeypatch.setattr(module.PaymentService, "initiate_payment", initiate)

    from app.payment.schemas import PaymentInitiate

    await module.initiate_payment(
        PaymentInitiate(order_id="o1", method=PaymentMethod.ECOCASH, phone="+263771234567"),
        SimpleNamespace(id="c1", role="consumer"),
    )
    breakdown = initiate.await_args.kwargs["breakdown"]
    # 20.00 + 10.00 + 1.50 + 1.00 + 2.00 - 3.00
    assert breakdown.customer_total_minor == 3150
    assert breakdown.subtotal_minor == 2000
    assert breakdown.driver_payout_minor == 850 + 200


def test_payment_initiate_rejects_an_unsupported_currency():
    from pydantic import ValidationError

    from app.payment.schemas import PaymentInitiate

    assert PaymentInitiate(
        order_id="o1", method=PaymentMethod.ECOCASH, phone="+263771234567", currency="zig"
    ).currency == "ZIG"
    with pytest.raises(ValidationError):
        PaymentInitiate(
            order_id="o1", method=PaymentMethod.ECOCASH, phone="+263771234567",
            currency="GBP",
        )


def test_notification_source_values_cover_every_intake_path():
    assert {s.value for s in NotificationSource} == {"WEBHOOK", "POLL", "MANUAL", "MOCK"}


@pytest.mark.asyncio
async def test_initiation_pins_the_rate_onto_the_payment_record(monkeypatch):
    """The payment itself carries the rate it was converted at, and its source."""
    from decimal import Decimal

    import app.payment.service as module
    from app.finance import exchange

    created = []

    class FakePayment:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "p1"
            self.poll_url = None
            self.paynow_reference = None
            created.append(self)

        async def insert(self):
            return self

        async def save(self):
            return self

    monkeypatch.setattr(module, "Payment", FakePayment)
    monkeypatch.setattr(
        module.PaymentService, "get_exchange_rate", AsyncMock(return_value=Decimal("13.5"))
    )
    monkeypatch.setattr(
        exchange,
        "get_order_rate_lock",
        AsyncMock(return_value=SimpleNamespace(
            source="rbz", rate_effective_at=None, rate=Decimal("13.5")
        )),
    )
    monkeypatch.setattr(
        module.paynow_client,
        "send_mobile",
        AsyncMock(return_value=SimpleNamespace(
            success=True, poll_url="https://www.paynow.co.zw/interface/poll/x",
            reference="ZVINGO-p1",
        )),
    )

    from app.finance.fee_calculator import build_breakdown

    breakdown = build_breakdown(subtotal_minor=2000, delivery_fee_minor=1000)
    payment = await module.PaymentService.initiate_payment(
        "o1", "c1", 0, PaymentMethod.ECOCASH, "+263771234567", "ZIG",
        breakdown=breakdown,
    )
    assert payment.amount_usd_cents == 3000
    assert payment.amount_local_cents == 40500        # 3000 * 13.5
    assert payment.fx_rate_micros == 13_500_000
    assert payment.fx_source == "rbz"
    assert payment.status == PaymentStatus.AWAITING_DELIVERY
    # The breakdown the customer was shown is frozen onto the payment.
    assert payment.breakdown["customer_total_minor"] == 3000
    assert payment.breakdown["driver_share_minor"] == 850


@pytest.mark.asyncio
async def test_a_usd_payment_needs_no_conversion(monkeypatch):
    import app.payment.service as module

    class FakePayment:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "p1"
            self.poll_url = None
            self.paynow_reference = None

        async def insert(self):
            return self

        async def save(self):
            return self

    monkeypatch.setattr(module, "Payment", FakePayment)
    monkeypatch.setattr(
        module.paynow_client,
        "send_mobile",
        AsyncMock(return_value=SimpleNamespace(success=False, error="declined")),
    )
    payment = await module.PaymentService.initiate_payment(
        "o1", "c1", 31.50, PaymentMethod.ECOCASH, "+263771234567", "USD"
    )
    assert payment.amount_usd_cents == 3150
    assert payment.amount_local_cents == 3150
    assert payment.fx_source == "base"
    assert payment.status == PaymentStatus.FAILED


@pytest.mark.asyncio
async def test_two_workers_racing_the_same_notification_settle_it_once(monkeypatch):
    """The receipt's unique index is the mutex: one worker wins, one stops."""
    import asyncio

    import app.payment.service as module

    payment = a_payment()
    notifications = install_payment(monkeypatch, module, payment)
    settle_hook = AsyncMock()
    monkeypatch.setattr(module.PaymentService, "_on_payment_success", settle_hook)
    monkeypatch.setattr(module.PaymentService, "_record_settlement_ledger", AsyncMock())

    async def deliver():
        return await module.PaymentService.handle_webhook(
            reference="ZVINGO-abc12345", status="Paid", poll_url="",
            amount="31.50", paynow_reference="1234567", signature_verified=True,
        )

    await asyncio.gather(deliver(), deliver(), deliver())
    assert payment.status == PaymentStatus.PAID
    settle_hook.assert_awaited_once()
    assert len(notifications) == 1
    assert notifications[0].action == "settled"


@pytest.mark.asyncio
async def test_the_receipt_records_what_the_notification_caused(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    notifications = install_payment(monkeypatch, module, payment)
    monkeypatch.setattr(module.PaymentService, "_on_payment_success", AsyncMock())
    monkeypatch.setattr(module.PaymentService, "_record_settlement_ledger", AsyncMock())

    await module.PaymentService.handle_webhook(
        reference="ZVINGO-abc12345", status="Paid", poll_url="",
        amount="31.50", signature_verified=True,
        payload={"status": "Paid", "hash": "SECRET"},
    )
    receipt = notifications[-1]
    assert receipt.action == "settled"
    assert receipt.anomaly is None
    assert receipt.signature_verified is True
    assert receipt.reported_amount_minor == 3150
    # The signature is redacted before the delivery is stored.
    assert receipt.payload["hash"] == "<redacted>"
