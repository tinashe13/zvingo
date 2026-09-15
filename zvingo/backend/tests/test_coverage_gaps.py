import asyncio
import builtins
import importlib
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException
from starlette.websockets import WebSocketDisconnect, WebSocketState

from app.auth.service import AuthService
from app.location.models import Location


class Query:
    def __init__(self, values):
        self.values = values

    def sort(self, *_args):
        return self

    def skip(self, *_args):
        return self

    def limit(self, *_args):
        return self

    async def to_list(self):
        return self.values


@pytest.mark.asyncio
async def test_retry_order_resolution_and_dispatch_errors(monkeypatch):
    import app.dispatch.retry_service as module
    import app.catalog.models as catalog_models

    invalid_location = SimpleNamespace(
        id="bad-location", merchant_id="restaurant-1", retry_count=0,
        last_retry_at=None, pickup_location=Location.from_lat_lng(0, 0),
        save=AsyncMock(),
    )
    dispatch_failure = SimpleNamespace(
        id="dispatch-failure", merchant_id="restaurant-2", retry_count=0,
        last_retry_at=None, pickup_location=Location.from_lat_lng(-17, 31),
        save=AsyncMock(),
    )

    class FakeOrder:
        @classmethod
        def find(cls, *args):
            return Query([invalid_location, dispatch_failure])

    class FakeRestaurant:
        get = AsyncMock(side_effect=RuntimeError("catalog unavailable"))

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    monkeypatch.setattr(
        module.dispatch_service, "dispatch_order", AsyncMock(side_effect=RuntimeError("dispatch unavailable"))
    )
    await module.OrderRetryService._process_stuck_orders()
    module.dispatch_service.dispatch_order.assert_awaited_once_with("dispatch-failure", -17, 31)
    invalid_location.save.assert_not_awaited()
    dispatch_failure.save.assert_not_awaited()


@pytest.mark.asyncio
async def test_websocket_worker_loops_and_cleanup_errors(monkeypatch):
    import app.dispatch.ws_router as module

    class PubSub:
        def __init__(self, fail=False):
            self.responses = [
                {"type": "message", "data": "from-redis"},
            ]
            if fail:
                self.responses.append(RuntimeError("pubsub failed"))

        async def subscribe(self, channel):
            pass

        async def get_message(self, **kwargs):
            value = self.responses.pop(0) if self.responses else None
            if isinstance(value, Exception):
                raise value
            return value

        async def unsubscribe(self, channel):
            raise RuntimeError("unsubscribe failed")

    class Redis:
        def __init__(self, fail=False):
            self._pubsub = PubSub(fail)

        def pubsub(self):
            return self._pubsub

        async def getdel(self, key):
            return None

        async def close(self):
            raise RuntimeError("close failed")

    class SlowWebSocket:
        def __init__(self, token, ping_error=False):
            self.query_params = {"token": token}
            self.headers = {}
            self.client_state = WebSocketState.CONNECTED
            self.sent = []
            self.ping_error = ping_error

        async def accept(self):
            pass

        async def close(self, code):
            self.client_state = WebSocketState.DISCONNECTED

        async def send_text(self, text):
            if self.ping_error and text.startswith("{") and json.loads(text).get("type") == "ping":
                raise RuntimeError("ping failed")
            self.sent.append(text)

        async def receive_text(self):
            await asyncio.sleep(0.01)
            self.client_state = WebSocketState.DISCONNECTED
            await asyncio.sleep(0.01)
            raise WebSocketDisconnect()

    token = AuthService.create_access_token({"sub": "driver"})
    websocket = SlowWebSocket(token)
    # The handshake now also confirms the account exists and is still active.
    monkeypatch.setattr(
        module.User, "get", AsyncMock(return_value=SimpleNamespace(is_active=True))
    )
    monkeypatch.setattr(module.aioredis, "from_url", lambda *args, **kwargs: Redis())
    monkeypatch.setattr(module, "PING_INTERVAL", 0)
    await module.driver_ws(websocket, "driver")
    assert "from-redis" in websocket.sent
    assert any(json.loads(value).get("type") == "ping" for value in websocket.sent if value.startswith("{"))

    websocket = SlowWebSocket(token, ping_error=True)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *args, **kwargs: Redis(fail=True))
    await module.driver_ws(websocket, "driver")


