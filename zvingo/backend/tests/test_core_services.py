import asyncio
import builtins
import sys
from datetime import datetime, timedelta
from types import ModuleType, SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import msgpack
import pytest
from jose import jwt

from app.auth.schemas import UserCreate
from app.auth.service import AuthService
from app.binproto.codec import BinProtoCodec, PTYPE_LOCATION
from app.catalog import maintenance
from app.config import Settings, settings
from app.finance.fee_calculator import (
    calculate_delivery_fee,
    calculate_delivery_fee_from_coords,
    haversine_km,
)
from app.location.service import LocationService
from app.order.state_machine import OrderState
from app.rate_limiter import RateLimiter, get_rate_limiter


class QueryResult:
    def __init__(self, value):
        self.value = value
        self.limit_value = None

    def limit(self, value):
        self.limit_value = value
        return self

    async def to_list(self):
        return self.value

    async def count(self):
        return self.value


class FakeHTTPResponse:
    def __init__(self, payload=None, status_code=200, error=None):
        self.payload = payload
        self.status_code = status_code
        self.error = error

    def raise_for_status(self):
        if self.error:
            raise self.error

    def json(self):
        return self.payload


class FakeHTTPClient:
    def __init__(self, response):
        self.response = response
        self.get = AsyncMock(return_value=response)
        self.post = AsyncMock(return_value=response)

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return False


class FakeRedis:
    def __init__(self):
        self.values = {}
        self.hashes = {}
        self.closed = False
        self.zcount = 0
        self.raise_on_zrem = None

    async def setex(self, key, ttl, value):
        self.values[key] = value

    async def get(self, key):
        return self.values.get(key)

    async def delete(self, key):
        self.values.pop(key, None)

    async def set(self, key, value):
        self.values[key] = value

    async def hgetall(self, key):
        return self.hashes.get(key, {})

    async def zremrangebyscore(self, *_):
        if self.raise_on_zrem:
            raise self.raise_on_zrem

    async def zcard(self, *_):
        return self.zcount

    async def zadd(self, *_):
        return 1

    async def expire(self, *_):
        return True

    async def close(self):
        self.closed = True


def test_fee_calculation_boundaries_and_coordinates():
    assert haversine_km(0, 0, 0, 0) == 0
    assert 111 < haversine_km(0, 0, 0, 1) < 112
    assert calculate_delivery_fee(0) == (5.0, 4.25)
    assert calculate_delivery_fee(-1) == (5.0, 4.25)
    assert calculate_delivery_fee(5.0) == (5.0, 4.25)
    assert calculate_delivery_fee(5.01) == (10.0, 8.5)
    gross, driver, distance = calculate_delivery_fee_from_coords(0, 0, 0, 1)
    assert (gross, driver) == (115.0, 97.75)
    assert distance == pytest.approx(111.19, abs=0.01)


def test_settings_cors_and_production_safety():
    base = {
        "MONGODB_URL": "mongodb://test",
        "REDIS_URL": "redis://test",
        "_env_file": None,
    }
    assert Settings(**base).cors_origins == ["*"]
    assert Settings(**base, CORS_ORIGINS=" https://a.test, ,https://b.test ").cors_origins == [
        "https://a.test",
        "https://b.test",
    ]
    with pytest.raises(ValueError, match="SECRET_KEY.*PAYMENT_MOCK_MODE.*PAYNOW"):
        Settings(**base, ENVIRONMENT="production")
    production = Settings(
        **base,
        ENVIRONMENT="production",
        SECRET_KEY="x" * 64,
        PAYMENT_MOCK_MODE=False,
        PAYNOW_INTEGRATION_ID="id",
        PAYNOW_INTEGRATION_KEY="key",
        SMS_MOCK_MODE=False,
        AFRICASTALKING_API_KEY="sms-key",
    )
    assert production.cors_origins == []


