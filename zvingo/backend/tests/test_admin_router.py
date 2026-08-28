"""Tests for the admin platform management API."""

from app.time_utils import utc_now
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from app.admin.schemas import AdminUserUpdate, RestaurantAdminUpdate
from app.order.state_machine import InvalidStateTransition, OrderState
from app.payment.models import PaymentMethod, PaymentStatus


class Query:
    def __init__(self, values=None, count=None):
        self.values = list(values or [])
        self.count_value = len(self.values) if count is None else count

    def sort(self, *args):
        return self

    def skip(self, *args):
        return self

    def limit(self, *args):
        return self

    async def to_list(self):
        return self.values

    async def count(self):
        return self.count_value


class Field:
    def __eq__(self, value):
        return ("eq", value)

    def __neg__(self):
        return self


def admin(id="admin-1"):
    return SimpleNamespace(id=id, role="admin", save=AsyncMock())


def user_doc(id="user-1", **overrides):
    values = {
        "id": id,
        "full_name": "User One",
        "phone": "+263770000000",
        "email": "user@example.com",
        "role": "consumer",
        "is_active": True,
        "is_dashing": False,
        "driver_rating": 4.5,
        "driver_review_count": 2,
        "created_at": datetime.now(),
        "vehicle": None,
        "schedule": [],
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def order_doc(id="order-1", **overrides):
    values = {
        "id": id,
        "state": OrderState.CREATED,
        "merchant_id": "restaurant-1",
        "consumer_id": "user-1",
        "driver_id": None,
        "group_id": None,
        "total_amount": 25.0,
        "delivery_fee": 5.0,
        "discount_amount": 0.0,
        "promo_code": None,
        "is_pickup": False,
        "scheduled_at": None,
        "retry_count": 0,
        "created_at": utc_now(),
        "updated_at": utc_now(),
        "last_retry_at": None,
        "scheduled_dispatched": False,
        "delivery_instructions": "Gate 3",
        "items": [{"name": "Burger", "quantity": 1, "price": 10.0}],
        "events": [
            SimpleNamespace(
                state=OrderState.CREATED, timestamp=utc_now(), actor_id=None
            )
        ],
        "pickup_location": SimpleNamespace(lat=-17.8, lng=31.0),
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def payment_doc(**overrides):
    values = {
        "id": "payment-1",
        "order_id": "order-1",
        "consumer_id": "user-1",
        "amount_usd": 25.0,
        "amount_local": 25.0,
        "currency": "USD",
        "method": PaymentMethod.ECOCASH,
        "status": PaymentStatus.PAID,
        "paynow_reference": "ref-1",
        "created_at": datetime.now(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def restaurant_doc(**overrides):
    values = {
        "id": "restaurant-1",
        "name": "Nandos",
        "merchant_id": "merchant-1",
        "is_active": True,
        "rating": 4.6,
        "review_count": 120,
        "menu": [SimpleNamespace(id="m1")],
        "address": "12 Samora Ave",
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


# ── stats & alerts ──────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_platform_stats_aggregates_every_collection(monkeypatch):
    import app.admin.router as module

    delivered = [order_doc(total_amount=10.0), order_doc(total_amount=15.0, updated_at=None)]

    monkeypatch.setattr(module.User, "find", lambda *a, **k: Query([], count=3))
    monkeypatch.setattr(module.User, "find_all", lambda: Query([], count=9))
    monkeypatch.setattr(module.Order, "find", lambda *a, **k: Query(delivered))
    monkeypatch.setattr(module.Order, "find_all", lambda: Query([], count=42))
    monkeypatch.setattr(module.Payment, "find", lambda *a, **k: Query([], count=4))
    monkeypatch.setattr(module.Restaurant, "find", lambda *a, **k: Query([], count=6))
    monkeypatch.setattr(module.Restaurant, "find_all", lambda: Query([], count=7))
    monkeypatch.setattr(module.User, "role", Field(), raising=False)
    monkeypatch.setattr(module.User, "is_active", Field(), raising=False)
    monkeypatch.setattr(module.Order, "state", Field(), raising=False)
    monkeypatch.setattr(module.Payment, "status", Field(), raising=False)
    monkeypatch.setattr(module.Restaurant, "is_active", Field(), raising=False)

    stats = await module.platform_stats(admin())
    assert stats.users["total"] == 9
    assert stats.users["driver"] == 3
    assert stats.orders["total"] == 42
    assert stats.payments["PAID"] == 4
    assert stats.gmv["all_time"] == 25.0
    # The order with no updated_at cannot be counted toward today's GMV.
    assert stats.gmv["today"] == 10.0
    assert stats.restaurants == {"total": 7, "active": 6}


@pytest.mark.asyncio
async def test_alert_endpoints_read_and_run(monkeypatch):
    import app.admin.router as module

    monkeypatch.setattr(
        module.alert_service, "history", MagicMock(return_value=[{"kind": "stuck_order"}])
    )
    monkeypatch.setattr(
        module.alert_service, "run_checks", AsyncMock(return_value={"stuck_orders": 0})
    )

    assert (await module.list_alerts(10, admin()))["alerts"][0]["kind"] == "stuck_order"
    assert (await module.run_alert_checks(admin()))["results"] == {"stuck_orders": 0}


# ── users ───────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_list_users_applies_every_filter(monkeypatch):
    import app.admin.router as module

    captured = {}

    def find(query):
        captured["query"] = query
        return Query([user_doc()], count=1)

    monkeypatch.setattr(module.User, "find", find)
    monkeypatch.setattr(module.User, "created_at", Field(), raising=False)

    page = await module.list_users(
        role="driver", is_active=False, q="tina", page=2, page_size=10, _=admin()
    )
    assert page.total == 1
    assert page.page == 2
    assert page.records[0]["id"] == "user-1"
    assert captured["query"]["role"] == "driver"
    assert captured["query"]["is_active"] is False
    assert len(captured["query"]["$or"]) == 3

    await module.list_users(
        role=None, is_active=None, q=None, page=1, page_size=25, _=admin()
    )
    assert captured["query"] == {}


@pytest.mark.asyncio
async def test_get_user_includes_order_counts(monkeypatch):
    import app.admin.router as module

    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=user_doc()))
    monkeypatch.setattr(module.Order, "find", lambda *a, **k: Query([], count=3))
    monkeypatch.setattr(module.Order, "consumer_id", Field(), raising=False)
    monkeypatch.setattr(module.Order, "driver_id", Field(), raising=False)

    detail = await module.get_user("user-1", admin())
    assert detail["order_count"] == 3
    assert detail["delivery_count"] == 3

    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.get_user("missing", admin())
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_update_user_changes_role_name_and_status(monkeypatch):
    import app.admin.router as module

    target = user_doc()
    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=target))

    result = await module.update_user(
        "user-1",
        AdminUserUpdate(role="driver", is_active=False, full_name="Renamed"),
        admin(),
    )
    assert result["role"] == "driver"
    assert result["is_active"] is False
    assert result["full_name"] == "Renamed"
    target.save.assert_awaited()


@pytest.mark.asyncio
async def test_update_user_rejects_bad_role_and_self_lockout(monkeypatch):
    import app.admin.router as module

    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.update_user("missing", AdminUserUpdate(role="driver"), admin())
    assert exc.value.status_code == 404

    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=user_doc()))
    with pytest.raises(HTTPException) as exc:
        await module.update_user("user-1", AdminUserUpdate(role="wizard"), admin())
    assert exc.value.status_code == 400

    me = user_doc(id="admin-1", role="admin")
    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=me))
    with pytest.raises(HTTPException) as exc:
        await module.update_user("admin-1", AdminUserUpdate(role="consumer"), admin())
    assert "own admin role" in exc.value.detail

    with pytest.raises(HTTPException) as exc:
        await module.update_user("admin-1", AdminUserUpdate(is_active=False), admin())
    assert "own account" in exc.value.detail

    # An admin may still keep their own role and rename themselves.
    result = await module.update_user(
        "admin-1", AdminUserUpdate(role="admin", is_active=True), admin()
    )
    assert result["role"] == "admin"


