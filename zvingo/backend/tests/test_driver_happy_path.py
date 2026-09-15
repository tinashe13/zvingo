"""Driver lifecycle happy-path integration tests.

These tests exercise the driver-facing surfaces directly (router handlers and
``DispatchService``) using the same mock patterns as the rest of the suite:
``SimpleNamespace`` + ``AsyncMock`` + ``monkeypatch``. No real MongoDB or Redis
is touched.
"""

import json
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.dispatch.schemas import DriverLocationUpdate
from app.order.state_machine import OrderState


def driver_user(id="driver-1", **overrides):
    """Build a lightweight driver user stand-in with an async ``save``."""
    values = {"id": id, "save": AsyncMock()}
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
async def test_driver_starts_dashing_syncs_location_and_persists(monkeypatch):
    import app.driver.router as module

    current = driver_user(
        "driver-1", is_dashing=False, current_location=None, dash_radius=0
    )
    update_location = AsyncMock()
    hset = AsyncMock()
    monkeypatch.setattr(module.dispatch_service, "update_location", update_location)
    monkeypatch.setattr(
        module.dispatch_service, "redis", SimpleNamespace(hset=hset)
    )

    result = await module.update_dash_session(
        module.DashSessionRequest(active=True, lat=-17.83, lng=31.05, radius=5),
        current,
    )

    assert result == {"status": "updated", "is_dashing": True}
    assert current.is_dashing is True
    assert current.dash_radius == 5

    # Location is persisted in GeoJSON [lng, lat] order.
    assert current.current_location.coordinates == [31.05, -17.83]
    assert current.current_location.lat == -17.83
    assert current.current_location.lng == 31.05

    # Redis geo-index sync is driven with the canonical lat/lng payload.
    update_location.assert_awaited_once()
    location_update = update_location.await_args.args[0]
    assert location_update.driver_id == "driver-1"
    assert location_update.lat == -17.83
    assert location_update.lng == 31.05
    assert location_update.status == "ONLINE"

    current.save.assert_awaited_once()
    hset.assert_not_awaited()


@pytest.mark.asyncio
async def test_driver_schedule_save_and_read():
    import app.driver.router as module

    current = driver_user("driver-1", schedule=[])
    empty = await module.get_schedule(current)
    assert empty["days"] == []
    # The schedule contract carries the timezone and shift windows the UI needs.
    assert empty["timezone"] == "Africa/Harare"
    assert empty["slot_windows"]["0"] == {
        "label": "Morning",
        "start": "06:00",
        "end": "12:00",
    }

    req = module.ScheduleUpdate(
        days=[
            module.ScheduleDay(day=0, slots=[0, 1]),
            module.ScheduleDay(day=3, slots=[2]),
        ]
    )
    result = await module.save_schedule(req, current)

    assert [d["day"] for d in result["days"]] == [0, 3]
    assert [d["slots"] for d in result["days"]] == [[0, 1], [2]]
    # Shift ids are expanded into explicit local time windows on save.
    assert result["days"][0]["windows"] == [
        {"slot": 0, "start": "06:00", "end": "12:00"},
        {"slot": 1, "start": "12:00", "end": "17:00"},
    ]
    assert current.schedule == result["days"]
    current.save.assert_awaited_once()
    assert (await module.get_schedule(current))["days"] == current.schedule


@pytest.mark.asyncio
async def test_driver_vehicle_save_merges_and_read():
    import app.driver.router as module

    current = driver_user("driver-1", vehicle=None)
    assert (await module.get_vehicle(current))["vehicle"] is None

    result = await module.save_vehicle(
        module.VehicleUpdate(make="Toyota", model="Corolla", color="Red"),
        current,
    )
    assert result["vehicle"] == {
        "make": "Toyota",
        "model": "Corolla",
        "color": "Red",
    }
    assert current.vehicle == result["vehicle"]

    # A second call must merge, not replace, the stored vehicle.
    result = await module.save_vehicle(module.VehicleUpdate(plate="ABC123"), current)
    assert result["vehicle"] == {
        "make": "Toyota",
        "model": "Corolla",
        "color": "Red",
        "plate": "ABC123",
    }
    assert current.save.await_count == 2
    assert (await module.get_vehicle(current))["vehicle"]["plate"] == "ABC123"


