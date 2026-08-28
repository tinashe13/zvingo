"""Tests for the consolidated consumer order-tracking WebSocket."""

import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from starlette.websockets import WebSocketDisconnect, WebSocketState

from app.auth.service import AuthService
from app.order.state_machine import OrderState
from app.tracking.ws_router import channel_kind, tag_message


class PubSub:
    def __init__(self, get_messages=None):
        self.get_messages = list(get_messages or [])
        self.subscribed = []
        self.unsubscribed = []
        self.unsubscribe_error = None

    async def subscribe(self, channel):
        self.subscribed.append(channel)

    async def unsubscribe(self, channel):
        if self.unsubscribe_error:
            raise self.unsubscribe_error
        self.unsubscribed.append(channel)

    async def get_message(self, **_kwargs):
        if self.get_messages:
            value = self.get_messages.pop(0)
            if isinstance(value, BaseException):
                raise value
            return value
        return None


class Redis:
    def __init__(self, pubsub=None, positions=None):
        self._pubsub = pubsub or PubSub()
        self.positions = positions
        self.closed = False
        self.close_error = None
        self.geopos_error = None

    def pubsub(self):
        return self._pubsub

    async def geopos(self, _key, _member):
        if self.geopos_error:
            raise self.geopos_error
        return self.positions

    async def close(self):
        if self.close_error:
            raise self.close_error
        self.closed = True


class WebSocket:
    def __init__(self, token=None, messages=None):
        self.query_params = {"token": token} if token else {}
        self.headers = {}
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
        # A real receive suspends, which is what lets the forwarding and ping
        # tasks make progress; yield so the fake behaves the same way.
        await asyncio.sleep(0)
        if not self.messages:
            self.client_state = WebSocketState.DISCONNECTED
            raise WebSocketDisconnect()
        value = self.messages.pop(0)
        if isinstance(value, BaseException):
            self.client_state = WebSocketState.DISCONNECTED
            raise value
        return value


def order(**overrides):
    values = {
        "id": "order-1",
        "state": OrderState.ACCEPTED,
        "consumer_id": "consumer-1",
        "driver_id": "driver-1",
        "merchant_id": "restaurant-1",
        "group_id": None,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def token(sub="consumer-1"):
    return AuthService.create_access_token({"sub": sub})


# ── pure helpers ────────────────────────────────────────────────────


def test_channel_kind_maps_prefixes():
    assert channel_kind("driver_loc_d1") == "location"
    assert channel_kind("consumer_c1") == "order"
    assert channel_kind("chat_o1") == "chat"
    assert channel_kind("something_else") == "event"


def test_tag_message_wraps_every_payload_shape():
    assert json.loads(tag_message("chat_o1", '{"text":"hi"}')) == {
        "text": "hi",
        "type": "chat",
    }
    # A non-object JSON payload and non-JSON text both get wrapped.
    assert json.loads(tag_message("consumer_c1", "[1,2]")) == {
        "data": [1, 2],
        "type": "order",
    }
    assert json.loads(tag_message("consumer_c1", "ping")) == {
        "data": "ping",
        "type": "order",
    }


def test_driver_id_extraction():
    from app.tracking.ws_router import _driver_id_from

    assert _driver_id_from('{"driver_id":"d1"}') == "d1"
    assert _driver_id_from('{"driver_id":null}') is None
    assert _driver_id_from('{"driver_id":7}') is None
    assert _driver_id_from("[1,2]") is None
    assert _driver_id_from("not json") is None


@pytest.mark.asyncio
async def test_driver_position_reads_and_tolerates_failure(monkeypatch):
    import app.tracking.ws_router as module

    monkeypatch.setattr(
        module.aioredis, "from_url", lambda *a, **k: Redis(positions=[(31.0, -17.8)])
    )
    assert await module.driver_position("driver-1") == (-17.8, 31.0)

    monkeypatch.setattr(
        module.aioredis, "from_url", lambda *a, **k: Redis(positions=[None])
    )
    assert await module.driver_position("driver-1") == (None, None)

    failing = Redis()
    failing.geopos_error = RuntimeError("redis down")
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: failing)
    assert await module.driver_position("driver-1") == (None, None)


# ── connection guards ───────────────────────────────────────────────


@pytest.mark.asyncio
async def test_tracking_ws_rejects_bad_credentials(monkeypatch):
    import app.tracking.ws_router as module

    anonymous = WebSocket()
    await module.track_order(anonymous, "order-1")
    assert anonymous.closed_code == 1008

    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=None))
    unknown = WebSocket(token=token())
    await module.track_order(unknown, "order-1")
    assert unknown.closed_code == 1008

    monkeypatch.setattr(
        module.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="consumer-1", is_active=False)),
    )
    inactive = WebSocket(token=token())
    await module.track_order(inactive, "order-1")
    assert inactive.closed_code == 1008


@pytest.mark.asyncio
async def test_tracking_ws_rejects_missing_orders_and_outsiders(monkeypatch):
    import app.tracking.ws_router as module

    consumer = SimpleNamespace(id="consumer-1", is_active=True)
    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=consumer))

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=None))
    missing = WebSocket(token=token())
    await module.track_order(missing, "order-1")
    assert missing.closed_code == 1008

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "can_access_order", AsyncMock(return_value=False))
    outsider = WebSocket(token=token("stranger"))
    await module.track_order(outsider, "order-1")
    assert outsider.closed_code == 1008