@pytest.mark.asyncio
async def test_rate_limiter_allowed_limited_error_and_singleton(monkeypatch):
    redis = FakeRedis()
    limiter = RateLimiter(redis)
    limiter.location_limit = 2
    assert await limiter.check_location_update("d1") == (True, None)
    redis.zcount = 2
    allowed, message = await limiter.check_location_update("d1")
    assert not allowed and "max 2" in message
    redis.raise_on_zrem = RuntimeError("redis down")
    assert await limiter.check_location_update("d1") == (True, None)

    import app.rate_limiter as module

    monkeypatch.setattr(module, "_limiter", None)
    assert await get_rate_limiter(redis) is await get_rate_limiter(FakeRedis())


def test_auth_password_hash_and_token():
    hashed = AuthService.get_password_hash("secret")
    assert hashed != "secret"
    assert AuthService.verify_password("secret", hashed)
    assert not AuthService.verify_password("wrong", hashed)
    token = AuthService.create_access_token(
        {"sub": "user-1"}, expires_delta=timedelta(minutes=5)
    )
    assert jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])["sub"] == "user-1"
    assert AuthService.create_access_token({"sub": "user-2"})


@pytest.mark.asyncio
async def test_auth_create_and_authenticate_user(monkeypatch):
    import app.auth.service as module

    inserted = AsyncMock()

    class FakeUser:
        email = "email-field"
        phone = "phone-field"

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.insert = inserted

    monkeypatch.setattr(module, "User", FakeUser)
    created = await AuthService.create_user(
        UserCreate(
            email="a@example.com",
            phone="+263770000000",
            password="secret",
            full_name="A User",
            role="driver",
        )
    )
    assert created.email == "a@example.com"
    inserted.assert_awaited_once()

    good = SimpleNamespace(hashed_password=AuthService.get_password_hash("secret"))
    FakeUser.find_one = AsyncMock(side_effect=[good])
    assert await AuthService.authenticate_user("a@example.com", "secret") is good
    FakeUser.find_one = AsyncMock(side_effect=[None, good])
    assert await AuthService.authenticate_user("+263", "secret") is good
    FakeUser.find_one = AsyncMock(side_effect=[None, None])
    assert await AuthService.authenticate_user("missing", "secret") is None
    FakeUser.find_one = AsyncMock(return_value=good)
    assert await AuthService.authenticate_user("a@example.com", "bad") is None


@pytest.mark.asyncio
async def test_auth_redis_tokens(monkeypatch):
    import redis.asyncio as aioredis

    redis = FakeRedis()
    monkeypatch.setattr(aioredis, "from_url", lambda *_args, **_kwargs: redis)
    digits = iter([1, 2, 3, 4, 5, 6])
    monkeypatch.setattr("secrets.randbelow", lambda _: next(digits))
    assert await AuthService.create_otp("+263") == "123456"
    assert await AuthService.verify_otp("+263", "123456") is True
    assert await AuthService.verify_otp("+263", "000000") is False
    monkeypatch.setattr("secrets.token_urlsafe", lambda _: "reset-token")
    assert await AuthService.create_password_reset_token("+263") == "reset-token"
    assert await AuthService.verify_reset_token("reset-token") == "+263"
    assert await AuthService.verify_reset_token("missing") is None
    assert redis.closed


@pytest.mark.asyncio
async def test_location_service_queries_and_geocoding(monkeypatch):
    import app.location.service as module

    query = QueryResult(["restaurant"])
    monkeypatch.setattr(module.Restaurant, "find", MagicMock(return_value=query))
    assert await LocationService.find_nearby_restaurants(1, 2, 3, 4) == ["restaurant"]
    assert query.limit_value == 4

    response = FakeHTTPResponse(
        [{"display_name": "Harare", "lat": "-17.8", "lon": "31.0", "type": "city"}]
    )
    client = FakeHTTPClient(response)
    monkeypatch.setattr(module.httpx, "AsyncClient", lambda: client)
    assert await LocationService.geocode("Harare") == [
        {"display_name": "Harare", "lat": -17.8, "lng": 31.0, "type": "city"}
    ]
    client.get.assert_awaited_once()
    monkeypatch.setattr(
        module.httpx,
        "AsyncClient",
        lambda: FakeHTTPClient(FakeHTTPResponse(error=RuntimeError("network"))),
    )
    assert await LocationService.geocode("bad") == []