@pytest.mark.asyncio
async def test_location_stream_stops_on_disconnect(monkeypatch):
    import app.location.router as module

    class PubSub:
        async def subscribe(self, channel):
            pass

        async def unsubscribe(self, channel):
            pass

        def listen(self):
            class Listener:
                def __init__(self):
                    self.done = False

                def __aiter__(self):
                    return self

                async def __anext__(self):
                    if self.done:
                        raise StopAsyncIteration
                    self.done = True
                    return {"type": "message", "data": "unused"}

            return Listener()

    class Redis:
        def pubsub(self):
            return PubSub()

        async def close(self):
            pass

    class Request:
        async def is_disconnected(self):
            return True

    monkeypatch.setattr(module.aioredis, "from_url", lambda *args, **kwargs: Redis())
    response = await module.track_driver(Request(), "driver")
    assert [item async for item in response.body_iterator] == []


@pytest.mark.asyncio
async def test_notification_lookup_failures_use_safe_defaults(monkeypatch):
    import app.notification.service as module
    import app.order.models as order_models
    import app.catalog.models as catalog_models
    import app.auth.models as auth_models

    current_order = SimpleNamespace(
        merchant_id="restaurant-1", consumer_id="consumer-1",
        pickup_location=Location.from_lat_lng(-17.0, 31.0),
        dropoff_location=Location.from_lat_lng(-17.1, 31.1), items=[],
        delivery_fee=2, tip_amount=0, total_amount=10,
        delivery_instructions="Destination",
    )

    class FakeOrder:
        get = AsyncMock(return_value=current_order)

    class BrokenRestaurant:
        merchant_id = SimpleNamespace(__eq__=lambda self, value: value)
        find_one = AsyncMock(side_effect=RuntimeError("catalog"))

    class BrokenUser:
        get = AsyncMock(side_effect=RuntimeError("auth"))

    monkeypatch.setattr(order_models, "Order", FakeOrder)
    monkeypatch.setattr(catalog_models, "Restaurant", BrokenRestaurant)
    monkeypatch.setattr(auth_models, "User", BrokenUser)
    payload = await module.NotificationService._build_offer_payload("order-1", "driver-1", 0)
    assert payload["merchant_name"] == "Unknown Restaurant"
    assert payload["customer_name"] == "Customer"


def test_paynow_missing_optional_dependency(monkeypatch):
    import app.payment.paynow_client as module

    monkeypatch.setattr(module.settings, "PAYMENT_MOCK_MODE", False)
    monkeypatch.setattr(module.settings, "PAYNOW_INTEGRATION_ID", "id")
    monkeypatch.setattr(module.settings, "PAYNOW_INTEGRATION_KEY", "key")
    original_import = builtins.__import__

    def fail_paynow(name, *args, **kwargs):
        if name == "paynow":
            raise ImportError("not installed")
        return original_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", fail_paynow)
    with pytest.raises(RuntimeError, match="package is not installed"):
        module.PaynowClient()


@pytest.mark.asyncio
async def test_payment_success_transition_with_and_without_order(monkeypatch):
    from app.payment.service import PaymentService
    from app.order.service import OrderService

    transition = AsyncMock(return_value=SimpleNamespace(id="order-1"))
    monkeypatch.setattr(OrderService, "transition_state", transition)
    payment = SimpleNamespace(order_id="order-1")
    await PaymentService._on_payment_success(payment)
    transition.assert_awaited_once()
    transition.return_value = None
    await PaymentService._on_payment_success(payment)


def test_import_time_cors_warning(monkeypatch):
    import app.main as main_module

    monkeypatch.setattr(main_module.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(main_module.settings, "CORS_ORIGINS", "")
    importlib.reload(main_module)
    monkeypatch.setattr(main_module.settings, "ENVIRONMENT", "development")
    importlib.reload(main_module)


def test_sms_router_uses_the_shared_gateway():
    """The router must not build its own Africa's Talking client.

    It used to initialise one at import from AT_USERNAME/AT_API_KEY and fall
    back to a mock whenever the key was missing — including in production.
    """
    import app.sms.router as sms_module

    assert not hasattr(sms_module, "africastalking")
    assert sms_module.sms_gateway is not None
