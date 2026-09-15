"""Authorization on the realtime and driver-facing surfaces.

The recurring bug class here is a client-supplied `driver_id` being trusted.
Every test below proves the identity comes from the JWT and a mismatching claim
is refused — on the driver WebSocket, on location reporting, on sync, and on
order state changes.
"""

import json
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import BackgroundTasks, HTTPException
from starlette.websockets import WebSocketDisconnect, WebSocketState

from app.auth.service import AuthService
from app.order.state_machine import OrderConflict, OrderState


class FakeWebSocket:
    def __init__(self, token=None, header=None, messages=None):
        self.query_params = {"token": token} if token else {}
        self.headers = {"authorization": header} if header else {}
        self.messages = list(messages or [])
        self.client_state = WebSocketState.CONNECTED
        self.sent = []
        self.accepted = False
        self.closed_code = None

    async def accept(self):
        self.accepted = True

    async def close(self, code):
        self.closed_code = code
        self.client_state = WebSocketState.DISCONNECTED

    async def send_text(self, text):
        self.sent.append(text)

    async def receive_text(self):
        if not self.messages:
            self.client_state = WebSocketState.DISCONNECTED
            raise WebSocketDisconnect()
        value = self.messages.pop(0)
        if isinstance(value, BaseException):
            self.client_state = WebSocketState.DISCONNECTED
            raise value
        return value


class PubSub:
    def __init__(self):
        self.subscribed = []

    async def subscribe(self, channel):
        self.subscribed.append(channel)

    async def unsubscribe(self, channel):
        pass

    async def get_message(self, **_kwargs):
        return None


class FakeRedis:
    def __init__(self):
        self._pubsub = PubSub()

    def pubsub(self):
        return self._pubsub

    async def getdel(self, _key):
        return None

    async def close(self):
        pass


def active_driver(monkeypatch, module, is_active=True):
    monkeypatch.setattr(
        module.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="driver-a", is_active=is_active)),
    )


# ── Driver WebSocket impersonation ──────────────────────────────────


@pytest.mark.asyncio
async def test_driver_websocket_rejects_impersonation(monkeypatch):
    """A token for one driver must not open another driver's channel.

    This is the hole the endpoint used to have: `driver_id` came straight from
    the URL, so anyone with any valid token could subscribe to another driver's
    offers and act as them.
    """
    import app.dispatch.ws_router as module

    active_driver(monkeypatch, module)
    redis = FakeRedis()
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)

    attacker_token = AuthService.create_access_token({"sub": "attacker"})
    socket = FakeWebSocket(token=attacker_token)

    await module.driver_ws(socket, "victim-driver")

    assert socket.closed_code == 1008
    assert socket.accepted is False, "the socket must never be accepted"
    assert redis._pubsub.subscribed == [], "no subscription to the victim's channel"


@pytest.mark.asyncio
async def test_driver_websocket_rejects_a_missing_or_forged_token(monkeypatch):
    import app.dispatch.ws_router as module

    active_driver(monkeypatch, module)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: FakeRedis())

    for socket in (
        FakeWebSocket(),
        FakeWebSocket(token="not-a-jwt"),
        FakeWebSocket(header="Bearer not-a-jwt"),
        FakeWebSocket(header="Basic hunter2"),
    ):
        await module.driver_ws(socket, "driver-a")
        assert socket.closed_code == 1008
        assert socket.accepted is False


@pytest.mark.asyncio
async def test_driver_websocket_rejects_a_deactivated_account(monkeypatch):
    import app.dispatch.ws_router as module

    active_driver(monkeypatch, module, is_active=False)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: FakeRedis())

    socket = FakeWebSocket(token=AuthService.create_access_token({"sub": "driver-a"}))
    await module.driver_ws(socket, "driver-a")

    assert socket.closed_code == 1008


@pytest.mark.asyncio
async def test_driver_websocket_accepts_the_driver_named_by_the_token(monkeypatch):
    import app.dispatch.ws_router as module

    active_driver(monkeypatch, module)
    redis = FakeRedis()
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)

    socket = FakeWebSocket(token=AuthService.create_access_token({"sub": "driver-a"}))
    await module.driver_ws(socket, "driver-a")

    assert socket.accepted is True
    assert socket.closed_code is None
    assert redis._pubsub.subscribed == ["driver_driver-a"]


