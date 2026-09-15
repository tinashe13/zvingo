import asyncio
import json
import struct
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import FastAPI
from starlette.websockets import WebSocketDisconnect, WebSocketState

from app.auth.service import AuthService
from app.binproto.codec import BinProtoCodec, PTYPE_LOCATION


class PubSub:
    def __init__(self, messages=None, get_messages=None):
        self.messages = messages or []
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

    async def listen(self):
        for message in self.messages:
            if isinstance(message, BaseException):
                raise message
            yield message

    async def get_message(self, **_kwargs):
        if self.get_messages:
            value = self.get_messages.pop(0)
            if isinstance(value, BaseException):
                raise value
            return value
        return None


class Redis:
    def __init__(self, pubsub, pending=None):
        self._pubsub = pubsub
        self.pending = pending
        self.closed = False
        self.close_error = None

    def pubsub(self):
        return self._pubsub

    async def getdel(self, _key):
        value, self.pending = self.pending, None
        return value

    async def close(self):
        if self.close_error:
            raise self.close_error
        self.closed = True


class Request:
    def __init__(self, disconnected=None):
        self.disconnected = list(disconnected or [False])

    async def is_disconnected(self):
        if self.disconnected:
            return self.disconnected.pop(0)
        return True


class WebSocket:
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


async def collect(response, limit=10):
    values = []
    async for item in response.body_iterator:
        values.append(item)
        if len(values) >= limit:
            break
    return values


@pytest.mark.asyncio
async def test_location_tracking_sse_message_disconnect_and_cancel(monkeypatch):
    import app.location.router as module

    pubsub = PubSub(
        messages=[
            {"type": "subscribe", "data": "ignored"},
            {"type": "message", "data": '{"lat":1}'},
        ]
    )
    redis = Redis(pubsub)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    # These tests cover stream mechanics (disconnect, cancel, cleanup), not
    # authorization. Both stream endpoints now require a single-use ticket;
    # ticket authorization has its own tests in test_lead_stream_auth.py.
    monkeypatch.setattr(module, "redeem_ticket", AsyncMock(return_value="user-1"))
    response = await module.track_driver(Request([False, False]), "driver")
    events = await collect(response)
    assert events == [{"event": "location", "data": '{"lat":1}'}]
    assert redis.closed and pubsub.unsubscribed == ["driver_loc_driver"]

    pubsub = PubSub(messages=[asyncio.CancelledError()])
    redis = Redis(pubsub)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    assert await collect(await module.track_driver(Request(), "driver")) == []


@pytest.mark.asyncio
async def test_notification_sse_messages_ping_error_and_cleanup(monkeypatch):
    import app.notification.router as module

    pubsub = PubSub(
        get_messages=[
            {"type": "message", "data": "payload"},
            None,
        ]
    )
    redis = Redis(pubsub)
    monkeypatch.setattr(module.redis, "from_url", lambda *_a, **_k: redis)
    # These tests cover stream mechanics (disconnect, cancel, cleanup), not
    # authorization. Both stream endpoints now require a single-use ticket;
    # ticket authorization has its own tests in test_lead_stream_auth.py.
    monkeypatch.setattr(module, "redeem_ticket", AsyncMock(return_value="user-1"))
    response = await module.message_stream(Request([False, False, True]), "channel")
    events = await collect(response)
    assert [event["event"] for event in events] == ["connected", "message", "ping"]
    assert redis.closed

    pubsub = PubSub(get_messages=[RuntimeError("redis")])
    pubsub.unsubscribe_error = RuntimeError("unsubscribe")
    redis = Redis(pubsub)
    redis.close_error = RuntimeError("close")
    monkeypatch.setattr(module.redis, "from_url", lambda *_a, **_k: redis)
    events = await collect(await module.message_stream(Request([False]), "channel"))
    assert events[-1]["event"] == "error"

    pubsub = PubSub(get_messages=[asyncio.CancelledError()])
    redis = Redis(pubsub)
    monkeypatch.setattr(module.redis, "from_url", lambda *_a, **_k: redis)
    events = await collect(await module.message_stream(Request([False]), "channel"))
    assert events[0]["event"] == "connected"


def test_websocket_authentication():
    import app.dispatch.ws_router as module

    token = AuthService.create_access_token({"sub": "driver"})
    assert module._authenticate_ws(WebSocket(token=token)) == "driver"
    assert module._authenticate_ws(WebSocket(header=f"Bearer {token}")) == "driver"
    assert module._authenticate_ws(WebSocket()) is None
    assert module._authenticate_ws(WebSocket(token="bad")) is None
    assert module._authenticate_ws(WebSocket(header="Basic bad")) is None