@pytest.mark.asyncio
async def test_sync_service_deduplicates_and_serializes(monkeypatch):
    import app.sync.service as module

    class Item:
        def model_dump(self):
            return {"name": "Burger"}

    first = SimpleNamespace(
        id="1",
        state=OrderState.ACCEPTED,
        total_amount=10,
        pickup_location={"lat": 1},
        dropoff_location={"lat": 2},
        items=[Item()],
    )
    second = SimpleNamespace(
        id="2",
        state=OrderState.OFFERED,
        total_amount=20,
        pickup_location={},
        dropoff_location={},
        items=[],
    )
    class Field:
        def __eq__(self, other):
            return ("eq", other)

        def __ne__(self, other):
            return ("ne", other)

        def __ge__(self, other):
            return ("ge", other)

    class FakeOrder:
        driver_id = Field()
        state = Field()
        updated_at = Field()
        find = MagicMock(
            side_effect=[
                QueryResult([first]),
                QueryResult([first, second]),
                QueryResult([]),
                QueryResult([]),
            ]
        )

    monkeypatch.setattr(module, "Order", FakeOrder)
    redis = FakeRedis()
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    monkeypatch.setattr(module.time, "time", lambda: 1234)
    packed = await module.SyncService.get_deltas("driver", 0)
    decoded = msgpack.unpackb(packed)
    assert decoded["new_version"] == 1234
    assert [order["id"] for order in decoded["data"]["orders"]] == ["1", "2"]
    assert redis.values["sync_ts:driver"] == "1234"
    await module.SyncService.get_deltas("driver", 100)


@pytest.mark.asyncio
async def test_catalog_maintenance(monkeypatch):
    assert maintenance.get_default_restaurant_coords()[1] == settings.DEV_DEFAULT_BASE_LNG
    monkeypatch.setattr(
        maintenance.Restaurant, "find_all", MagicMock(return_value=QueryResult([]))
    )
    assert await maintenance.backfill_restaurant_locations() is None

    valid = SimpleNamespace(
        location=SimpleNamespace(coordinates=[31.0, -17.0]), save=AsyncMock()
    )
    missing = SimpleNamespace(location=None, save=AsyncMock())
    monkeypatch.setattr(
        maintenance.Restaurant,
        "find_all",
        MagicMock(return_value=QueryResult([valid, missing])),
    )
    await maintenance.backfill_restaurant_locations()
    valid.save.assert_not_awaited()
    missing.save.assert_awaited_once()
    await maintenance.backfill_restaurant_locations(force_all=True)
    assert valid.save.await_count == 1


@pytest.mark.asyncio
async def test_sms_gateway_modes_and_delivery(monkeypatch):
    import app.sms.gateway as module

    monkeypatch.setattr(settings, "SMS_MOCK_MODE", True)
    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(settings, "SMS_GATEWAY_URL", None)
    gateway = module.SMSGateway()
    assert await gateway.send_sms("+263", "hello") is True

    monkeypatch.setattr(settings, "SMS_GATEWAY_URL", "http://mock")
    client = FakeHTTPClient(FakeHTTPResponse(status_code=202))
    monkeypatch.setattr(module.httpx, "AsyncClient", lambda: client)
    assert await gateway._send_mock("+263", "hello") is True
    failing_client = FakeHTTPClient(FakeHTTPResponse())
    failing_client.post.side_effect = RuntimeError("down")
    monkeypatch.setattr(module.httpx, "AsyncClient", lambda: failing_client)
    assert await gateway._send_mock("+263", "hello") is False

    monkeypatch.setattr(settings, "SMS_MOCK_MODE", False)
    monkeypatch.setattr(settings, "AFRICASTALKING_API_KEY", "key")
    monkeypatch.setattr(settings, "AFRICASTALKING_USERNAME", "live")
    live = module.SMSGateway()
    client = FakeHTTPClient(FakeHTTPResponse(payload={"ok": True}))
    monkeypatch.setattr(module.httpx, "AsyncClient", lambda: client)
    assert await live.send_sms("+263", "hello") is True
    monkeypatch.setattr(
        module.httpx,
        "AsyncClient",
        lambda: FakeHTTPClient(FakeHTTPResponse(error=RuntimeError("down"))),
    )
    assert await live._send_africastalking("+263", "hello") is False

    monkeypatch.setattr(settings, "AFRICASTALKING_API_KEY", None)
    with pytest.raises(RuntimeError, match="API_KEY"):
        module.SMSGateway()
    monkeypatch.setattr(settings, "SMS_MOCK_MODE", True)
    monkeypatch.setattr(settings, "ENVIRONMENT", "production")
    with pytest.raises(RuntimeError, match="production"):
        module.SMSGateway()


