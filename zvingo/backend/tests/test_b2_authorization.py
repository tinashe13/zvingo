"""Authorization on financial endpoints, and the impossibility of mock payments in production."""

import inspect
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.auth.router import get_current_admin, get_current_user


def user(user_id="user-1", role="consumer"):
    return SimpleNamespace(id=user_id, role=role)


class Query:
    def __init__(self, values=None, count=None):
        self.values = list(values or [])
        self.count_value = len(self.values) if count is None else count

    def sort(self, *_a):
        return self

    def limit(self, *_a):
        return self

    def skip(self, *_a):
        return self

    async def to_list(self):
        return self.values

    async def count(self):
        return self.count_value


class Field:
    def __eq__(self, other):
        return ("eq", other)

    def __ge__(self, other):
        return ("ge", other)

    def __lt__(self, other):
        return ("lt", other)

    def __neg__(self):
        return self


def _history(module, driver_id, current_user):
    """Call the history route with real values (FastAPI Query defaults are objects)."""
    return module.get_earnings_history(
        driver_id, start_date=None, end_date=None, payment_method=None,
        min_amount_cents=None, merchant_name=None, area=None, page=1,
        page_size=20, current_user=current_user,
    )


def _dependency_of(func, name="current_user"):
    """The FastAPI dependency callable bound to a route parameter."""
    param = inspect.signature(func).parameters[name]
    return param.default.dependency


# ── admin-only routes ───────────────────────────────────────────────


def test_rate_publication_and_audit_are_admin_only():
    import app.finance.router as module

    assert _dependency_of(module.update_exchange_rate) is get_current_admin
    assert _dependency_of(module.get_rate_history) is get_current_admin
    assert _dependency_of(module.get_reconciliation) is get_current_admin
    # Reading rates stays public — it is a price list, not a private record.
    assert "current_user" not in inspect.signature(module.get_exchange_rates).parameters


def test_refund_settlement_routes_are_admin_only():
    import app.payment.router as module

    assert _dependency_of(module.list_refunds) is get_current_admin
    assert _dependency_of(module.complete_refund) is get_current_admin
    assert _dependency_of(module.reject_refund) is get_current_admin
    # Requesting a refund is open to the paying consumer, so it uses the
    # ordinary dependency plus an explicit ownership check in the body.
    assert _dependency_of(module.open_refund_request) is get_current_user
    assert _dependency_of(module.refund_payment) is get_current_user


@pytest.mark.asyncio
async def test_get_current_admin_actually_rejects_non_admins():
    with pytest.raises(HTTPException) as exc:
        await get_current_admin(user(role="consumer"))
    assert exc.value.status_code == 403
    admin = user(role="admin")
    assert await get_current_admin(admin) is admin


# ── driver earnings privacy ─────────────────────────────────────────


@pytest.fixture
def earnings(monkeypatch):
    import app.finance.models as models

    class FakeEarning:
        driver_id = Field()
        order_id = Field()
        completed_at = Field()
        payment_method = Field()
        total_earning_cents = Field()

        @classmethod
        def find(cls, *_a):
            return Query([])

        @classmethod
        async def find_one(cls, *_a):
            return None

    monkeypatch.setattr(models, "DriverEarning", FakeEarning)
    return FakeEarning


@pytest.mark.asyncio
async def test_a_driver_cannot_read_another_drivers_earnings(earnings):
    import app.finance.router as module

    for call in (
        lambda: module.get_driver_earnings("driver-a", user("driver-b", "driver")),
        lambda: module.get_daily_breakdown("driver-a", 30, user("driver-b", "driver")),
        lambda: _history(module, "driver-a", user("driver-b", "driver")),
    ):
        with pytest.raises(HTTPException) as exc:
            await call()
        assert exc.value.status_code == 403
        assert "Not authorized" in exc.value.detail


@pytest.mark.asyncio
async def test_a_driver_can_read_their_own_earnings(earnings):
    import app.finance.router as module

    me = user("driver-a", "driver")
    summary = await module.get_driver_earnings("driver-a", me)
    assert summary["today_deliveries"] == 0
    assert await module.get_daily_breakdown("driver-a", 30, me) == []
    assert (await _history(module, "driver-a", me))["total"] == 0


@pytest.mark.asyncio
async def test_an_admin_can_read_any_drivers_earnings(earnings):
    import app.finance.router as module

    admin = user("admin-1", "admin")
    assert await module.get_driver_earnings("driver-a", admin)
    assert await module.get_daily_breakdown("driver-a", 30, admin) == []
    assert await _history(module, "driver-a", admin)


@pytest.mark.asyncio
async def test_a_driver_cannot_record_earnings_for_someone_else(earnings):
    import app.finance.router as module

    with pytest.raises(HTTPException) as exc:
        await module.record_earning("o1", "driver-a", user("driver-b", "driver"))
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_merchant_analytics_are_private_to_the_merchant_and_admins(monkeypatch):
    import app.finance.router as module

    with pytest.raises(HTTPException) as exc:
        await module.get_merchant_analytics("merchant-a", user("merchant-b", "merchant"))
    assert exc.value.status_code == 403

    class FakeOrder:
        merchant_id = Field()
        state = Field()
        updated_at = Field()
        created_at = Field()

        @classmethod
        def find(cls, *_a):
            return Query([])

    class FakeRestaurant:
        merchant_id = Field()
        find_one = AsyncMock(return_value=None)

        @classmethod
        def find(cls, *_a):
            # Analytics resolves the merchant's restaurants before querying
            # orders, because Order.merchant_id is a restaurant id. This test
            # is about who may call the endpoint, not what it returns.
            return Query([])

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(module, "Restaurant", FakeRestaurant)
    assert await module.get_merchant_analytics("merchant-a", user("merchant-a", "merchant"))
    assert await module.get_merchant_analytics("merchant-a", user("admin-1", "admin"))