@pytest.mark.asyncio
async def test_websocket_delivery_action_only_moves_your_own_order(monkeypatch):
    """A driver must not be able to walk another driver's order to DELIVERED."""
    import app.dispatch.ws_router as module
    import app.order.service as order_service

    active_driver(monkeypatch, module)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: FakeRedis())

    transition = AsyncMock(side_effect=OrderConflict("This order is not assigned to you"))
    monkeypatch.setattr(order_service.OrderService, "transition_state", transition)

    socket = FakeWebSocket(
        token=AuthService.create_access_token({"sub": "driver-a"}),
        messages=[
            json.dumps(
                {
                    "type": "delivery_action",
                    "order_id": "someone-elses-order",
                    "state": "DELIVERED",
                }
            )
        ],
    )
    await module.driver_ws(socket, "driver-a")

    # The ownership guard is passed down to the service, not assumed.
    assert transition.await_args.kwargs["require_driver_id"] == "driver-a"
    errors = [json.loads(m) for m in socket.sent if json.loads(m).get("type") == "error"]
    assert errors and errors[0]["code"] == "delivery_action_rejected"


@pytest.mark.asyncio
async def test_websocket_tells_a_driver_when_an_offer_was_already_taken(monkeypatch):
    import app.dispatch.ws_router as module

    active_driver(monkeypatch, module)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: FakeRedis())
    monkeypatch.setattr(
        module.dispatch_service,
        "accept_offer",
        AsyncMock(side_effect=OrderConflict("This order has already been taken")),
    )

    socket = FakeWebSocket(
        token=AuthService.create_access_token({"sub": "driver-a"}),
        messages=[json.dumps({"type": "accept_offer", "order_id": "order-1"})],
    )
    await module.driver_ws(socket, "driver-a")

    errors = [json.loads(m) for m in socket.sent if json.loads(m).get("type") == "error"]
    assert errors and errors[0]["code"] == "offer_unavailable"
    assert errors[0]["order_id"] == "order-1"


# ── Location reporting ──────────────────────────────────────────────


@pytest.mark.asyncio
async def test_location_updates_cannot_be_filed_for_another_driver(monkeypatch):
    import app.dispatch.router as module
    from app.dispatch.schemas import DriverLocationUpdate

    limiter = SimpleNamespace(check_location_update=AsyncMock(return_value=(True, None)))
    monkeypatch.setattr(module, "RateLimiter", lambda _: limiter)
    caller = SimpleNamespace(id="driver-a")

    with pytest.raises(HTTPException) as exc:
        await module.update_location(
            DriverLocationUpdate(driver_id="driver-b", lat=-17.8, lng=31.0),
            BackgroundTasks(),
            caller,
            object(),
        )
    assert exc.value.status_code == 403

    # The driver's own update is accepted and attributed to the token subject.
    tasks = BackgroundTasks()
    update = DriverLocationUpdate(driver_id="driver-a", lat=-17.8, lng=31.0)
    assert await module.update_location(update, tasks, caller, object()) == {
        "status": "received"
    }
    assert update.driver_id == "driver-a"
    assert len(tasks.tasks) == 1


# ── Sync ────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_sync_refuses_to_pull_another_drivers_state(monkeypatch):
    import app.sync.router as module
    from app.sync.schemas import SyncRequest

    pull = AsyncMock(return_value=b"packed")
    monkeypatch.setattr(module.SyncService, "get_deltas", pull)

    with pytest.raises(HTTPException) as exc:
        await module.pull_changes(
            SyncRequest(driver_id="driver-b", last_version=0),
            SimpleNamespace(id="driver-a"),
        )
    assert exc.value.status_code == 403
    pull.assert_not_awaited()

    response = await module.pull_changes(
        SyncRequest(driver_id="driver-a", last_version=0),
        SimpleNamespace(id="driver-a"),
    )
    assert response.media_type == "application/x-msgpack"
    pull.assert_awaited_once_with("driver-a", 0)


@pytest.mark.asyncio
async def test_sync_only_returns_offers_made_to_this_driver(monkeypatch):
    """A driver's sync must not leak every open order on the platform."""
    import app.sync.service as module
    from app.location.models import Location

    filters = []

    class Query:
        def __init__(self, values):
            self.values = values

        def limit(self, *_args):
            return self

        async def to_list(self):
            return self.values

    assigned = SimpleNamespace(
        id="order-1",
        state=OrderState.PICKED_UP,
        total_amount=20,
        pickup_location=Location.from_lat_lng(-17.8, 31.0),
        dropoff_location=Location.from_lat_lng(-17.9, 31.1),
        items=[{"name": "Burger", "quantity": 2, "price": 5}],
    )
    offered = SimpleNamespace(
        id="order-2",
        state=OrderState.OFFERED,
        total_amount=10,
        pickup_location=None,
        dropoff_location=None,
        items=[],
    )

    results = [Query([assigned]), Query([offered])]

    def find(criteria):
        filters.append(criteria)
        return results.pop(0)

    monkeypatch.setattr(module.Order, "find", find)

    class Redis:
        async def set(self, *_a):
            return True

        async def close(self):
            return True

    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: Redis())

    packed = await module.SyncService.get_deltas("driver-a", 0)

    import msgpack

    decoded = msgpack.unpackb(packed)
    assert [o["id"] for o in decoded["data"]["orders"]] == ["order-1", "order-2"]
    # Items survive whether they are models or raw Mongo dicts.
    assert decoded["data"]["orders"][0]["items"][0]["name"] == "Burger"
    assert decoded["data"]["orders"][0]["pickup"] == {"lat": -17.8, "lng": 31.0}

    assigned_filter, offer_filter = filters
    assert assigned_filter["driver_id"] == "driver-a"
    # The crucial one: offers are scoped to this driver, not "state == OFFERED".
    assert offer_filter["offered_to"] == "driver-a"
    assert offer_filter["state"] == OrderState.OFFERED.value


