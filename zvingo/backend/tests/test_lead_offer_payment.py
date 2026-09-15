"""A driver offer must state the real payment method.

The offer payload hardcoded ``payment_method: 0`` with the comment "0=cash".
Cash is not a supported method -- the enum is ECOCASH / ONEMONEY / INNBUCKS /
CARD -- so every offer told the driver the order was cash. The driver app shows
a prominent "Collect $X" for a cash order, so this pushed drivers to ask for
money on orders the customer had already paid by mobile money.
"""

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

import app.notification.service as service


@pytest.mark.asyncio
async def test_a_settled_mobile_money_order_is_marked_prepaid(monkeypatch):
    import app.payment.models as payment_models

    payment = SimpleNamespace(
        method=SimpleNamespace(value="ECOCASH"),
        status=SimpleNamespace(value="PAID"),
    )
    monkeypatch.setattr(
        payment_models.Payment, "find_one", AsyncMock(return_value=payment)
    )

    code, name, prepaid = await service._resolve_payment("o1")

    assert prepaid is True
    assert code == service.PAYMENT_METHOD_CODES["ECOCASH"]
    assert name == "Ecocash"


@pytest.mark.asyncio
async def test_an_unsettled_order_is_not_reported_as_paid(monkeypatch):
    import app.payment.models as payment_models

    payment = SimpleNamespace(
        method=SimpleNamespace(value="ECOCASH"),
        status=SimpleNamespace(value="PENDING"),
    )
    monkeypatch.setattr(
        payment_models.Payment, "find_one", AsyncMock(return_value=payment)
    )

    _code, name, prepaid = await service._resolve_payment("o1")

    assert prepaid is False
    assert name == "Unpaid"


@pytest.mark.asyncio
async def test_a_missing_payment_record_errs_toward_collecting(monkeypatch):
    """Failing open here would tell a driver an unpaid order was settled."""
    import app.payment.models as payment_models

    monkeypatch.setattr(
        payment_models.Payment, "find_one", AsyncMock(return_value=None)
    )

    code, _name, prepaid = await service._resolve_payment("o1")

    assert prepaid is False
    assert code == service.UNSETTLED_PAYMENT_CODE


@pytest.mark.asyncio
async def test_a_lookup_failure_errs_toward_collecting(monkeypatch):
    import app.payment.models as payment_models

    monkeypatch.setattr(
        payment_models.Payment,
        "find_one",
        AsyncMock(side_effect=RuntimeError("database down")),
    )

    _code, name, prepaid = await service._resolve_payment("o1")

    assert prepaid is False
    assert name == "Unknown"


def test_cash_is_not_a_supported_payment_method():
    """If cash is ever added, the offer payload needs revisiting deliberately."""
    from app.payment.models import PaymentMethod

    assert "CASH" not in {m.value for m in PaymentMethod}


# ── payment rail safety ───────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_an_unsupported_method_is_refused_not_silently_rerouted():
    """CARD is in the PaymentMethod enum but has no Paynow rail.

    The provider lookup used to be ``.get(method, "ecocash")``, so choosing card
    fell through the default and charged the customer's EcoCash wallet -- money
    taken from a rail they never picked. It must refuse instead.
    """
    from fastapi import HTTPException

    from app.payment.models import PaymentMethod
    from app.payment.service import METHOD_PROVIDER_MAP, _provider_for

    assert PaymentMethod.CARD not in METHOD_PROVIDER_MAP

    with pytest.raises(HTTPException) as exc:
        _provider_for(PaymentMethod.CARD)
    assert exc.value.status_code == 400
    assert "ecocash" not in str(exc.value.detail).lower().split("please")[0]

    for method in (
        PaymentMethod.ECOCASH,
        PaymentMethod.ONEMONEY,
        PaymentMethod.INNBUCKS,
    ):
        assert _provider_for(method) == METHOD_PROVIDER_MAP[method]