@pytest.mark.asyncio
async def test_websocket_rejection_and_full_message_flow(monkeypatch):
    import app.dispatch.ws_router as module
    import app.order.service as order_service

    unauthorized = WebSocket()
    await module.driver_ws(unauthorized, "driver")
    assert unauthorized.closed_code == 1008

    wrong = WebSocket(token=AuthService.create_access_token({"sub": "other"}))
    await module.driver_ws(wrong, "driver")
    assert wrong.closed_code == 1008

    # A valid token for an account that no longer exists is refused too.
    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=None))
    deactivated = WebSocket(token=AuthService.create_access_token({"sub": "driver"}))
    await module.driver_ws(deactivated, "driver")
    assert deactivated.closed_code == 1008
    monkeypatch.setattr(
        module.User, "get", AsyncMock(return_value=SimpleNamespace(is_active=True))
    )

    token = AuthService.create_access_token({"sub": "driver"})
    messages = [
        "not-json",
        json.dumps({"type": "location_update", "lat": 1, "lng": 2}),
        json.dumps({"type": "accept_offer"}),
        json.dumps({"type": "accept_offer", "order_id": "o1"}),
        json.dumps({"type": "decline_offer"}),
        json.dumps({"type": "decline_offer", "order_id": "o1"}),
        json.dumps({"type": "status_change", "status": "BUSY"}),
        json.dumps({"type": "delivery_action"}),
        json.dumps(
            {"type": "delivery_action", "order_id": "o1", "state": "PICKED_UP"}
        ),
        json.dumps({"type": "pong"}),
        json.dumps({"type": "unknown"}),
    ]
    websocket = WebSocket(token=token, messages=messages)
    pubsub = PubSub(get_messages=[{"type": "message", "data": "redis-message"}])
    redis = Redis(pubsub, pending="pending-offer")
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    monkeypatch.setattr(module, "_handle_location_update", AsyncMock())
    monkeypatch.setattr(module.dispatch_service, "accept_offer", AsyncMock())
    monkeypatch.setattr(module.dispatch_service, "decline_offer", AsyncMock())
    monkeypatch.setattr(module.dispatch_service.redis, "hset", AsyncMock())
    monkeypatch.setattr(order_service.OrderService, "transition_state", AsyncMock())
    await module.driver_ws(websocket, "driver")
    assert websocket.accepted
    assert "pending-offer" in websocket.sent
    module._handle_location_update.assert_awaited_once()
    module.dispatch_service.accept_offer.assert_awaited_once_with("driver", "o1")
    module.dispatch_service.decline_offer.assert_awaited_once_with("driver", "o1")
    order_service.OrderService.transition_state.assert_awaited_once()
    assert redis.closed

    order_service.OrderService.transition_state.side_effect = RuntimeError("transition")
    websocket = WebSocket(
        token=token,
        messages=[
            json.dumps(
                {"type": "delivery_action", "order_id": "o1", "state": "DELIVERED"}
            ),
            RuntimeError("socket"),
        ],
    )
    redis = Redis(PubSub())
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    await module.driver_ws(websocket, "driver")


@pytest.mark.asyncio
async def test_websocket_location_update_validation(monkeypatch):
    import app.dispatch.ws_router as module

    update = AsyncMock()
    monkeypatch.setattr(module.dispatch_service, "update_location", update)
    await module._handle_location_update(
        "driver", {"lat": "1.2", "lng": "2.3", "status": "ONLINE", "battery": "80"}
    )
    sent = update.await_args.args[0]
    assert sent.driver_id == "driver" and sent.battery == 80
    await module._handle_location_update("driver", {})
    await module._handle_location_update("driver", {"lat": "bad", "lng": 2})


