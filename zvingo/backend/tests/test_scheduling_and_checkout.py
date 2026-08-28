"""Scheduled-order dispatch, multi-restaurant checkout, and shared order access."""

from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import asyncio
import pytest
from fastapi import HTTPException

from app.location.models import Location
from app.order.schemas import CheckoutBasket, CheckoutCreate, OrderItem
from app.order.state_machine import OrderState
from app.time_utils import utc_now


class Query:
    def __init__(self, values=None):
        self.values = list(values or [])

    def sort(self, *args):
        return self

    async def to_list(self):
        return self.values


def scheduled_order(id="order-1", **overrides):
    values = {
        "id": id,
        "merchant_id": "restaurant-1",
        "scheduled_at": utc_now(),
        "scheduled_dispatched": False,
        "pickup_location": Location.from_lat_lng(-17.8, 31.0),
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def basket(merchant_id="restaurant-1", subtotal=20.0, **overrides):
    values = {
        "merchant_id": merchant_id,
        "items": [OrderItem(name="Burger", quantity=1, price=subtotal)],
        "subtotal": subtotal,
    }
    values.update(overrides)
    return CheckoutBasket(**values)


def checkout(**overrides):
    values = {
        "baskets": [basket("restaurant-1", 20.0), basket("restaurant-2", 30.0)],
        "dropoff": Location.from_lat_lng(-17.9, 31.1),
        "tip_amount": 3.0,
    }
    values.update(overrides)
    return CheckoutCreate(**values)


# ── ScheduledOrderService ───────────────────────────────────────────


@pytest.mark.asyncio
async def test_due_orders_uses_the_dispatch_lead_window(monkeypatch):
    import app.dispatch.scheduler_service as module

    captured = {}

    def find(query):
        captured["query"] = query
        return Query([scheduled_order()])

    monkeypatch.setattr(module.Order, "find", find)
    monkeypatch.setattr(module.settings, "SCHEDULED_DISPATCH_LEAD_MINUTES", 15)

    due = await module.scheduled_order_service.due_orders()
    assert len(due) == 1
    query = captured["query"]
    assert query["state"] == OrderState.CREATED
    assert query["scheduled_dispatched"] == {"$ne": True}
    assert query["is_pickup"] == {"$ne": True}
    # The window reaches 15 minutes into the future.
    assert query["scheduled_at"]["$lte"] > utc_now() + timedelta(minutes=14)


@pytest.mark.asyncio
async def test_release_marks_and_dispatches_due_orders(monkeypatch):
    import app.dispatch.scheduler_service as module

    order = scheduled_order()
    monkeypatch.setattr(
        module.scheduled_order_service, "due_orders", AsyncMock(return_value=[order])
    )
    dispatch = AsyncMock()
    monkeypatch.setattr(module.dispatch_service, "dispatch_order", dispatch)

    assert await module.scheduled_order_service.release_due_orders() == 1
    assert order.scheduled_dispatched is True
    order.save.assert_awaited_once()
    dispatch.assert_awaited_once_with("order-1", -17.8, 31.0)


@pytest.mark.asyncio
async def test_release_resolves_a_missing_pickup_from_the_restaurant(monkeypatch):
    import app.catalog.models as catalog_models
    import app.dispatch.scheduler_service as module

    order = scheduled_order(pickup_location=Location.from_lat_lng(0.0, 0.0))
    monkeypatch.setattr(
        module.scheduled_order_service, "due_orders", AsyncMock(return_value=[order])
    )
    monkeypatch.setattr(module.dispatch_service, "dispatch_order", AsyncMock())
    restaurant = SimpleNamespace(location=Location.from_lat_lng(-17.7, 31.2))
    monkeypatch.setattr(
        catalog_models.Restaurant, "get", AsyncMock(return_value=restaurant)
    )

    assert await module.scheduled_order_service.release_due_orders() == 1
    assert order.pickup_location.lat == -17.7


@pytest.mark.asyncio
async def test_release_skips_orders_whose_pickup_cannot_be_resolved(monkeypatch):
    import app.catalog.models as catalog_models
    import app.dispatch.scheduler_service as module

    null_island = scheduled_order(pickup_location=Location.from_lat_lng(0.0, 0.0))
    no_location = scheduled_order(id="order-2", pickup_location=None)
    monkeypatch.setattr(
        module.scheduled_order_service,
        "due_orders",
        AsyncMock(return_value=[null_island, no_location]),
    )
    dispatch = AsyncMock()
    monkeypatch.setattr(module.dispatch_service, "dispatch_order", dispatch)

    # No restaurant at all, then a restaurant with no location, then a lookup error.
    monkeypatch.setattr(catalog_models.Restaurant, "get", AsyncMock(return_value=None))
    assert await module.scheduled_order_service.release_due_orders() == 0
    dispatch.assert_not_awaited()

    monkeypatch.setattr(
        catalog_models.Restaurant,
        "get",
        AsyncMock(return_value=SimpleNamespace(location=None)),
    )
    assert await module.scheduled_order_service.release_due_orders() == 0

    monkeypatch.setattr(
        catalog_models.Restaurant, "get", AsyncMock(side_effect=RuntimeError("db"))
    )
    assert await module.scheduled_order_service.release_due_orders() == 0


@pytest.mark.asyncio
async def test_release_isolates_a_failing_order(monkeypatch):
    import app.dispatch.scheduler_service as module

    broken = scheduled_order(save=AsyncMock(side_effect=RuntimeError("write failed")))
    good = scheduled_order(id="order-2")
    monkeypatch.setattr(
        module.scheduled_order_service,
        "due_orders",
        AsyncMock(return_value=[broken, good]),
    )
    monkeypatch.setattr(module.dispatch_service, "dispatch_order", AsyncMock())

    assert await module.scheduled_order_service.release_due_orders() == 1


@pytest.mark.asyncio
async def test_scheduler_lifecycle_and_loop_error_recovery(monkeypatch):
    import app.dispatch.scheduler_service as module

    service = module.ScheduledOrderService()
    monkeypatch.setattr(module.settings, "SCHEDULED_POLL_INTERVAL_SECONDS", 0)

    calls = []
    done = asyncio.Event()

    async def release():
        calls.append(1)
        if len(calls) == 1:
            raise RuntimeError("transient")
        done.set()
        return 0

    monkeypatch.setattr(service, "release_due_orders", release)
    await service.start()
    await service.start()  # already running
    await asyncio.wait_for(done.wait(), 1)
    await service.stop()
    await service.stop()  # idempotent
    assert len(calls) >= 2


# ── discount splitting ──────────────────────────────────────────────


def test_split_discount_is_proportional_and_exact():
    from app.order.service import OrderService

    parts = OrderService.split_discount(10.0, [20.0, 30.0])
    assert parts == [4.0, 6.0]
    assert sum(parts) == 10.0

    # Rounding remainders land on the largest basket.
    parts = OrderService.split_discount(10.0, [1.0, 1.0, 1.0])
    assert round(sum(parts), 2) == 10.0

    assert OrderService.split_discount(0.0, [5.0, 5.0]) == [0.0, 0.0]
    assert OrderService.split_discount(10.0, []) == []
    assert sum(OrderService.split_discount(10.0, [0.0, 0.0])) == 10.0


# ── checkout ────────────────────────────────────────────────────────


def test_checkout_schema_rejects_bad_baskets():
    with pytest.raises(ValueError):
        CheckoutCreate(baskets=[], dropoff=Location.from_lat_lng(-17.9, 31.1))

    with pytest.raises(ValueError) as exc:
        checkout(baskets=[basket("restaurant-1"), basket("restaurant-1")])
    assert "different restaurant" in str(exc.value)

    with pytest.raises(ValueError) as exc:
        checkout(baskets=[basket().model_copy(update={"items": []})])
    assert "at least one item" in str(exc.value)

    assert checkout().subtotal == 50.0


@pytest.mark.asyncio
async def test_create_checkout_splits_promo_and_shares_a_group(monkeypatch):
    import app.order.service as module

    created = []

    async def create_order(order_in, group_id=None, promo_override=None):
        created.append((order_in, group_id, promo_override))
        return SimpleNamespace(id=f"order-{len(created)}")

    monkeypatch.setattr(module.OrderService, "create_order", create_order)
    monkeypatch.setattr(
        "app.catalog.promotion_service.validate_and_compute",
        AsyncMock(return_value=(10.0, True)),
    )
    record = AsyncMock()
    monkeypatch.setattr("app.catalog.promotion_service.record_redemption", record)

    group_id, orders, discount = await module.OrderService.create_checkout(
        checkout(promo_code="SAVE10", idempotency_key="key-1"), "consumer-1"
    )

    assert len(orders) == 2
    assert discount == 10.0
    assert {g for _, g, _ in created} == {group_id}

    # The promo is split proportionally and free delivery applies once.
    assert [override for _, _, override in created] == [(4.0, True), (6.0, False)]
    # The tip belongs to the basket as a whole, not to each restaurant.
    assert [o.tip_amount for o, _, _ in created] == [3.0, 0.0]
    # Idempotency keys are derived per basket so a retry is still safe.
    assert [o.idempotency_key for o, _, _ in created] == [
        "key-1:restaurant-1",
        "key-1:restaurant-2",
    ]
    record.assert_awaited_once_with("SAVE10", "consumer-1")


@pytest.mark.asyncio
async def test_create_checkout_without_a_promo(monkeypatch):
    import app.order.service as module

    created = []

    async def create_order(order_in, group_id=None, promo_override=None):
        created.append(order_in)
        return SimpleNamespace(id="order-1")

    monkeypatch.setattr(module.OrderService, "create_order", create_order)
    _, orders, discount = await module.OrderService.create_checkout(
        checkout(baskets=[basket()]), "consumer-1"
    )
    assert discount == 0.0
    assert len(orders) == 1
    assert created[0].idempotency_key is None


@pytest.mark.asyncio
async def test_create_checkout_rejects_an_invalid_promo(monkeypatch):
    import app.catalog.promotion_service as promo_module
    import app.order.service as module

    monkeypatch.setattr(
        promo_module,
        "validate_and_compute",
        AsyncMock(side_effect=promo_module.PromotionError("expired")),
    )
    with pytest.raises(ValueError) as exc:
        await module.OrderService.create_checkout(
            checkout(promo_code="OLD"), "consumer-1"
        )
    assert "expired" in str(exc.value)


@pytest.mark.asyncio
async def test_create_order_honours_group_and_promo_override(monkeypatch):
    import app.order.service as module
    from app.order.schemas import OrderCreate

    inserted = {}

    class FakeOrder:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.delivery_fee = kwargs.get("delivery_fee", 0.0)
            self.id = "order-1"

        async def insert(self):
            inserted["order"] = self

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(
        "app.notification.service.notification_service.notify_merchant", AsyncMock()
    )
    monkeypatch.setattr(
        "app.dispatch.service.dispatch_service.dispatch_order", AsyncMock()
    )
    record = AsyncMock()
    monkeypatch.setattr("app.catalog.promotion_service.record_redemption", record)

    order_in = OrderCreate(
        merchant_id="restaurant-1",
        consumer_id="consumer-1",
        items=[OrderItem(name="Burger", quantity=1, price=20.0)],
        total_amount=20.0,
        pickup=Location.from_lat_lng(-17.8, 31.0),
        dropoff=Location.from_lat_lng(-17.9, 31.1),
        promo_code="SAVE10",
    )
    order = await module.OrderService.create_order(
        order_in, group_id="group-1", promo_override=(5.0, True)
    )
    await asyncio.sleep(0)

    assert order.group_id == "group-1"
    assert order.discount_amount == 5.0
    # Free delivery from the override waives the fee...
    assert order.delivery_fee == 0.0
    # ...and the caller owns redemption, so it is not recorded twice.
    record.assert_not_awaited()


# ── checkout & group endpoints ──────────────────────────────────────


@pytest.mark.asyncio
async def test_checkout_endpoint_returns_the_group(monkeypatch):
    import app.order.router as module

    orders = [
        SimpleNamespace(
            id="order-1",
            state=OrderState.CREATED,
            total_amount=20.0,
            created_at=utc_now(),
            driver_id=None,
            merchant_id="restaurant-1",
            consumer_id="consumer-1",
            items=[],
            pickup_location=None,
            dropoff_location=None,
            delivery_instructions=None,
            group_id="group-1",
        )
    ]
    monkeypatch.setattr(
        module.OrderService,
        "create_checkout",
        AsyncMock(return_value=("group-1", orders, 4.0)),
    )
    response = await module.checkout(
        checkout(promo_code="SAVE10"), SimpleNamespace(id="consumer-1")
    )
    assert response.group_id == "group-1"
    assert response.discount_total == 4.0
    assert response.subtotal == 50.0
    assert response.orders[0].group_id == "group-1"

    monkeypatch.setattr(
        module.OrderService,
        "create_checkout",
        AsyncMock(side_effect=ValueError("bad promo")),
    )
    with pytest.raises(HTTPException) as exc:
        await module.checkout(checkout(), SimpleNamespace(id="consumer-1"))
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_order_group_endpoint_checks_access(monkeypatch):
    import app.order.router as module

    order = SimpleNamespace(
        id="order-1",
        state=OrderState.CREATED,
        total_amount=20.0,
        created_at=utc_now(),
        driver_id=None,
        merchant_id="restaurant-1",
        consumer_id="consumer-1",
        items=[],
        pickup_location=None,
        dropoff_location=None,
        delivery_instructions=None,
        group_id="group-1",
    )
    monkeypatch.setattr(module.Order, "find", lambda *a, **k: Query([order]))
    monkeypatch.setattr(module.Order, "group_id", MagicMock(), raising=False)
    monkeypatch.setattr(module.Order, "created_at", MagicMock(), raising=False)

    consumer = SimpleNamespace(id="consumer-1")
    result = await module.get_order_group("group-1", consumer)
    assert len(result) == 1

    with pytest.raises(HTTPException) as exc:
        await module.get_order_group("group-1", SimpleNamespace(id="stranger"))
    assert exc.value.status_code == 403

    monkeypatch.setattr(module.Order, "find", lambda *a, **k: Query([]))
    with pytest.raises(HTTPException) as exc:
        await module.get_order_group("missing", consumer)
    assert exc.value.status_code == 404


# ── shared order access ─────────────────────────────────────────────


@pytest.mark.asyncio
async def test_owning_merchant_id_resolution(monkeypatch):
    import app.catalog.models as catalog_models
    from app.order.access import owning_merchant_id

    order = SimpleNamespace(merchant_id="restaurant-1")
    monkeypatch.setattr(
        catalog_models.Restaurant,
        "get",
        AsyncMock(return_value=SimpleNamespace(merchant_id="merchant-1")),
    )
    assert await owning_merchant_id(order) == "merchant-1"

    monkeypatch.setattr(catalog_models.Restaurant, "get", AsyncMock(return_value=None))
    assert await owning_merchant_id(order) is None

    monkeypatch.setattr(
        catalog_models.Restaurant, "get", AsyncMock(side_effect=RuntimeError("db"))
    )
    assert await owning_merchant_id(order) is None