@pytest.mark.asyncio
async def test_paynow_client_all_paths(monkeypatch):
    import app.payment.paynow_client as module

    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(settings, "PAYMENT_MOCK_MODE", True)
    client = module.PaynowClient()
    sent = await client.send_mobile("+263", "a@example.com", "ref", 10)
    assert sent.success and sent.poll_url == "mock://poll/ref"
    assert (await client.check_status(sent.poll_url)).paid
    assert not (await client.check_status("https://poll")).paid

    monkeypatch.setattr(settings, "PAYMENT_MOCK_MODE", False)
    monkeypatch.setattr(settings, "PAYNOW_INTEGRATION_ID", None)
    monkeypatch.setattr(settings, "PAYNOW_INTEGRATION_KEY", None)
    with pytest.raises(RuntimeError, match="INTEGRATION"):
        module.PaynowClient()

    monkeypatch.setattr(settings, "PAYNOW_INTEGRATION_ID", "id")
    monkeypatch.setattr(settings, "PAYNOW_INTEGRATION_KEY", "key")
    paynow = MagicMock()
    monkeypatch.setattr("paynow.Paynow", MagicMock(return_value=paynow))
    live = module.PaynowClient()
    payment = MagicMock()
    paynow.create_payment.return_value = payment
    paynow.send_mobile.return_value = SimpleNamespace(
        success=True, poll_url="https://poll", error=None
    )
    assert (await live.send_mobile("+263", "a@example.com", "ref", 10)).success
    payment.add.assert_called_once_with("Order Payment", 10)
    paynow.send_mobile.return_value = SimpleNamespace(success=False, error="declined")
    assert not (await live.send_mobile("+263", "a@example.com", "ref", 10)).success
    paynow.create_payment.side_effect = RuntimeError("gateway")
    assert (await live.send_mobile("+263", "a@example.com", "ref", 10)).error == "gateway"

    paynow.check_transaction_status.return_value = SimpleNamespace(
        paid=True, status="Paid", amount="9.50"
    )
    paynow.create_payment.side_effect = None
    status = await live.check_status("https://poll")
    assert status.paid and status.amount == 9.5
    paynow.check_transaction_status.return_value = SimpleNamespace(paid=False)
    status = await live.check_status("https://poll")
    assert status.status == "Unknown" and status.amount == 0
    paynow.check_transaction_status.side_effect = RuntimeError("gateway")
    assert (await live.check_status("https://poll")).status == "Error"

    monkeypatch.setattr(settings, "PAYMENT_MOCK_MODE", True)
    monkeypatch.setattr(settings, "ENVIRONMENT", "production")
    with pytest.raises(RuntimeError, match="production"):
        module.PaynowClient()

    assert module.PaynowResponse(True).success
    assert module.PaynowStatusResponse(False).status == ""


