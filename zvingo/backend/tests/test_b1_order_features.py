"""Order features that were reported missing but already exist — verified here.

Reorder, group (multi-restaurant) orders and scheduled orders are all in the
codebase. These tests pin the behaviour that was actually wrong: a reorder
inherited a stale delivery fee, dispatched a driver for a self-pickup order, and
would happily create an order with no delivery address.
"""

from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.location.models import Location
from app.order.state_machine import OrderState
from app.time_utils import utc_now


def item(name="Burger", quantity=1, price=10.0):
    return SimpleNamespace(
        name=name,
        quantity=quantity,
        price=price,
        model_dump=MagicMock(
            return_value={"name": name, "quantity": quantity, "price": price}
        ),
    )


def original_order(**overrides):
    values = {
        "id": "order-1",
        "merchant_id": "restaurant-1",
        "consumer_id": "consumer-1",
        "items": [item()],
        "total_amount": 22.0,
        "pickup_location": Location.from_lat_lng(-17.80, 31.00),
        "dropoff_location": Location.from_lat_lng(-17.90, 31.10),
        "delivery_instructions": "Gate 4",
        "tip_amount": 1.0,
        # A fee quoted long ago — a reorder must not inherit it blindly.
        "delivery_fee": 99.0,
        "service_fee": 1.0,
        "tax_amount": 0.5,
        "is_pickup": False,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def install(monkeypatch, original):
    """Wire OrderService.reorder to doubles.

    Returns (created_orders, dispatch_calls, run_background) — dispatch happens
    in a background task, so the caller awaits `run_background()` to let it run.
    """
    import app.dispatch.service as dispatch_module
    import app.notification.service as notification_module
    import app.order.service as module

    created = []

    class FakeOrder:
        get = AsyncMock(return_value=original)

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "order-2"
            self.insert = AsyncMock(side_effect=lambda: created.append(self))

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(
        notification_module.notification_service, "notify_merchant", AsyncMock()
    )
    dispatched = []
    monkeypatch.setattr(
        dispatch_module.dispatch_service,
        "dispatch_order",
        AsyncMock(side_effect=lambda *a, **k: dispatched.append(a)),
    )
    pending = []
    monkeypatch.setattr(
        module.asyncio,
        "create_task",
        lambda coro: (pending.append(coro), MagicMock())[1],
    )

    async def run_background():
        while pending:
            await pending.pop(0)

    return created, dispatched, run_background


@pytest.mark.asyncio
async def test_reorder_requotes_the_delivery_fee(monkeypatch):
    import app.order.service as module

    original = original_order()
    created, dispatched, run_background = install(monkeypatch, original)

    new_order = await module.OrderService.reorder("order-1", "consumer-1")
    await run_background()

    assert new_order.merchant_id == "restaurant-1"
    assert new_order.items == [{"name": "Burger", "quantity": 1, "price": 10.0}]
    assert new_order.delivery_instructions == "Gate 4"
    # The stale $99 fee is replaced by a fee computed from today's distance.
    assert new_order.delivery_fee != 99.0
    assert new_order.delivery_fee > 0
    assert len(dispatched) == 1


@pytest.mark.asyncio
async def test_reordering_a_self_pickup_order_does_not_summon_a_driver(monkeypatch):
    import app.order.service as module

    original = original_order(is_pickup=True, delivery_fee=5.0)
    created, dispatched, run_background = install(monkeypatch, original)

    new_order = await module.OrderService.reorder("order-1", "consumer-1")
    await run_background()

    assert new_order.is_pickup is True
    assert new_order.delivery_fee == 0.0
    assert dispatched == [], "a self-pickup order has no driver to dispatch"


@pytest.mark.asyncio
async def test_reorder_records_where_it_came_from(monkeypatch):
    import app.order.service as module

    original = original_order()
    _, _, run_background = install(monkeypatch, original)

    new_order = await module.OrderService.reorder("order-1", "consumer-1")
    await run_background()

    event = new_order.events[0]
    assert event.state is OrderState.CREATED
    assert event.reason == "reorder"
    assert event.metadata["source_order_id"] == "order-1"
    assert event.actor_id == "consumer-1"


@pytest.mark.asyncio
async def test_reorder_without_a_delivery_address_is_refused(monkeypatch):
    import app.order.service as module

    original = original_order(dropoff_location=Location.from_lat_lng(0, 0))
    install(monkeypatch, original)

    with pytest.raises(ValueError, match="no delivery address"):
        await module.OrderService.reorder("order-1", "consumer-1")


@pytest.mark.asyncio
async def test_reorder_reresolves_a_missing_pickup_from_the_restaurant(monkeypatch):
    import app.catalog.models as catalog_models
    import app.order.service as module

    original = original_order(pickup_location=None)
    _, dispatched, run_background = install(monkeypatch, original)
    monkeypatch.setattr(
        catalog_models.Restaurant,
        "get",
        AsyncMock(return_value=SimpleNamespace(location=Location.from_lat_lng(-17.82, 31.05))),
    )

    new_order = await module.OrderService.reorder("order-1", "consumer-1")
    await run_background()

    assert new_order.pickup_location.lat == -17.82
    assert dispatched == [("order-2", -17.82, 31.05)]


@pytest.mark.asyncio
async def test_reorder_refuses_someone_elses_order_and_empty_orders(monkeypatch):
    import app.order.service as module

    original = original_order()
    install(monkeypatch, original)

    with pytest.raises(ValueError, match="Not your order"):
        await module.OrderService.reorder("order-1", "someone-else")

    original.items = []
    with pytest.raises(ValueError, match="empty"):
        await module.OrderService.reorder("order-1", "consumer-1")

    module.Order.get = AsyncMock(return_value=None)
    assert await module.OrderService.reorder("missing", "consumer-1") is None


# ── Scheduled orders ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_a_scheduled_order_is_not_dispatched_on_creation(monkeypatch):
    """The scheduler releases it near its slot; creating it must not offer it."""
    import app.order.service as module

    released = []

    class FakeOrder:
        instances = []

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "order-9"
            self.delivery_fee = 0
            self.insert = AsyncMock()

        @staticmethod
        async def find_one(*_a, **_k):
            return None

    import app.dispatch.service as dispatch_module
    import app.notification.service as notification_module
    from app.order.schemas import OrderCreate, OrderItem

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(
        notification_module.notification_service, "notify_merchant", AsyncMock()
    )
    monkeypatch.setattr(
        dispatch_module.dispatch_service,
        "dispatch_order",
        AsyncMock(side_effect=lambda *a, **k: released.append(a)),
    )
    monkeypatch.setattr(
        module.asyncio, "create_task", lambda coro: (coro.close(), MagicMock())[1]
    )

    await module.OrderService.create_order(
        OrderCreate(
            merchant_id="restaurant-1",
            consumer_id="consumer-1",
            items=[OrderItem(name="Burger", quantity=1, price=10)],
            total_amount=10,
            pickup=Location.from_lat_lng(-17.8, 31.0),
            dropoff=Location.from_lat_lng(-17.9, 31.1),
            scheduled_at=utc_now() + timedelta(hours=3),
        )
    )

    assert released == [], "a scheduled order waits for its window"


@pytest.mark.asyncio
async def test_the_scheduler_releases_an_order_once_and_only_once(monkeypatch):
    import app.dispatch.scheduler_service as module

    order = SimpleNamespace(
        id="order-9",
        merchant_id="restaurant-1",
        scheduled_at=utc_now(),
        scheduled_dispatched=False,
        pickup_location=Location.from_lat_lng(-17.8, 31.0),
        save=AsyncMock(),
    )
    monkeypatch.setattr(
        module.ScheduledOrderService, "due_orders", AsyncMock(return_value=[order])
    )
    dispatch = AsyncMock()
    monkeypatch.setattr(module.dispatch_service, "dispatch_order", dispatch)

    released = await module.scheduled_order_service.release_due_orders()

    assert released == 1
    # Marked before dispatching, so a crash mid-dispatch cannot double-release.
    assert order.scheduled_dispatched is True
    order.save.assert_awaited_once()
    dispatch.assert_awaited_once_with("order-9", -17.8, 31.0)


# ── Group orders ────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_a_group_order_is_only_visible_to_its_participants(monkeypatch):
    import app.order.router as module

    from datetime import datetime

    orders = [
        SimpleNamespace(
            id=f"order-{i}",
            state=OrderState.CREATED,
            total_amount=10.0,
            created_at=datetime(2026, 1, 1),
            driver_id=None,
            merchant_id=f"restaurant-{i}",
            consumer_id="consumer-1",
            items=[],
            pickup_location=None,
            dropoff_location=None,
            delivery_instructions=None,
            group_id="group-1",
        )
        for i in (1, 2)
    ]

    class Query:
        def __init__(self, values):
            self.values = values

        def sort(self, *_a):
            return self

        def limit(self, *_a):
            return self

        async def to_list(self):
            return self.values

    class Field:
        def __eq__(self, other):
            return ("eq", other)

        def __neg__(self):
            return self

    class FakeOrder:
        group_id = Field()
        created_at = Field()

        @classmethod
        def find(cls, *_args, **_kwargs):
            return Query(orders)

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(
        module, "require_order_participant", AsyncMock(side_effect=lambda o, u: o)
    )

    result = await module.get_order_group("group-1", SimpleNamespace(id="consumer-1"))
    assert [o.id for o in result] == ["order-1", "order-2"]
    assert all(o.group_id == "group-1" for o in result)

    from fastapi import HTTPException

    monkeypatch.setattr(
        module,
        "require_order_participant",
        AsyncMock(side_effect=HTTPException(status_code=403, detail="nope")),
    )
    with pytest.raises(HTTPException) as exc:
        await module.get_order_group("group-1", SimpleNamespace(id="stranger"))
    assert exc.value.status_code == 403


def test_checkout_splits_a_discount_without_losing_cents():
    from app.order.service import OrderService

    parts = OrderService.split_discount(10.0, [33.33, 33.33, 33.34])
    assert round(sum(parts), 2) == 10.0

    parts = OrderService.split_discount(5.0, [0.0, 0.0])
    assert round(sum(parts), 2) == 5.0

    assert OrderService.split_discount(0.0, [10.0]) == [0.0]


@pytest.mark.asyncio
async def test_two_pollers_cannot_release_the_same_scheduled_order(monkeypatch):
    """The release claim is conditional, so a scheduled order ships once."""
    import asyncio

    import app.order.service as module

    document = {"_id": "order-9", "scheduled_dispatched": False}

    class Collection:
        async def find_one_and_update(self, criteria, update):
            # Atomic: no await between the check and the write.
            condition = criteria["scheduled_dispatched"]["$ne"]
            if document["scheduled_dispatched"] is condition:
                return None
            document.update(update["$set"])
            return dict(document)

    monkeypatch.setattr(module, "_order_collection", lambda: Collection())
    monkeypatch.setattr(module, "_document_id", str)

    async def claim():
        order = SimpleNamespace(id="order-9", scheduled_dispatched=False, save=AsyncMock())
        await asyncio.sleep(0)
        return await module.OrderService.claim_scheduled_release(order)

    results = await asyncio.gather(claim(), claim(), claim())

    assert sum(1 for r in results if r) == 1
    assert document["scheduled_dispatched"] is True


@pytest.mark.asyncio
async def test_the_release_claim_persists_a_resolved_pickup(monkeypatch):
    import app.order.service as module

    written = {}

    class Collection:
        async def find_one_and_update(self, _criteria, update):
            written.update(update["$set"])
            return {"_id": "order-9"}

    monkeypatch.setattr(module, "_order_collection", lambda: Collection())
    monkeypatch.setattr(module, "_document_id", str)

    order = SimpleNamespace(id="order-9", scheduled_dispatched=False, save=AsyncMock())
    assert await module.OrderService.claim_scheduled_release(
        order, pickup=Location.from_lat_lng(-17.82, 31.05)
    )

    # Stored as GeoJSON so a later retry does not have to resolve it again.
    assert written["pickup_location"] == {"type": "Point", "coordinates": [31.05, -17.82]}


@pytest.mark.asyncio
async def test_reorder_refuses_when_the_pickup_cannot_be_resolved(monkeypatch):
    """Better a clear 400 than an order no driver can ever be sent to."""
    import app.catalog.models as catalog_models
    import app.order.service as module

    original = original_order(pickup_location=Location.from_lat_lng(0, 0))
    _, dispatched, _ = install(monkeypatch, original)
    monkeypatch.setattr(catalog_models.Restaurant, "get", AsyncMock(return_value=None))
    monkeypatch.setattr(
        catalog_models.Restaurant, "find_one", AsyncMock(return_value=None)
    )

    with pytest.raises(ValueError, match="pickup location is unavailable"):
        await module.OrderService.reorder("order-1", "consumer-1")
    assert dispatched == []