# ── streaming ───────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_tracking_ws_streams_snapshot_and_tagged_events(monkeypatch):
    import app.tracking.ws_router as module

    monkeypatch.setattr(
        module.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="consumer-1", is_active=True)),
    )
    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "can_access_order", AsyncMock(return_value=True))
    monkeypatch.setattr(
        module, "driver_position", AsyncMock(return_value=(-17.8, 31.0))
    )

    pubsub = PubSub(
        get_messages=[
            {"type": "message", "channel": "driver_loc_driver-1", "data": '{"lat":1}'},
            {"type": "subscribe", "channel": "chat_order-1", "data": 1},
        ]
    )
    redis = Redis(pubsub)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: redis)

    websocket = WebSocket(token=token(), messages=[json.dumps({"type": "pong"})])
    await module.track_order(websocket, "order-1")

    assert websocket.accepted
    snapshot = json.loads(websocket.sent[0])
    assert snapshot["type"] == "snapshot"
    assert snapshot["state"] == "ACCEPTED"
    assert snapshot["driver_lat"] == -17.8

    assert set(pubsub.subscribed) == {
        "chat_order-1",
        "consumer_consumer-1",
        "driver_loc_driver-1",
    }
    assert redis.closed


@pytest.mark.asyncio
async def test_tracking_ws_follows_a_driver_assigned_mid_stream(monkeypatch):
    import app.tracking.ws_router as module

    monkeypatch.setattr(
        module.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="consumer-1", is_active=True)),
    )
    # No driver yet — the snapshot has no position to report.
    monkeypatch.setattr(
        module.Order,
        "get",
        AsyncMock(return_value=order(driver_id=None, state="CREATED")),
    )
    monkeypatch.setattr(module, "can_access_order", AsyncMock(return_value=True))

    assigned = json.dumps({"event": "order_accepted", "driver_id": "driver-9"})
    pubsub = PubSub(
        get_messages=[
            {"type": "message", "channel": "consumer_consumer-1", "data": assigned},
            # A repeat must not re-subscribe.
            {"type": "message", "channel": "consumer_consumer-1", "data": assigned},
        ]
    )
    redis = Redis(pubsub)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: redis)

    websocket = WebSocket(token=token(), messages=["{}", "{}"])
    await module.track_order(websocket, "order-1")

    assert pubsub.subscribed.count("driver_loc_driver-9") == 1
    assert "driver_loc_driver-9" in pubsub.unsubscribed


@pytest.mark.asyncio
async def test_tracking_ws_survives_forwarding_and_cleanup_errors(monkeypatch):
    import app.tracking.ws_router as module

    monkeypatch.setattr(
        module.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="consumer-1", is_active=True)),
    )
    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "can_access_order", AsyncMock(return_value=True))
    monkeypatch.setattr(module, "driver_position", AsyncMock(return_value=(None, None)))

    pubsub = PubSub(get_messages=[RuntimeError("pubsub blew up")])
    pubsub.unsubscribe_error = RuntimeError("unsubscribe")
    redis = Redis(pubsub)
    redis.close_error = RuntimeError("close")
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: redis)

    websocket = WebSocket(token=token(), messages=[RuntimeError("socket failure")])
    await module.track_order(websocket, "order-1")
    assert websocket.accepted


@pytest.mark.asyncio
async def test_forward_loop_stops_once_the_socket_closes(monkeypatch):
    import app.tracking.ws_router as module

    websocket = WebSocket()
    websocket.client_state = WebSocketState.DISCONNECTED
    pubsub = PubSub(get_messages=[{"type": "message", "channel": "chat_o1", "data": "{}"}])

    await module.forward_messages(websocket, pubsub, set(), "order-1")
    assert websocket.sent == []


@pytest.mark.asyncio
async def test_ping_loop_stops_and_swallows_send_failures(monkeypatch):
    import app.tracking.ws_router as module

    monkeypatch.setattr(module, "PING_INTERVAL", 0)

    disconnected = WebSocket()
    disconnected.client_state = WebSocketState.DISCONNECTED
    await module.ping_loop(disconnected)
    assert disconnected.sent == []

    class Broken(WebSocket):
        async def send_text(self, text):
            raise RuntimeError("socket gone")

    await module.ping_loop(Broken())


@pytest.mark.asyncio
async def test_tracking_ws_ping_loop_stops_when_disconnected(monkeypatch):
    import app.tracking.ws_router as module

    monkeypatch.setattr(
        module.User,
        "get",
        AsyncMock(return_value=SimpleNamespace(id="consumer-1", is_active=True)),
    )
    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "can_access_order", AsyncMock(return_value=True))
    monkeypatch.setattr(module, "driver_position", AsyncMock(return_value=(None, None)))
    monkeypatch.setattr(module, "PING_INTERVAL", 0)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: Redis())

    websocket = WebSocket(token=token(), messages=["{}", "{}", "{}"])
    await module.track_order(websocket, "order-1")
    assert any(
        json.loads(sent).get("type") == "ping"
        for sent in websocket.sent
        if sent.startswith("{")
    )