@pytest.mark.asyncio
async def test_sync_caps_how_much_one_pull_can_return(monkeypatch):
    import app.sync.service as module

    limits = []

    class Query:
        def limit(self, value):
            limits.append(value)
            return self

        async def to_list(self):
            return []

    monkeypatch.setattr(module.Order, "find", lambda *_a, **_k: Query())

    class Redis:
        async def set(self, *_a):
            return True

        async def close(self):
            return True

    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: Redis())

    await module.SyncService.get_deltas("driver-a", 0, limit=10_000)

    assert limits == [module.MAX_SYNC_ORDERS, module.MAX_SYNC_ORDERS]


# ── Order state role guards ─────────────────────────────────────────


def order_double(**overrides):
    values = {
        "id": "order-1",
        "state": OrderState.OFFERED,
        "consumer_id": "consumer-1",
        "merchant_id": "restaurant-1",
        "driver_id": None,
        "total_amount": 10.0,
        "created_at": datetime(2026, 1, 1),
        "items": [],
        "pickup_location": None,
        "dropoff_location": None,
        "delivery_instructions": None,
        "group_id": None,
        "events": [],
    }
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
async def test_a_consumer_cannot_claim_their_own_order_was_picked_up(monkeypatch):
    import app.order.router as module

    order = order_double()
    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order)))
    monkeypatch.setattr(module, "owning_merchant_id", AsyncMock(return_value="merchant-9"))
    transition = AsyncMock(return_value=order)
    monkeypatch.setattr(module.OrderService, "transition_state", transition)

    from app.order.schemas import OrderUpdateState

    for forbidden in (OrderState.PICKED_UP, OrderState.ARRIVED_AT_CUSTOMER, OrderState.ACCEPTED):
        with pytest.raises(HTTPException) as exc:
            await module.update_order_state(
                "order-1", OrderUpdateState(state=forbidden), SimpleNamespace(id="consumer-1")
            )
        assert exc.value.status_code == 403
    transition.assert_not_awaited()


@pytest.mark.asyncio
async def test_a_merchant_cannot_mark_an_order_delivered(monkeypatch):
    import app.order.router as module
    from app.order.schemas import OrderUpdateState

    order = order_double()
    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order)))
    monkeypatch.setattr(module, "require_order_participant", AsyncMock(return_value=order))
    monkeypatch.setattr(module, "owning_merchant_id", AsyncMock(return_value="merchant-1"))
    transition = AsyncMock(return_value=order)
    monkeypatch.setattr(module.OrderService, "transition_state", transition)

    with pytest.raises(HTTPException) as exc:
        await module.update_order_state(
            "order-1",
            OrderUpdateState(state=OrderState.DELIVERED),
            SimpleNamespace(id="merchant-1"),
        )
    assert exc.value.status_code == 403

    # Marking it ready for pickup is squarely the merchant's job.
    await module.update_order_state(
        "order-1",
        OrderUpdateState(state=OrderState.READY_FOR_PICKUP),
        SimpleNamespace(id="merchant-1"),
    )
    assert transition.await_args.kwargs["require_driver_id"] is None


@pytest.mark.asyncio
async def test_the_assigned_driver_is_pinned_on_their_own_transitions(monkeypatch):
    import app.order.router as module
    from app.order.schemas import OrderUpdateState

    order = order_double(state=OrderState.ACCEPTED, driver_id="driver-a")
    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order)))
    monkeypatch.setattr(module, "require_order_participant", AsyncMock(return_value=order))
    transition = AsyncMock(return_value=order)
    monkeypatch.setattr(module.OrderService, "transition_state", transition)

    await module.update_order_state(
        "order-1",
        OrderUpdateState(state=OrderState.PICKED_UP),
        SimpleNamespace(id="driver-a"),
    )

    assert transition.await_args.kwargs["require_driver_id"] == "driver-a"