@pytest.mark.asyncio
async def test_the_order_ledger_is_visible_only_to_its_parties(monkeypatch):
    import app.finance.router as module
    from app.finance.ledger import LedgerService

    order = SimpleNamespace(
        id="o1", consumer_id="c1", merchant_id="m1", driver_id="d1"
    )

    class FakeOrder:
        get = AsyncMock(return_value=order)

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(LedgerService, "entries_for_order", AsyncMock(return_value=[]))

    with pytest.raises(HTTPException) as exc:
        await module.get_order_ledger("o1", user("stranger"))
    assert exc.value.status_code == 403

    for viewer in ("c1", "m1", "d1"):
        assert (await module.get_order_ledger("o1", user(viewer)))["balanced"] is True
    assert await module.get_order_ledger("o1", user("admin-1", "admin"))

    FakeOrder.get.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.get_order_ledger("missing", user("c1"))
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_the_fee_breakdown_is_visible_only_to_the_orders_parties(monkeypatch):
    import app.payment.router as module

    order = SimpleNamespace(
        id="o1", consumer_id="c1", merchant_id="m1", driver_id="d1",
        total_amount=20.0, delivery_fee=10.0, service_fee=0.0,
        tax_amount=0.0, tip_amount=0.0, discount_amount=0.0,
    )

    class FakeOrder:
        get = AsyncMock(return_value=order)

    monkeypatch.setattr(module, "Order", FakeOrder)

    with pytest.raises(HTTPException) as exc:
        await module.get_order_fee_breakdown("o1", user("stranger"))
    assert exc.value.status_code == 403

    result = await module.get_order_fee_breakdown("o1", user("c1"))
    assert result["customer_total_minor"] == 3000
    assert result["driver_payout_minor"] == 850
    assert result["merchant_payout_minor"] == 2000
    assert await module.get_order_fee_breakdown("o1", user("admin-1", "admin"))

    FakeOrder.get.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.get_order_fee_breakdown("missing", user("c1"))
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_an_admin_may_view_but_not_hijack_a_consumers_payment(monkeypatch):
    import app.payment.router as module

    payment = SimpleNamespace(consumer_id="c1")
    monkeypatch.setattr(
        module.PaymentService, "get_payment_for_order", AsyncMock(return_value=payment)
    )
    monkeypatch.setattr(module, "_payment_to_response", lambda p: p)

    with pytest.raises(HTTPException) as exc:
        await module.get_payment_for_order("o1", user("stranger"))
    assert exc.value.status_code == 403
    assert await module.get_payment_for_order("o1", user("c1")) is payment
    assert await module.get_payment_for_order("o1", user("admin-1", "admin")) is payment


# ── mock mode cannot exist in production ────────────────────────────


def test_settings_refuse_to_boot_with_mock_payments_in_production():
    from app.config import Settings

    with pytest.raises(ValueError) as exc:
        Settings(
            ENVIRONMENT="production",
            MONGODB_URL="mongodb://localhost:27017",
            REDIS_URL="redis://localhost:6379",
            SECRET_KEY="a" * 64,
            PAYMENT_MOCK_MODE=True,
            PAYNOW_INTEGRATION_ID="id",
            PAYNOW_INTEGRATION_KEY="key",
            SMS_MOCK_MODE=False,
            AFRICASTALKING_API_KEY="k",
        )
    assert "PAYMENT_MOCK_MODE must be false in production" in str(exc.value)


def test_settings_refuse_to_boot_without_paynow_credentials_in_production():
    from app.config import Settings

    with pytest.raises(ValueError) as exc:
        Settings(
            ENVIRONMENT="production",
            MONGODB_URL="mongodb://localhost:27017",
            REDIS_URL="redis://localhost:6379",
            SECRET_KEY="a" * 64,
            PAYMENT_MOCK_MODE=False,
            PAYNOW_INTEGRATION_ID=None,
            PAYNOW_INTEGRATION_KEY=None,
            SMS_MOCK_MODE=False,
            AFRICASTALKING_API_KEY="k",
        )
    assert "PAYNOW_INTEGRATION_ID and PAYNOW_INTEGRATION_KEY are required" in str(exc.value)


def test_the_paynow_client_refuses_to_construct_a_production_mock(monkeypatch):
    """Defence in depth: even a hand-built settings object cannot do it."""
    import app.payment.paynow_client as module

    monkeypatch.setattr(module.settings, "PAYMENT_MOCK_MODE", True)
    monkeypatch.setattr(module.settings, "ENVIRONMENT", "production")
    with pytest.raises(RuntimeError, match="must not be enabled in production"):
        module.PaynowClient()


def test_a_live_client_without_credentials_refuses_to_construct(monkeypatch):
    import app.payment.paynow_client as module

    monkeypatch.setattr(module.settings, "PAYMENT_MOCK_MODE", False)
    monkeypatch.setattr(module.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(module.settings, "PAYNOW_INTEGRATION_ID", None)
    monkeypatch.setattr(module.settings, "PAYNOW_INTEGRATION_KEY", None)
    with pytest.raises(RuntimeError, match="are not configured"):
        module.PaynowClient()


@pytest.mark.asyncio
async def test_a_live_client_never_auto_approves_when_it_cannot_reach_paynow(monkeypatch):
    import app.payment.paynow_client as module

    client = module.PaynowClient()
    client.mock_mode = False
    client._paynow = None
    status = await client.check_status("https://www.paynow.co.zw/interface/poll/abc")
    assert status.paid is False
    assert status.state is module.PaynowState.ERROR

    # A mock:// poll URL is not honoured once mock mode is off either.
    status = await client.check_status("mock://poll/whatever")
    assert status.paid is False