@pytest.mark.asyncio
async def test_driver_accepts_offer_transitions_order_and_creates_dispatch(monkeypatch):
    import app.dispatch.service as module
    import app.dispatch.models as dispatch_models
    import app.notification.service as notification_module
    import app.order.service as order_service_module

    fake_order = SimpleNamespace(
        id="order-1",
        state=OrderState.OFFERED,
        driver_id=None,
        consumer_id=None,
        updated_at=None,
        events=[],
        save=AsyncMock(),
    )
    monkeypatch.setattr(
        order_service_module,
        "Order",
        SimpleNamespace(get=AsyncMock(return_value=fake_order)),
    )

    inserted = AsyncMock()
    dispatch_kwargs = {}

    class FakeDispatch:
        def __init__(self, **kwargs):
            dispatch_kwargs.update(kwargs)
            self.insert = inserted

    monkeypatch.setattr(dispatch_models, "Dispatch", FakeDispatch)
    notify = AsyncMock()
    monkeypatch.setattr(
        notification_module.notification_service, "notify_consumer", notify
    )

    service = module.DispatchService()
    result = await service.accept_offer("driver-1", "order-1")

    assert result is fake_order
    assert fake_order.state == OrderState.ACCEPTED
    assert fake_order.driver_id == "driver-1"
    assert fake_order.save.await_count == 1

    assert dispatch_kwargs == {
        "order_id": "order-1",
        "driver_id": "driver-1",
        "status": "ASSIGNED",
    }
    inserted.assert_awaited_once()
    notify.assert_awaited_once_with(
        None, "order-1", "order_accepted", data={"driver_id": "driver-1"}
    )


@pytest.mark.asyncio
async def test_driver_declines_offer():
    import app.dispatch.service as module

    service = module.DispatchService()
    assert await service.decline_offer("driver-1", "order-1") == {"status": "declined"}


@pytest.mark.asyncio
async def test_driver_location_update_orders_redis_calls():
    import app.dispatch.service as module

    class RecordingRedis:
        def __init__(self):
            self.calls = []

        async def geoadd(self, *args):
            self.calls.append(("geoadd", args))

        async def hset(self, *args, **kwargs):
            self.calls.append(("hset", args, kwargs))

        async def publish(self, channel, payload):
            self.calls.append(("publish", channel, payload))

    redis = RecordingRedis()
    service = module.DispatchService()
    service.redis = redis

    ts = datetime(2026, 1, 2, 3, 4, 5)
    await service.update_location(
        DriverLocationUpdate(
            driver_id="driver-1",
            lat=-17.83,
            lng=31.05,
            status="ONLINE",
            battery=80,
            timestamp=ts,
        )
    )

    # geoadd -> hset -> publish, in that order.
    assert [call[0] for call in redis.calls] == ["geoadd", "hset", "publish"]

    # geoadd receives [longitude, latitude, member].
    assert redis.calls[0][1] == ("driver_locations", [31.05, -17.83, "driver-1"])

    hset_args, hset_kwargs = redis.calls[1][1], redis.calls[1][2]
    assert hset_args == ("driver:driver-1",)
    assert hset_kwargs["mapping"] == {
        "status": "ONLINE",
        "battery": "80",
        "last_seen": str(ts.timestamp()),
    }

    channel, payload = redis.calls[2][1], redis.calls[2][2]
    assert channel == "driver_loc_driver-1"
    assert json.loads(payload) == {"lat": -17.83, "lng": 31.05, "ts": str(ts)}