# ── orders ──────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_list_orders_filters_and_stuck_window(monkeypatch):
    import app.admin.router as module

    captured = {}

    def find(query):
        captured["query"] = query
        return Query([order_doc()], count=1)

    monkeypatch.setattr(module.Order, "find", find)
    monkeypatch.setattr(module.Order, "created_at", Field(), raising=False)

    page = await module.list_orders(
        state=OrderState.OFFERED,
        merchant_id="restaurant-1",
        consumer_id="user-1",
        driver_id="driver-1",
        group_id="group-1",
        stuck_minutes=None,
        page=1,
        page_size=25,
        _=admin(),
    )
    assert page.records[0]["state"] == "CREATED"
    assert captured["query"]["merchant_id"] == "restaurant-1"
    assert captured["query"]["group_id"] == "group-1"

    await module.list_orders(
        state=None,
        merchant_id=None,
        consumer_id=None,
        driver_id=None,
        group_id=None,
        stuck_minutes=30,
        page=1,
        page_size=25,
        _=admin(),
    )
    assert captured["query"]["state"] == {"$nin": list(module.TERMINAL_STATES)}
    assert "updated_at" in captured["query"]


@pytest.mark.asyncio
async def test_get_order_returns_events_and_payment(monkeypatch):
    import app.admin.router as module

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order_doc()))
    monkeypatch.setattr(module.Payment, "find_one", AsyncMock(return_value=payment_doc()))
    monkeypatch.setattr(module.Payment, "order_id", Field(), raising=False)

    detail = await module.get_order("order-1", admin())
    assert detail["events"][0]["state"] == "CREATED"
    assert detail["payment"]["status"] == "PAID"
    assert detail["items"][0]["name"] == "Burger"

    # Model items and a missing payment.
    item = SimpleNamespace(model_dump=MagicMock(return_value={"name": "Fries"}))
    monkeypatch.setattr(
        module.Order,
        "get",
        AsyncMock(return_value=order_doc(items=[item], events=[])),
    )
    monkeypatch.setattr(module.Payment, "find_one", AsyncMock(return_value=None))
    detail = await module.get_order("order-1", admin())
    assert detail["items"] == [{"name": "Fries"}]
    assert detail["payment"] is None

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.get_order("missing", admin())
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_force_cancel_order(monkeypatch):
    import app.admin.router as module

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order_doc()))
    transition = AsyncMock(return_value=order_doc(state=OrderState.CANCELLED))
    monkeypatch.setattr(module.OrderService, "transition_state", transition)

    assert (await module.force_cancel_order("order-1", admin()))["status"] == "cancelled"
    transition.assert_awaited_once()

    transition.side_effect = InvalidStateTransition("already delivered")
    with pytest.raises(HTTPException) as exc:
        await module.force_cancel_order("order-1", admin())
    assert exc.value.status_code == 400

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.force_cancel_order("missing", admin())
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_redispatch_order_resets_retries(monkeypatch):
    import app.admin.router as module
    import app.dispatch.service as dispatch_module

    target = order_doc(retry_count=10, state=OrderState.OFFERED)
    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=target))
    dispatch = AsyncMock()
    monkeypatch.setattr(dispatch_module.dispatch_service, "dispatch_order", dispatch)

    result = await module.redispatch_order("order-1", admin())
    assert result["status"] == "redispatched"
    assert target.retry_count == 0
    assert target.scheduled_dispatched is True
    dispatch.assert_awaited_once_with("order-1", -17.8, 31.0)

    monkeypatch.setattr(
        module.Order, "get", AsyncMock(return_value=order_doc(state=OrderState.DELIVERED))
    )
    with pytest.raises(HTTPException) as exc:
        await module.redispatch_order("order-1", admin())
    assert exc.value.status_code == 400

    monkeypatch.setattr(
        module.Order, "get", AsyncMock(return_value=order_doc(pickup_location=None))
    )
    with pytest.raises(HTTPException) as exc:
        await module.redispatch_order("order-1", admin())
    assert "pickup location" in exc.value.detail

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.redispatch_order("missing", admin())
    assert exc.value.status_code == 404


