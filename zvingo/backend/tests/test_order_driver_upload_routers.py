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

    def skip(self, *_args):
        return self

    def limit(self, *_args):
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
        "delivery_instructions": None,
        "group_id": None,
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
    created = await module.create_order(payload, user())
    assert created.id == "order-1"
    module.OrderService.create_order.side_effect = ValueError("bad order")
    with pytest.raises(HTTPException) as exc:
        await module.create_order(payload, user())
    assert exc.value.detail == "bad order"

    module.OrderService.transition_state = AsyncMock(return_value=order(items=[
        {"name": "Meal", "quantity": 1, "price": 5},
        OrderItem(name="Drink", quantity=1, price=2),
    ]))
    FakeOrder.get.return_value = current
    # DELIVERED is one of the two states a consumer's role may reach.
    response = await module.update_order_state(
        "order-1", OrderUpdateState(state=OrderState.DELIVERED), user()
    )
    assert response.state == OrderState.CREATED
    # Role check: a consumer cannot advance their own order into ACCEPTED —
    # that would take it out of the dispatch pool with no driver on it.
    with pytest.raises(HTTPException) as exc:
        await module.update_order_state("order-1", OrderUpdateState(state=OrderState.ACCEPTED), user())
    assert exc.value.status_code == 403
    # Ownership check: a consumer may not mutate someone else's order.
    with pytest.raises(HTTPException) as exc:
        await module.update_order_state("order-1", OrderUpdateState(state=OrderState.DELIVERED), user("other"))
    assert exc.value.status_code == 403
    FakeOrder.get.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.update_order_state("missing", OrderUpdateState(state=OrderState.DELIVERED), user())
    assert exc.value.status_code == 404
    FakeOrder.get.return_value = current
    module.OrderService.transition_state.side_effect = InvalidStateTransition("no")
    with pytest.raises(HTTPException) as exc:
        await module.update_order_state("order-1", OrderUpdateState(state=OrderState.DELIVERED), user())
    assert exc.value.status_code == 400

    # The order was found for the access check but the transition returned
    # None (e.g. it was deleted concurrently) — surface a 404.
    module.OrderService.transition_state.side_effect = None
    module.OrderService.transition_state.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.update_order_state("order-1", OrderUpdateState(state=OrderState.DELIVERED), user())
    assert exc.value.status_code == 404


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
async def test_driver_schedule_get_and_save():
    import app.driver.router as module

    current = user("driver-1", schedule=[], vehicle=None)
    assert (await module.get_schedule(current))["days"] == []

    req = module.ScheduleUpdate(days=[module.ScheduleDay(day=0, slots=[0, 1])])
    result = await module.save_schedule(req, current)
    assert result["days"][0]["slots"] == [0, 1]
    assert current.schedule == result["days"]
    assert current.save.await_count == 1

    # Two entries for the same weekday are a client bug, not a merge.
    with pytest.raises(HTTPException):
        await module.save_schedule(
            module.ScheduleUpdate(
                days=[module.ScheduleDay(day=1, slots=[0]), module.ScheduleDay(day=1, slots=[1])]
            ),
            current,
        )


@pytest.mark.asyncio
async def test_driver_vehicle_get_and_save():
    import app.driver.router as module

    current = user("driver-1", schedule=[], vehicle=None)
    assert (await module.get_vehicle(current))["vehicle"] is None

    result = await module.save_vehicle(
        module.VehicleUpdate(make="Toyota", color="Red"), current
    )
    assert result["vehicle"] == {"make": "Toyota", "color": "Red"}
    assert current.vehicle == {"make": "Toyota", "color": "Red"}

    # Merge into the existing vehicle rather than replacing it.
    result = await module.save_vehicle(module.VehicleUpdate(model="Corolla"), current)
    assert result["vehicle"] == {"make": "Toyota", "color": "Red", "model": "Corolla"}
    assert current.save.await_count == 2


@pytest.mark.asyncio
async def test_order_location_helper_handles_location_and_legacy_dict():
    import app.order.router as module
    from app.location.models import Location

    loc = Location.from_lat_lng(-17.0, 31.0)
    assert module._lat(loc) == -17.0
    assert module._lng(loc) == 31.0
    assert module._lat(None) is None
    assert module._lng(None) is None
    assert module._lat({"coordinates": [31.0, -17.0]}) == -17.0
    assert module._lng({"coordinates": [31.0, -17.0]}) == 31.0
    assert module._lat({"coordinates": []}) is None
    assert module._lng({}) is None
    assert module._lat("not-a-location") is None
    assert module._lng("not-a-location") is None


@pytest.mark.asyncio
async def test_upload_validation_success_and_failure(monkeypatch, tmp_path):
    """The upload route trusts the bytes, not the name or the declared type."""
    import app.upload.router as module

    png = b"\x89PNG\r\n\x1a\n" + b"0" * 32

    class Upload:
        """Streaming stand-in for UploadFile: read() drains, like the real one."""

        def __init__(self, filename, content):
            self.filename = filename
            self._content = content
            self._offset = 0

        async def read(self, size=-1):
            if size is None or size < 0:
                chunk, self._offset = self._content[self._offset:], len(self._content)
                return chunk
            chunk = self._content[self._offset:self._offset + size]
            self._offset += len(chunk)
            return chunk

    # A dangerous extension is refused before the bytes are even read.
    with pytest.raises(HTTPException) as exc:
        await module.upload_file(Upload("shell.php", png), user())
    assert exc.value.status_code == 400

    # An extension that is merely unsupported is refused too.
    with pytest.raises(HTTPException) as exc:
        await module.upload_file(Upload("bad.exe", png), user())
    assert exc.value.status_code == 400

    # Oversized bodies are rejected while streaming, with 413.
    monkeypatch.setattr(module, "MAX_FILE_SIZE", 2)
    with pytest.raises(HTTPException) as exc:
        await module.upload_file(Upload("large.png", png), user())
    assert exc.value.status_code == 413
    monkeypatch.setattr(module, "MAX_FILE_SIZE", 5 * 1024 * 1024)

    # A .png name over non-image bytes is rejected by the magic-byte sniff.
    with pytest.raises(HTTPException) as exc:
        await module.upload_file(Upload("image.png", b"not an image at all"), user())
    assert exc.value.status_code == 400

    monkeypatch.setattr(module, "UPLOAD_DIR", tmp_path)
    result = await module.upload_file(Upload(None, png), user())
    assert result["url"].endswith(".png")
    assert result["content_type"] == "image/png"
    stored = list(tmp_path.iterdir())
    assert len(stored) == 1
    # The stored name is generated, never taken from the client.
    assert stored[0].name != "image.png"

    monkeypatch.setattr(module, "UPLOAD_DIR", Path("missing") / "nested")
    with pytest.raises(HTTPException) as exc:
        await module.upload_file(Upload("image.png", png), user())
    assert exc.value.status_code == 500
