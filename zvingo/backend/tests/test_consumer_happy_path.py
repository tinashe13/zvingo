"""Consumer lifecycle happy-path integration tests.

Exercises the consumer order flow end-to-end at the router/service level using
the same ``SimpleNamespace`` + ``AsyncMock`` + ``monkeypatch`` style used
elsewhere in the suite (no real DB/Redis).

Scenarios:
  1. Create an order with nested ``Location`` objects.
  2. Create an order with legacy flat lat/lng fields (backward compatibility).
  3. Resolve a (0,0) pickup sentinel from the restaurant record; reject when unresolved.
  4. List own orders (ownership enforced) and cancel a cancellable order.
  5. Confirm delivery, transitioning the order to DELIVERED.
"""

from datetime import datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from app.location.models import Location
from app.order.schemas import OrderCreate, OrderItem
from app.order.state_machine import InvalidStateTransition, OrderState


class Field:
    def __eq__(self, value):
        return ("eq", value)

    def __neg__(self):
        return self


class Query:
    def __init__(self, values=None):
        self.values = list(values or [])

    def sort(self, *args):
        return self

    async def to_list(self):
        return self.values


def user(id="consumer-1", role="consumer"):
    return SimpleNamespace(id=id, role=role, save=AsyncMock())


def order_input(**overrides):
    values = {
        "merchant_id": "merchant-1",
        "consumer_id": "consumer-1",
        "items": [OrderItem(name="Burger", quantity=2, price=10)],
        "total_amount": 22,
        "pickup": Location.from_lat_lng(-17.8, 31.0),
        "dropoff": Location.from_lat_lng(-17.9, 31.1),
    }
    values.update(overrides)
    return OrderCreate(**values)


def order(**overrides):
    values = {
        "id": "order-1",
        "state": OrderState.CREATED,
        "total_amount": 22,
        "created_at": datetime.now(),
        "updated_at": datetime.now(),
        "driver_id": None,
        "merchant_id": "restaurant-1",
        "consumer_id": "consumer-1",
        "items": [SimpleNamespace(name="Burger", quantity=2, price=10)],
        "pickup_location": Location.from_lat_lng(-17.8, 31.0),
        "dropoff_location": Location.from_lat_lng(-17.9, 31.1),
        "events": [],
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
async def test_consumer_creates_order_with_nested_locations(monkeypatch):
    import app.dispatch.service as dispatch_module
    import app.notification.service as notification_module
    import app.order.service as module

    class FakeOrder:
        idempotency_key = Field()
        find_one = AsyncMock(return_value=None)
        instances = []

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "order-1"
            self.insert = AsyncMock(side_effect=lambda: FakeOrder.instances.append(self))
            self.delivery_fee = 0

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(notification_module.notification_service, "notify_merchant", AsyncMock())
    monkeypatch.setattr(dispatch_module.dispatch_service, "dispatch_order", AsyncMock())
    monkeypatch.setattr(
        module.asyncio,
        "create_task",
        lambda coro: (coro.close(), MagicMock())[1],
    )

    created = await module.OrderService.create_order(order_input())

    assert created.pickup_location.lat == -17.8
    assert created.pickup_location.lng == 31.0
    assert created.dropoff_location.lat == -17.9
    assert created.dropoff_location.lng == 31.1
    assert created.delivery_fee > 0
    created.insert.assert_awaited_once()


@pytest.mark.asyncio
async def test_consumer_creates_order_with_legacy_flat_fields(monkeypatch):
    import app.dispatch.service as dispatch_module
    import app.notification.service as notification_module
    import app.order.service as module

    class FakeOrder:
        idempotency_key = Field()
        find_one = AsyncMock(return_value=None)

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "order-1"
            self.insert = AsyncMock()
            self.delivery_fee = 0

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(notification_module.notification_service, "notify_merchant", AsyncMock())
    monkeypatch.setattr(dispatch_module.dispatch_service, "dispatch_order", AsyncMock())
    monkeypatch.setattr(
        module.asyncio,
        "create_task",
        lambda coro: (coro.close(), MagicMock())[1],
    )

    legacy = order_input(
        pickup=None,
        dropoff=None,
        pickup_lat=-17.8,
        pickup_lng=31.0,
        dropoff_lat=-17.9,
        dropoff_lng=31.1,
    )
    created = await module.OrderService.create_order(legacy)

    assert created.pickup_location.coordinates == [31.0, -17.8]
    assert created.dropoff_location.coordinates == [31.1, -17.9]


@pytest.mark.asyncio
async def test_consumer_pickup_resolution_and_unresolved_rejection(monkeypatch):
    import app.catalog.models as catalog_models
    import app.dispatch.service as dispatch_module
    import app.notification.service as notification_module
    import app.order.service as module

    class FakeOrder:
        idempotency_key = Field()
        find_one = AsyncMock(return_value=None)

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "order-1"
            self.insert = AsyncMock()
            self.delivery_fee = 0

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(notification_module.notification_service, "notify_merchant", AsyncMock())
    monkeypatch.setattr(dispatch_module.dispatch_service, "dispatch_order", AsyncMock())
    monkeypatch.setattr(
        module.asyncio,
        "create_task",
        lambda coro: (coro.close(), MagicMock())[1],
    )

    restaurant = SimpleNamespace(
        id="restaurant-1", name="Cafe", location=Location.from_lat_lng(-17.7, 31.2)
    )

    class FakeRestaurant:
        merchant_id = Field()
        get = AsyncMock(return_value=None)
        find_one = AsyncMock(return_value=restaurant)

    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)

    # Pickup sentinel (0,0) resolves from the restaurant record.
    resolved = await module.OrderService.create_order(
        order_input(pickup=Location.from_lat_lng(0, 0))
    )
    assert resolved.pickup_location.coordinates == [31.2, -17.7]

    # No restaurant location and no valid pickup → rejected.
    FakeRestaurant.find_one.return_value = SimpleNamespace(location=None)
    with pytest.raises(ValueError, match="Pickup location unresolved"):
        await module.OrderService.create_order(order_input(pickup=Location.from_lat_lng(0, 0)))


