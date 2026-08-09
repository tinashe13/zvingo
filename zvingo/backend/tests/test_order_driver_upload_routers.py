from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.order.schemas import OrderCreate, OrderItem, OrderUpdateState
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


def user(id="user-1", **overrides):
    values = {"id": id, "role": "consumer", "save": AsyncMock()}
    values.update(overrides)
    return SimpleNamespace(**values)


def order(**overrides):
    values = {
        "id": "order-1",
        "state": OrderState.CREATED,
        "total_amount": 12.5,
        "created_at": datetime.now(),
        "updated_at": datetime.now(),
        "driver_id": "driver-1",
        "merchant_id": "restaurant-1",
        "consumer_id": "user-1",
        "items": [SimpleNamespace(name="Meal", quantity=2, price=5.0), {"name": "Drink"}],
        "pickup_location": {"coordinates": [31.0, -17.0]},
        "dropoff_location": {"coordinates": [31.1, -17.1]},
    }
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
async def test_order_helpers_get_and_access(monkeypatch):
    import app.order.router as module
    import app.catalog.models as catalog_models

    current = order()

    class FakeUser:
        get = AsyncMock(return_value=SimpleNamespace(full_name="Driver Name"))

    class FakeOrder:
        get = AsyncMock(return_value=current)

    class FakeRestaurant:
        get = AsyncMock(return_value=SimpleNamespace(merchant_id="merchant-user"))

    monkeypatch.setattr(module, "User", FakeUser)
    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)

    assert await module._get_driver_name(None) is None
    assert await module._get_driver_name("driver-1") == "Driver Name"
    FakeUser.get.return_value = None
    assert await module._get_driver_name("missing") is None
    FakeUser.get.side_effect = RuntimeError("db")
    assert await module._get_driver_name("broken") is None
    FakeUser.get.side_effect = None
    FakeUser.get.return_value = SimpleNamespace(full_name="Driver Name")

    await module._assert_order_access(current, user())
    await module._assert_order_access(current, user("driver-1"))
    await module._assert_order_access(current, user("merchant-user"))
    FakeRestaurant.get.side_effect = RuntimeError("db")
    with pytest.raises(HTTPException) as exc:
        await module._assert_order_access(current, user("stranger"))
    assert exc.value.status_code == 403

    class Redis:
        geopos = AsyncMock(return_value=[(31.25, -17.75)])
        close = AsyncMock()

    import redis.asyncio as aioredis
    monkeypatch.setattr(aioredis, "from_url", lambda *args, **kwargs: Redis())
    result = await module.get_order("order-1", user())
    assert result["driver_name"] == "Driver Name"
    assert result["driver_lat"] == -17.75
    assert result["items"][1] == {"name": "Drink", "quantity": 1, "price": 0}

    current.state = "OrderState.CREATED"
    current.driver_id = None
    current.created_at = None
    current.pickup_location = None
    current.dropoff_location = None
    result = await module.get_order("order-1", user())
    assert result["state"] == "CREATED"
    assert result["driver_lat"] is None

    current.driver_id = "driver-1"
    monkeypatch.setattr(aioredis, "from_url", lambda *args, **kwargs: (_ for _ in ()).throw(RuntimeError("redis")))
    assert (await module.get_order("order-1", user()))["driver_lat"] is None

    FakeOrder.get.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.get_order("missing", user())
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_order_cancel_create_and_state_update(monkeypatch):
    import app.order.router as module

    current = order(driver_id=None)

    class FakeOrder:
        get = AsyncMock(return_value=current)

    monkeypatch.setattr(module, "Order", FakeOrder)
    transition = AsyncMock(return_value=current)
    monkeypatch.setattr(module.OrderService, "transition_state", transition)

    FakeOrder.get.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.cancel_order("missing", user())
    assert exc.value.status_code == 404
    FakeOrder.get.return_value = current
    with pytest.raises(HTTPException) as exc:
        await module.cancel_order("order-1", user("other"))
    assert exc.value.status_code == 403
    current.state = "OrderState.DELIVERED"
    with pytest.raises(HTTPException) as exc:
        await module.cancel_order("order-1", user())
    assert exc.value.status_code == 400
    current.state = OrderState.CREATED
    assert (await module.cancel_order("order-1", user()))["status"] == "cancelled"
    transition.side_effect = InvalidStateTransition("invalid")
    with pytest.raises(HTTPException) as exc:
        await module.cancel_order("order-1", user())
    assert exc.value.detail == "invalid"

    payload = OrderCreate(
        merchant_id="restaurant-1", consumer_id="user-1",
        items=[OrderItem(name="Meal", quantity=1, price=5)], total_amount=5,
        pickup_lat=-17, pickup_lng=31, dropoff_lat=-18, dropoff_lng=32,
    )
    transition.side_effect = None
    monkeypatch.setattr(module.OrderService, "create_order", AsyncMock(return_value=order(driver_id=None)))
    created = await module.create_order(payload)
    assert created.id == "order-1"
    module.OrderService.create_order.side_effect = ValueError("bad order")
    with pytest.raises(HTTPException) as exc:
        await module.create_order(payload)
    assert exc.value.detail == "bad order"

    module.OrderService.transition_state = AsyncMock(return_value=order(items=[
        {"name": "Meal", "quantity": 1, "price": 5},
        OrderItem(name="Drink", quantity=1, price=2),
    ]))
    response = await module.update_order_state(
        "order-1", OrderUpdateState(state=OrderState.ACCEPTED, driver_id="driver-1"), "token"
    )
    assert response.state == OrderState.CREATED
    module.OrderService.transition_state.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.update_order_state("missing", OrderUpdateState(state=OrderState.ACCEPTED), "token")
    assert exc.value.status_code == 404
    module.OrderService.transition_state.side_effect = InvalidStateTransition("no")
    with pytest.raises(HTTPException) as exc:
        await module.update_order_state("order-1", OrderUpdateState(state=OrderState.ACCEPTED), "token")
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_order_lists_confirmation_and_driver_active(monkeypatch):
    import app.order.router as module
    import app.catalog.models as catalog_models
    import app.order.models as order_models

    current = order(driver_id="driver-1")

    class FakeOrder:
        consumer_id = Field()
        merchant_id = Field()
        driver_id = Field()
        created_at = Field()
        get = AsyncMock(return_value=current)
        found = [current]

        @classmethod
        def find(cls, *args):
            return Query(cls.found)

    class FakeRestaurant:
        merchant_id = Field()

        @classmethod
        def find(cls, *args):
            return Query([SimpleNamespace(id="restaurant-1")])

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(order_models, "Order", FakeOrder)
    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    with pytest.raises(HTTPException):
        await module.get_consumer_orders("user-1", user("other"))
    assert len(await module.get_consumer_orders("user-1", user())) == 1

    with pytest.raises(HTTPException):
        await module.get_merchant_orders("merchant-user", user("other"))
    merchant_orders = await module.get_merchant_orders("merchant-user", user("merchant-user"))
    assert len(merchant_orders) == 1
    FakeRestaurant.find = classmethod(lambda cls, *args: Query([]))
    assert await module.get_merchant_orders("merchant-user", user("merchant-user")) == []

    FakeOrder.get.return_value = None
    with pytest.raises(HTTPException):
        await module.consumer_confirm_delivery("missing", user())
    FakeOrder.get.return_value = current
    with pytest.raises(HTTPException):
        await module.consumer_confirm_delivery("order-1", user("other"))
    current.state = OrderState.CREATED.value
    with pytest.raises(HTTPException):
        await module.consumer_confirm_delivery("order-1", user())
    current.state = OrderState.PICKED_UP.value
    monkeypatch.setattr(module.OrderService, "transition_state", AsyncMock(return_value=current))
    assert (await module.consumer_confirm_delivery("order-1", user()))["status"] == "delivered"
    module.OrderService.transition_state.side_effect = InvalidStateTransition("no")
    with pytest.raises(HTTPException):
        await module.consumer_confirm_delivery("order-1", user())

    active = await module.get_driver_active_orders(user("driver-1"))
    assert len(active) == 1