@pytest.mark.asyncio
async def test_a_lost_race_is_reported_as_a_conflict_not_a_success(monkeypatch):
    import app.order.router as module
    from app.order.schemas import OrderUpdateState

    order = order_double(state=OrderState.OFFERED)
    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order)))
    monkeypatch.setattr(module, "require_order_participant", AsyncMock(return_value=order))
    monkeypatch.setattr(module, "owning_merchant_id", AsyncMock(return_value="merchant-9"))
    monkeypatch.setattr(
        module.OrderService,
        "transition_state",
        AsyncMock(side_effect=OrderConflict("already taken")),
    )

    with pytest.raises(HTTPException) as exc:
        await module.update_order_state(
            "order-1",
            OrderUpdateState(state=OrderState.CANCELLED),
            SimpleNamespace(id="consumer-1"),
        )
    assert exc.value.status_code == 409

    with pytest.raises(HTTPException) as exc:
        await module.cancel_order("order-1", SimpleNamespace(id="consumer-1"))
    assert exc.value.status_code == 409


@pytest.mark.asyncio
async def test_a_picked_up_order_cannot_be_self_cancelled(monkeypatch):
    import app.order.router as module

    order = order_double(state=OrderState.PICKED_UP, driver_id="driver-a")
    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order)))
    transition = AsyncMock()
    monkeypatch.setattr(module.OrderService, "transition_state", transition)

    with pytest.raises(HTTPException) as exc:
        await module.cancel_order("order-1", SimpleNamespace(id="consumer-1"))
    assert exc.value.status_code == 400
    assert "picked up" in exc.value.detail
    transition.assert_not_awaited()


# ── Audit trail ─────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_the_audit_trail_is_readable_by_the_parties_to_the_order(monkeypatch):
    import app.order.router as module

    order = order_double(
        events=[
            {"state": "CREATED", "timestamp": None, "actor_id": "consumer-1", "reason": "order_created"},
            SimpleNamespace(
                state=OrderState.ACCEPTED,
                timestamp=None,
                actor_id="driver-a",
                reason="driver_accepted",
            ),
        ]
    )
    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order)))
    monkeypatch.setattr(module, "require_order_participant", AsyncMock(return_value=order))

    events = await module.get_order_events("order-1", SimpleNamespace(id="consumer-1"))

    assert [e.state for e in events] == ["CREATED", "ACCEPTED"]
    assert [e.reason for e in events] == ["order_created", "driver_accepted"]
    assert [e.actor_id for e in events] == ["consumer-1", "driver-a"]

    monkeypatch.setattr(
        module,
        "require_order_participant",
        AsyncMock(side_effect=HTTPException(status_code=403, detail="nope")),
    )
    with pytest.raises(HTTPException) as exc:
        await module.get_order_events("order-1", SimpleNamespace(id="stranger"))
    assert exc.value.status_code == 403


# ── Consumer order tracking ─────────────────────────────────────────


@pytest.mark.asyncio
async def test_tracking_websocket_rejects_a_non_participant(monkeypatch):
    """The live tracking socket leaks driver position — it must be gated."""
    import app.tracking.ws_router as module

    order = SimpleNamespace(
        id="order-1", consumer_id="consumer-1", driver_id="driver-a",
        merchant_id="restaurant-1", state=OrderState.PICKED_UP, group_id=None,
    )
    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order))
    monkeypatch.setattr(
        module.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="stranger", is_active=True)),
    )
    monkeypatch.setattr(module, "can_access_order", AsyncMock(return_value=False))
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: FakeRedis())

    socket = FakeWebSocket(token=AuthService.create_access_token({"sub": "stranger"}))
    await module.track_order(socket, "order-1")

    assert socket.closed_code == 1008
    assert socket.accepted is False

    # No token at all is refused before any database work happens.
    anonymous = FakeWebSocket()
    await module.track_order(anonymous, "order-1")
    assert anonymous.closed_code == 1008


@pytest.mark.asyncio
async def test_tracking_websocket_closes_cleanly_on_an_unreadable_order_id(monkeypatch):
    import app.tracking.ws_router as module

    monkeypatch.setattr(
        module.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="consumer-1", is_active=True)),
    )
    monkeypatch.setattr(
        module.Order, "get", AsyncMock(side_effect=ValueError("not an ObjectId"))
    )

    socket = FakeWebSocket(token=AuthService.create_access_token({"sub": "consumer-1"}))
    await module.track_order(socket, "../../etc/passwd")

    assert socket.closed_code == 1008