@pytest.mark.asyncio
async def test_tcp_client_location_rate_limit_and_errors(monkeypatch):
    import app.binproto.tcp_server as module
    import app.dispatch.service as dispatch_module

    session = b"12345678"
    payload = BinProtoCodec.encode_location(-17.8, 31.0)
    header = BinProtoCodec.encode_header(PTYPE_LOCATION, session, 7, len(payload))

    class Reader:
        def __init__(self, chunks):
            self.chunks = list(chunks)

        async def readexactly(self, _size):
            if not self.chunks:
                raise asyncio.IncompleteReadError(b"", 1)
            value = self.chunks.pop(0)
            if isinstance(value, BaseException):
                raise value
            return value

    class Writer:
        def __init__(self):
            self.data = []
            self.closed = False

        def get_extra_info(self, _):
            return ("127.0.0.1", 1)

        def write(self, value):
            self.data.append(value)

        async def drain(self):
            pass

        def close(self):
            self.closed = True

        async def wait_closed(self):
            pass

    redis = SimpleNamespace(close=AsyncMock())
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    monkeypatch.setattr(module, "resolve_driver_id", AsyncMock(return_value="driver"))
    limiter = SimpleNamespace(check_location_update=AsyncMock(return_value=(True, None)))
    monkeypatch.setattr(module, "RateLimiter", lambda _: limiter)
    monkeypatch.setattr(dispatch_module.dispatch_service, "update_location", AsyncMock())
    writer = Writer()
    await module.handle_tcp_client(Reader([header, payload]), writer)
    assert writer.data == [BinProtoCodec.encode_ack(7)]
    dispatch_module.dispatch_service.update_location.assert_awaited_once()

    limiter.check_location_update.return_value = (False, "limited")
    await module.handle_tcp_client(Reader([header, payload]), Writer())
    module.resolve_driver_id.return_value = None
    await module.handle_tcp_client(Reader([header, payload]), Writer())

    empty_header = BinProtoCodec.encode_header(2, session, 8, 0)
    await module.handle_tcp_client(Reader([empty_header]), Writer())
    await module.handle_tcp_client(Reader([RuntimeError("read")]), Writer())


@pytest.mark.asyncio
async def test_udp_protocol_packets_and_background_handler(monkeypatch):
    import app.binproto.udp_server as module
    import app.dispatch.service as dispatch_module

    protocol = module.BinProtoUDPProtocol()
    transport = SimpleNamespace(sendto=MagicMock())
    protocol.connection_made(transport)
    payload = BinProtoCodec.encode_location(-17.8, 31.0)
    packet = BinProtoCodec.encode_header(PTYPE_LOCATION, b"12345678", 9, len(payload)) + payload

    created = []

    class Loop:
        def create_task(self, coro):
            task = asyncio.create_task(coro)
            created.append(task)
            return task

    monkeypatch.setattr(module.asyncio, "get_running_loop", lambda: Loop())
    monkeypatch.setattr(module, "resolve_driver_id", AsyncMock(return_value=None))
    protocol.datagram_received(packet, ("127.0.0.1", 1))
    await asyncio.gather(*created)
    assert transport.sendto.called

    redis = SimpleNamespace(close=AsyncMock())
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    limiter = SimpleNamespace(check_location_update=AsyncMock(return_value=(False, "limited")))
    monkeypatch.setattr(module, "RateLimiter", lambda _: limiter)
    module.resolve_driver_id.return_value = "driver"
    created.clear()
    protocol.datagram_received(packet, ("127.0.0.1", 1))
    await asyncio.gather(*created)

    limiter.check_location_update.return_value = (True, None)
    monkeypatch.setattr(dispatch_module.dispatch_service, "update_location", AsyncMock())
    created.clear()
    protocol.datagram_received(packet, ("127.0.0.1", 1))
    await asyncio.gather(*created)
    dispatch_module.dispatch_service.update_location.assert_awaited_once()
    protocol.datagram_received(b"bad", ("127.0.0.1", 1))


@pytest.mark.asyncio
async def test_main_health_and_lifespan(monkeypatch):
    import app.binproto.tcp_server as tcp
    import app.binproto.udp_server as udp
    import app.catalog.maintenance as maintenance
    import app.db.session as session
    import app.dispatch.retry_service as retry
    import app.main as module
    import app.notification.fcm as fcm

    assert await module.health_check() == {"status": "ok"}
    monkeypatch.setattr(session, "init_db", AsyncMock())
    monkeypatch.setattr(module, "init_db", session.init_db)
    monkeypatch.setattr(fcm, "init_firebase", MagicMock())
    transport = SimpleNamespace(close=MagicMock())
    monkeypatch.setattr(udp, "start_udp_server", AsyncMock(return_value=transport))
    tcp_started = asyncio.Event()

    async def tcp_server():
        tcp_started.set()
        await asyncio.Future()

    monkeypatch.setattr(tcp, "start_tcp_server", tcp_server)
    monkeypatch.setattr(retry.retry_service, "start", AsyncMock())
    monkeypatch.setattr(retry.retry_service, "stop", AsyncMock())
    monkeypatch.setattr(maintenance, "backfill_restaurant_locations", AsyncMock())
    async with module.lifespan(FastAPI()):
        await asyncio.wait_for(tcp_started.wait(), 1)
    transport.close.assert_called_once()
    retry.retry_service.start.assert_awaited_once()
    retry.retry_service.stop.assert_awaited_once()

    monkeypatch.setattr(udp, "start_udp_server", AsyncMock(return_value=None))
    async with module.lifespan(FastAPI()):
        await asyncio.wait_for(tcp_started.wait(), 1)