# ── payments & restaurants ──────────────────────────────────────────


@pytest.mark.asyncio
async def test_list_payments_filters(monkeypatch):
    import app.admin.router as module

    captured = {}

    def find(query):
        captured["query"] = query
        return Query([payment_doc()], count=1)

    monkeypatch.setattr(module.Payment, "find", find)
    monkeypatch.setattr(module.Payment, "created_at", Field(), raising=False)

    page = await module.list_payments(
        status=PaymentStatus.FAILED,
        order_id="order-1",
        consumer_id="user-1",
        page=1,
        page_size=25,
        _=admin(),
    )
    assert page.records[0]["method"] == "ECOCASH"
    assert captured["query"]["order_id"] == "order-1"

    await module.list_payments(
        status=None, order_id=None, consumer_id=None, page=1, page_size=25, _=admin()
    )
    assert captured["query"] == {}


@pytest.mark.asyncio
async def test_list_and_update_restaurants(monkeypatch):
    import app.admin.router as module

    captured = {}

    def find(query):
        captured["query"] = query
        return Query([restaurant_doc()], count=1)

    monkeypatch.setattr(module.Restaurant, "find", find)
    page = await module.list_restaurants(
        is_active=True, merchant_id="merchant-1", page=1, page_size=25, _=admin()
    )
    assert page.records[0]["menu_items"] == 1
    assert captured["query"] == {"is_active": True, "merchant_id": "merchant-1"}

    await module.list_restaurants(
        is_active=None, merchant_id=None, page=1, page_size=25, _=admin()
    )
    assert captured["query"] == {}

    target = restaurant_doc()
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=target))
    result = await module.update_restaurant(
        "restaurant-1", RestaurantAdminUpdate(is_active=False), admin()
    )
    assert result["is_active"] is False
    target.save.assert_awaited_once()

    # An empty patch is a no-op rather than an error.
    unchanged = restaurant_doc()
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=unchanged))
    await module.update_restaurant("restaurant-1", RestaurantAdminUpdate(), admin())
    unchanged.save.assert_not_awaited()

    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.update_restaurant("missing", RestaurantAdminUpdate(), admin())
    assert exc.value.status_code == 404