@pytest.mark.asyncio
async def test_driver_dash_session(monkeypatch):
    import app.driver.router as module

    current = user("driver-1", is_dashing=False, current_location=None, dash_radius=0)
    update = AsyncMock()
    hset = AsyncMock()
    monkeypatch.setattr(module.dispatch_service, "update_location", update)
    monkeypatch.setattr(module.dispatch_service, "redis", SimpleNamespace(hset=hset))
    result = await module.update_dash_session(
        module.DashSessionRequest(active=True, lat=-17, lng=31, radius=5), current
    )
    assert result["is_dashing"] is True
    assert current.current_location.coordinates == [31, -17]
    update.assert_awaited_once()

    await module.update_dash_session(module.DashSessionRequest(active=False), current)
    hset.assert_awaited_once_with("driver:driver-1", "status", "OFFLINE")
    await module.update_dash_session(module.DashSessionRequest(active=True), current)
    assert current.save.await_count == 3


@pytest.mark.asyncio
async def test_upload_validation_success_and_failure(monkeypatch, tmp_path):
    import app.upload.router as module

    class Upload:
        def __init__(self, filename, content):
            self.filename = filename
            self.read = AsyncMock(return_value=content)

    with pytest.raises(HTTPException) as exc:
        await module.upload_file(Upload("bad.exe", b"x"), user())
    assert exc.value.status_code == 400
    monkeypatch.setattr(module, "MAX_FILE_SIZE", 2)
    with pytest.raises(HTTPException) as exc:
        await module.upload_file(Upload("large.png", b"123"), user())
    assert exc.value.status_code == 400

    monkeypatch.setattr(module, "UPLOAD_DIR", tmp_path)
    result = await module.upload_file(Upload(None, b"ok"), user())
    assert result["url"].endswith(".jpg")
    assert len(list(tmp_path.iterdir())) == 1

    monkeypatch.setattr(module, "UPLOAD_DIR", Path("missing") / "nested")
    with pytest.raises(HTTPException) as exc:
        await module.upload_file(Upload("image.png", b"ok"), user())
    assert exc.value.status_code == 500