@pytest.mark.asyncio
async def test_consumer_lists_and_cancels_own_order(monkeypatch):
    import app.order.router as module

    current = order(state=OrderState.CREATED)

    class FakeOrder:
        consumer_id = Field()
        created_at = Field()
        get = AsyncMock(return_value=current)
        found = [current]

        @classmethod
        def find(cls, *args):
            return Query(cls.found)

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(
        module.OrderService, "transition_state", AsyncMock(return_value=current)
    )

    # Ownership check.
    with pytest.raises(HTTPException) as exc:
        await module.get_consumer_orders("consumer-1", user("other"))
    assert exc.value.status_code == 403

    listing = await module.get_consumer_orders("consumer-1", user())
    assert len(listing) == 1
    assert listing[0].id == "order-1"

    # Cancel (consumer owns it, state is cancellable).
    assert (await module.cancel_order("order-1", user()))["status"] == "cancelled"

    # A non-owner cannot cancel.
    with pytest.raises(HTTPException) as exc:
        await module.cancel_order("order-1", user("other"))
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_consumer_confirms_delivery(monkeypatch):
    import app.order.models as order_models
    import app.order.router as module

    current = order(state=OrderState.PICKED_UP)

    class FakeOrder:
        get = AsyncMock(return_value=current)

    # consumer_confirm_delivery imports Order locally from app.order.models.
    monkeypatch.setattr(order_models, "Order", FakeOrder)
    monkeypatch.setattr(
        module.OrderService, "transition_state", AsyncMock(return_value=current)
    )

    result = await module.consumer_confirm_delivery("order-1", user())
    assert result["status"] == "delivered"

    # A non-owner cannot confirm delivery.
    with pytest.raises(HTTPException) as exc:
        await module.consumer_confirm_delivery("order-1", user("other"))
    assert exc.value.status_code == 403

    # Confirmation is only allowed when the driver has arrived/picked up.
    current.state = OrderState.CREATED
    with pytest.raises(HTTPException) as exc:
        await module.consumer_confirm_delivery("order-1", user())
    assert exc.value.status_code == 400

    # Invalid transition from a valid-but-unexpected state is surfaced.
    current.state = OrderState.PICKED_UP
    module.OrderService.transition_state.side_effect = InvalidStateTransition("no")
    with pytest.raises(HTTPException) as exc:
        await module.consumer_confirm_delivery("order-1", user())
    assert exc.value.status_code == 400
