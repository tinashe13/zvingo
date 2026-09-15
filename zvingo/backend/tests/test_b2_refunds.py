"""Refunds: never fake, always auditable, settled only against real evidence.

Paynow Zimbabwe exposes no refund endpoint (its documented API is initiate,
initiate-express, poll and the result-URL callback, and no official SDK
implements a refund). So a refund request opens an auditable workflow and holds
the payment in REFUND_PENDING — an explicit "we owe this customer money and it
has not moved yet" — until an operator records the provider reference proving
the money was actually returned.
"""

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.payment.models import PaymentStatus, RefundStatus


def a_payment(**overrides):
    values = {
        "id": "p1",
        "order_id": "o1",
        "consumer_id": "c1",
        "paynow_reference": "ZVINGO-abc12345",
        "amount_usd_cents": 3150,
        "amount_local_cents": 3150,
        "currency": "USD",
        "charge_amount_minor": 3150,
        "charge_currency": "USD",
        "refund_request_id": None,
        "status": PaymentStatus.PAID,
        "updated_at": None,
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def install(monkeypatch, module, payment):
    created = []

    class FakePayment:
        get = AsyncMock(return_value=payment)

    class FakeRefundRequest:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = f"refund-{len(created) + 1}"
            self.external_reference = None
            self.resolved_by = None
            self.resolved_at = None
            self.resolution_note = kwargs.get("resolution_note", "")
            self.ledger_posted = False
            self.updated_at = None
            created.append(self)

        async def insert(self):
            return self

        async def save(self):
            return self

        @classmethod
        async def get(cls, refund_id):
            for row in created:
                if row.id == refund_id:
                    return row
            return None

        @classmethod
        async def find_one(cls, *args):
            return created[-1] if created else None

    monkeypatch.setattr(module, "Payment", FakePayment)
    monkeypatch.setattr(module, "RefundRequest", FakeRefundRequest)
    monkeypatch.setattr(module.LedgerService, "post", AsyncMock(return_value=[]))
    return created


@pytest.mark.asyncio
async def test_a_failed_provider_refund_parks_an_explicit_liability(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    created = install(monkeypatch, module, payment)
    monkeypatch.setattr(
        module.paynow_client,
        "refund",
        AsyncMock(return_value=SimpleNamespace(
            success=False, error="Paynow Zimbabwe exposes no refund API"
        )),
    )

    result, refund = await module.PaymentService.request_refund(
        "p1", requested_by="admin-1", reason="order never arrived"
    )
    assert result.status == PaymentStatus.REFUND_PENDING
    assert refund.status is RefundStatus.PENDING_MANUAL
    assert refund.amount_minor == 3150
    assert refund.requested_by == "admin-1"
    assert refund.reason == "order never arrived"
    assert refund.provider_reference == "ZVINGO-abc12345"
    assert refund.ledger_posted is False
    assert payment.refund_request_id == refund.id
    # Crucially, the payment is NOT marked refunded.
    assert result.status is not PaymentStatus.REFUNDED
    assert len(created) == 1


@pytest.mark.asyncio
async def test_completing_a_manual_refund_requires_provider_evidence(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    install(monkeypatch, module, payment)
    monkeypatch.setattr(
        module.paynow_client,
        "refund",
        AsyncMock(return_value=SimpleNamespace(success=False, error="no refund API")),
    )
    _payment, refund = await module.PaymentService.request_refund(
        "p1", requested_by="admin-1"
    )

    # A blank reference is refused: the ledger entry must be backed by proof.
    for bad in ("", "   ", None):
        with pytest.raises(ValueError):
            await module.PaymentService.complete_manual_refund(
                refund.id, external_reference=bad, resolved_by="admin-1"
            )
    assert payment.status == PaymentStatus.REFUND_PENDING

    settled_payment, settled = await module.PaymentService.complete_manual_refund(
        refund.id,
        external_reference="PN-REFUND-99887",
        resolved_by="admin-1",
        note="refunded from the Paynow portal",
    )
    assert settled_payment.status == PaymentStatus.REFUNDED
    assert settled.status is RefundStatus.COMPLETED
    assert settled.external_reference == "PN-REFUND-99887"
    assert settled.resolved_by == "admin-1"
    assert settled.resolved_at is not None
    assert settled.ledger_posted is True
    module.LedgerService.post.assert_awaited()


@pytest.mark.asyncio
async def test_completing_twice_is_idempotent(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    install(monkeypatch, module, payment)
    monkeypatch.setattr(
        module.paynow_client,
        "refund",
        AsyncMock(return_value=SimpleNamespace(success=False, error="no refund API")),
    )
    _p, refund = await module.PaymentService.request_refund("p1", requested_by="a")
    await module.PaymentService.complete_manual_refund(
        refund.id, external_reference="PN-1", resolved_by="a"
    )
    posts = module.LedgerService.post.await_count

    again_payment, again = await module.PaymentService.complete_manual_refund(
        refund.id, external_reference="PN-1", resolved_by="a"
    )
    assert again.status is RefundStatus.COMPLETED
    assert again.external_reference == "PN-1"
    assert module.LedgerService.post.await_count == posts
    assert again_payment.status == PaymentStatus.REFUNDED


@pytest.mark.asyncio
async def test_rejecting_a_refund_returns_the_payment_to_paid(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    install(monkeypatch, module, payment)
    monkeypatch.setattr(
        module.paynow_client,
        "refund",
        AsyncMock(return_value=SimpleNamespace(success=False, error="no refund API")),
    )
    _p, refund = await module.PaymentService.request_refund("p1", requested_by="a")
    assert payment.status == PaymentStatus.REFUND_PENDING

    restored, rejected = await module.PaymentService.reject_refund(
        refund.id, resolved_by="admin-2", note="customer withdrew the claim"
    )
    assert rejected.status is RefundStatus.REJECTED
    assert rejected.resolution_note == "customer withdrew the claim"
    assert restored.status == PaymentStatus.PAID
    module.LedgerService.post.assert_not_awaited()


@pytest.mark.asyncio
async def test_a_completed_refund_cannot_be_rejected(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    install(monkeypatch, module, payment)
    monkeypatch.setattr(
        module.paynow_client,
        "refund",
        AsyncMock(return_value=SimpleNamespace(success=True, reference="PN-OK")),
    )
    _p, refund = await module.PaymentService.request_refund("p1", requested_by="a")
    assert refund.status is RefundStatus.COMPLETED
    with pytest.raises(ValueError):
        await module.PaymentService.reject_refund(refund.id, resolved_by="a")


@pytest.mark.asyncio
async def test_partial_refunds_are_bounded_by_what_was_charged(monkeypatch):
    import app.payment.service as module

    payment = a_payment()
    install(monkeypatch, module, payment)
    monkeypatch.setattr(
        module.paynow_client,
        "refund",
        AsyncMock(return_value=SimpleNamespace(success=False, error="no refund API")),
    )

    _p, refund = await module.PaymentService.request_refund(
        "p1", requested_by="a", amount_minor=1000
    )
    assert refund.amount_minor == 1000

    payment.status = PaymentStatus.PAID
    with pytest.raises(ValueError):
        await module.PaymentService.request_refund(
            "p1", requested_by="a", amount_minor=999_999
        )
    with pytest.raises(ValueError):
        await module.PaymentService.request_refund(
            "p1", requested_by="a", amount_minor=-5
        )


@pytest.mark.asyncio
async def test_refunding_an_unpaid_payment_does_nothing(monkeypatch):
    import app.payment.service as module

    payment = a_payment(status=PaymentStatus.FAILED)
    created = install(monkeypatch, module, payment)
    result, refund = await module.PaymentService.request_refund("p1", requested_by="a")
    assert result is payment
    assert payment.status == PaymentStatus.FAILED
    assert created == []
    assert refund is None


@pytest.mark.asyncio
async def test_refunding_a_missing_payment_returns_nothing(monkeypatch):
    import app.payment.service as module

    install(monkeypatch, module, None)
    module.Payment.get.return_value = None
    assert await module.PaymentService.request_refund("gone", requested_by="a") == (None, None)
    assert await module.PaymentService.complete_manual_refund(
        "gone", external_reference="x", resolved_by="a"
    ) == (None, None)
    assert await module.PaymentService.reject_refund("gone", resolved_by="a") == (None, None)


@pytest.mark.asyncio
async def test_paynow_client_reports_no_programmatic_refund_in_live_mode(monkeypatch):
    """The provider capability is stated explicitly, not discovered by surprise."""
    import app.payment.paynow_client as module

    client = module.PaynowClient()
    assert module.PaynowClient.supports_programmatic_refund is False

    client.mock_mode = False
    client._paynow = object()
    response = await client.refund("ZVINGO-abc12345", 31.50)
    assert response.success is False
    assert "no refund API" in response.error

    client.mock_mode = True
    assert (await client.refund("ZVINGO-abc12345", 31.50)).success is True