@pytest.mark.asyncio
async def test_fcm_initialization_and_send(monkeypatch):
    import app.notification.fcm as module

    monkeypatch.setattr(module, "_fcm_initialized", False)
    monkeypatch.setattr(settings, "FIREBASE_CREDENTIALS_PATH", None)
    assert module.init_firebase() is None
    assert await module.send_push_notification("token", "Title", "Body") is False

    monkeypatch.setattr(settings, "FIREBASE_CREDENTIALS_PATH", "creds.json")
    fake_credentials = ModuleType("firebase_admin.credentials")
    fake_credentials.Certificate = MagicMock(return_value="cred")
    fake_firebase = ModuleType("firebase_admin")
    fake_firebase.__path__ = []
    fake_firebase.credentials = fake_credentials
    fake_firebase.initialize_app = MagicMock()
    monkeypatch.setitem(sys.modules, "firebase_admin", fake_firebase)
    monkeypatch.setitem(sys.modules, "firebase_admin.credentials", fake_credentials)
    module.init_firebase()
    assert module._fcm_initialized
    module.init_firebase()

    message = SimpleNamespace(
        Message=MagicMock(return_value="message"),
        Notification=MagicMock(return_value="notification"),
        send=MagicMock(return_value="response"),
    )
    monkeypatch.setitem(sys.modules, "firebase_admin.messaging", message)
    fake_firebase.messaging = message
    assert await module.send_push_notification("token", "Title", "Body", {"a": "b"})
    message.send.side_effect = RuntimeError("fcm")
    assert not await module.send_push_notification("token", "Title", "Body")

    monkeypatch.setattr(module, "_fcm_initialized", False)
    fake_credentials.Certificate.side_effect = RuntimeError("bad creds")
    module.init_firebase()

    real_import = builtins.__import__

    def missing_firebase(name, *args, **kwargs):
        if name == "firebase_admin":
            raise ImportError("missing")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", missing_firebase)
    fake_credentials.Certificate.side_effect = None
    module.init_firebase()


@pytest.mark.asyncio
async def test_db_initialization(monkeypatch):
    import app.db.session as module

    database = object()

    class Client:
        def __init__(self, url):
            self.url = url

        def __getitem__(self, name):
            assert name == settings.MONGODB_DB_NAME
            return database

    init = AsyncMock()
    monkeypatch.setattr(module, "AsyncIOMotorClient", Client)
    monkeypatch.setattr(module, "init_beanie", init)
    await module.init_db()
    assert init.await_args.kwargs["database"] is database
    assert len(init.await_args.kwargs["document_models"]) == 7


@pytest.mark.asyncio
async def test_binproto_session_resolution_and_servers(monkeypatch):
    import app.binproto.tcp_server as tcp
    import app.binproto.udp_server as udp

    redis = FakeRedis()
    redis.values["binproto_session:3132333435363738"] = "driver"
    monkeypatch.setattr(tcp.aioredis, "from_url", lambda *_a, **_k: redis)
    monkeypatch.setattr(udp.aioredis, "from_url", lambda *_a, **_k: redis)
    assert await tcp.resolve_driver_id(b"12345678") == "driver"
    assert await udp.resolve_driver_id(b"12345678") == "driver"

    server = SimpleNamespace(
        __aenter__=AsyncMock(), __aexit__=AsyncMock(), serve_forever=AsyncMock()
    )

    class ServerContext:
        async def __aenter__(self):
            return server

        async def __aexit__(self, *_):
            return False

        async def serve_forever(self):
            return None

    start = AsyncMock(return_value=ServerContext())
    monkeypatch.setattr(tcp.asyncio, "start_server", start)
    await tcp.start_tcp_server()
    start.assert_awaited_once()

    transport = object()
    loop = SimpleNamespace(create_datagram_endpoint=AsyncMock(return_value=(transport, object())))
    monkeypatch.setattr(udp.asyncio, "get_running_loop", lambda: loop)
    assert await udp.start_udp_server() is transport
    loop.create_datagram_endpoint.side_effect = OSError("port")
    assert await udp.start_udp_server() is None
