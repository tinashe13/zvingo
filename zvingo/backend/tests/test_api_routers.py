import asyncio
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import BackgroundTasks, HTTPException
from jose import jwt

from app.auth.schemas import OTPRequest, OTPVerify, UserCreate
from app.config import settings
from app.dispatch.schemas import DriverLocationUpdate
from app.order.state_machine import OrderState
from app.payment.models import PaymentMethod, PaymentStatus
from app.payment.schemas import PaymentInitiate
from app.sync.schemas import SyncRequest


class Field:
    def __eq__(self, other):
        return ("eq", other)


class QueryResult:
    def __init__(self, values):
        self.values = values

    async def to_list(self):
        return self.values


class FakeRedis:
    def __init__(self):
        self.closed = False

    async def close(self):
        self.closed = True


def user(**overrides):
    values = {
        "id": "user-1",
        "email": "user@example.com",
        "phone": "+263770000000",
        "full_name": "User One",
        "role": "consumer",
        "is_active": True,
        "driver_rating": None,
        "driver_review_count": 0,
        "fcm_token": None,
        "favourite_restaurant_ids": [],
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def payment(**overrides):
    values = {
        "id": "payment-1",
        "order_id": "order-1",
        "consumer_id": "user-1",
        "amount_usd": 10.0,
        "amount_local": 10.0,
        "currency": "USD",
        "method": PaymentMethod.ECOCASH,
        "status": PaymentStatus.PENDING,
        "paynow_reference": "ref",
        "created_at": datetime.now(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
async def test_auth_current_user_registration_and_login(monkeypatch):
    import app.auth.router as module

    current = user()

    class FakeUser:
        phone = Field()
        email = Field()
        get = AsyncMock(return_value=current)
        find_one = AsyncMock()

    monkeypatch.setattr(module, "User", FakeUser)
    token = module.AuthService.create_access_token({"sub": "user-1"})
    assert await module.get_current_user(token) is current

    FakeUser.get.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.get_current_user(token)
    assert exc.value.status_code == 401
    with pytest.raises(HTTPException):
        await module.get_current_user("not-a-token")
    no_sub = jwt.encode({}, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    with pytest.raises(HTTPException):
        await module.get_current_user(no_sub)

    request = UserCreate(
        phone="+263770000000", password="password", full_name="User One"
    )
    FakeUser.find_one.return_value = current
    with pytest.raises(HTTPException, match="Phone already"):
        await module.register(request)
    request.email = "new@example.com"
    FakeUser.find_one.side_effect = [None, current]
    with pytest.raises(HTTPException, match="Email already"):
        await module.register(request)
    FakeUser.find_one.side_effect = None
    FakeUser.find_one.return_value = None
    monkeypatch.setattr(module.AuthService, "create_user", AsyncMock(return_value=current))
    result = await module.register(request)
    assert result["token_type"] == "bearer"

    form = SimpleNamespace(username="user@example.com", password="password")
    monkeypatch.setattr(module.AuthService, "authenticate_user", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.login_for_access_token(form)
    assert exc.value.status_code == 401
    module.AuthService.authenticate_user.return_value = current
    assert (await module.login_for_access_token(form))["access_token"]


@pytest.mark.asyncio
async def test_auth_profile_otp_fcm_reset_and_favourites(monkeypatch):
    import app.auth.router as module
    import app.sms.gateway as sms_module

    current = user()
    profile = await module.get_me(current)
    assert profile.id == "user-1"
    updated = await module.update_me(
        module.UserUpdate(full_name="New Name", email="new@example.com"), current
    )
    assert updated.full_name == "New Name"
    await module.update_me(module.UserUpdate(), current)

    class FakeUser:
        phone = Field()
        find_one = AsyncMock(return_value=None)

    monkeypatch.setattr(module, "User", FakeUser)
    with pytest.raises(HTTPException) as exc:
        await module.request_otp(OTPRequest(phone=current.phone))
    assert exc.value.status_code == 404
    FakeUser.find_one.return_value = current
    monkeypatch.setattr(module.AuthService, "create_otp", AsyncMock(return_value="123456"))
    monkeypatch.setattr(sms_module.sms_gateway, "send_sms", AsyncMock(return_value=True))
    assert await module.request_otp(OTPRequest(phone=current.phone)) == {"status": "otp_sent"}

    monkeypatch.setattr(module.AuthService, "verify_otp", AsyncMock(return_value=False))
    with pytest.raises(HTTPException, match="Invalid or expired"):
        await module.verify_otp(OTPVerify(phone=current.phone, code="bad"))
    module.AuthService.verify_otp.return_value = True
    FakeUser.find_one.return_value = None
    with pytest.raises(HTTPException, match="User not found"):
        await module.verify_otp(OTPVerify(phone=current.phone, code="123456"))
    FakeUser.find_one.return_value = current
    assert (await module.verify_otp(OTPVerify(phone=current.phone, code="123456")))[
        "access_token"
    ]

    assert await module.register_fcm_token(module.FCMTokenRequest(token="fcm"), current) == {
        "status": "updated"
    }
    assert current.fcm_token == "fcm"

    FakeUser.find_one.return_value = None
    assert await module.request_password_reset(
        module.PasswordResetRequest(phone=current.phone)
    ) == {"status": "reset_initiated"}
    FakeUser.find_one.return_value = current
    monkeypatch.setattr(
        module.AuthService,
        "create_password_reset_token",
        AsyncMock(return_value="reset-token-long"),
    )
    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    assert (await module.request_password_reset(module.PasswordResetRequest(phone=current.phone)))[
        "token"
    ] == "reset-token-long"
    monkeypatch.setattr(settings, "ENVIRONMENT", "production")
    assert await module.request_password_reset(
        module.PasswordResetRequest(phone=current.phone)
    ) == {"status": "reset_initiated"}

    monkeypatch.setattr(module.AuthService, "verify_reset_token", AsyncMock(return_value=None))
    with pytest.raises(HTTPException, match="Invalid or expired"):
        await module.confirm_password_reset(
            module.PasswordResetConfirm(token="bad", new_password="new")
        )
    module.AuthService.verify_reset_token.return_value = current.phone
    FakeUser.find_one.return_value = None
    with pytest.raises(HTTPException, match="User not found"):
        await module.confirm_password_reset(
            module.PasswordResetConfirm(token="ok", new_password="new")
        )
    FakeUser.find_one.return_value = current
    monkeypatch.setattr(module.AuthService, "get_password_hash", lambda value: f"hashed-{value}")
    assert await module.confirm_password_reset(
        module.PasswordResetConfirm(token="ok", new_password="new")
    ) == {"status": "password_reset"}
    assert current.hashed_password == "hashed-new"

    assert await module.get_favourites(current) == {"favourite_restaurant_ids": []}
    added = await module.toggle_favourite("restaurant", current)
    assert added["action"] == "added"
    removed = await module.toggle_favourite("restaurant", current)
    assert removed["action"] == "removed"


@pytest.mark.asyncio
async def test_payment_router_all_paths(monkeypatch):
    import app.payment.router as module

    current = user()
    request = PaymentInitiate(
        order_id="order-1", method=PaymentMethod.ECOCASH, phone=current.phone
    )

    class FakeOrder:
        get = AsyncMock(return_value=None)

    monkeypatch.setattr(module, "Order", FakeOrder)
    with pytest.raises(HTTPException, match="Order not found"):
        await module.initiate_payment(request, current)
    order = SimpleNamespace(consumer_id="other", total_amount=10)
    FakeOrder.get.return_value = order
    with pytest.raises(HTTPException, match="Not your order"):
        await module.initiate_payment(request, current)
    order.consumer_id = "user-1"
    monkeypatch.setattr(
        module.PaymentService,
        "get_payment_for_order",
        AsyncMock(return_value=payment(status=PaymentStatus.PAID)),
    )
    with pytest.raises(HTTPException, match="already exists"):
        await module.initiate_payment(request, current)
    module.PaymentService.get_payment_for_order.return_value = payment(
        status=PaymentStatus.AWAITING_DELIVERY
    )
    with pytest.raises(HTTPException, match="already exists"):
        await module.initiate_payment(request, current)
    module.PaymentService.get_payment_for_order.return_value = payment(
        status=PaymentStatus.FAILED
    )
    created = payment()
    monkeypatch.setattr(module.PaymentService, "initiate_payment", AsyncMock(return_value=created))
    assert (await module.initiate_payment(request, current)).id == "payment-1"
    assert module._payment_to_response(created).order_id == "order-1"

    form_request = SimpleNamespace(
        form=AsyncMock(
            return_value={"reference": "ref", "status": "paid", "pollurl": "poll"}
        )
    )
    monkeypatch.setattr(module.PaymentService, "handle_webhook", AsyncMock(return_value=None))
    with pytest.raises(HTTPException, match="Payment not found"):
        await module.payment_webhook(form_request)
    module.PaymentService.handle_webhook.return_value = created
    assert await module.payment_webhook(form_request) == {"status": "ok"}

    monkeypatch.setattr(module.PaymentService, "check_payment_status", AsyncMock(return_value=None))
    with pytest.raises(HTTPException, match="Payment not found"):
        await module.check_payment_status("p", current)
    foreign = payment(consumer_id="other")
    module.PaymentService.check_payment_status.return_value = foreign
    with pytest.raises(HTTPException, match="Not your payment"):
        await module.check_payment_status("p", current)
    module.PaymentService.check_payment_status.return_value = created
    assert (await module.check_payment_status("p", current)).id == "payment-1"

    module.PaymentService.get_payment_for_order.return_value = None
    with pytest.raises(HTTPException, match="No payment"):
        await module.get_payment_for_order("o", current)
    module.PaymentService.get_payment_for_order.return_value = foreign
    with pytest.raises(HTTPException, match="Not your payment"):
        await module.get_payment_for_order("o", current)
    module.PaymentService.get_payment_for_order.return_value = created
    assert (await module.get_payment_for_order("o", current)).id == "payment-1"

    # Refund: now requires ownership (or admin) and fetches the payment first.
    class FakePayment:
        get = AsyncMock(return_value=None)

    monkeypatch.setattr(module, "Payment", FakePayment)
    with pytest.raises(HTTPException, match="Payment not found"):
        await module.refund_payment("p", current)
    FakePayment.get.return_value = created
    monkeypatch.setattr(module.PaymentService, "refund_payment", AsyncMock(return_value=created))
    assert (await module.refund_payment("p", current)).status == PaymentStatus.PENDING
    # A non-owner (and non-admin) cannot refund someone else's payment.
    with pytest.raises(HTTPException, match="Not authorized to refund"):
        await module.refund_payment("p", user(id="stranger"))
    # An admin can refund any payment.
    assert (await module.refund_payment("p", user(id="admin", role="admin"))).status == PaymentStatus.PENDING


@pytest.mark.asyncio
async def test_dispatch_router_all_paths(monkeypatch):
    import app.dispatch.router as module
    import app.order.models as order_models

    redis = FakeRedis()
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    assert await module.get_redis() is redis

    limiter = SimpleNamespace(check_location_update=AsyncMock(return_value=(False, "slow down")))
    monkeypatch.setattr(module, "RateLimiter", lambda _: limiter)
    update = DriverLocationUpdate(driver_id="d", lat=1, lng=2)
    with pytest.raises(HTTPException) as exc:
        await module.update_location(update, BackgroundTasks(), "token", redis)
    assert exc.value.status_code == 429
    limiter.check_location_update.return_value = (True, None)
    tasks = BackgroundTasks()
    assert await module.update_location(update, tasks, "token", redis) == {
        "status": "received"
    }
    assert len(tasks.tasks) == 1

    current = user(id="driver")
    request = module.OfferActionRequest(order_id="order")
    monkeypatch.setattr(module.dispatch_service, "accept_offer", AsyncMock(return_value=None))
    with pytest.raises(HTTPException, match="Could not accept"):
        await module.accept_offer(request, current)
    module.dispatch_service.accept_offer.return_value = object()
    assert (await module.accept_offer(request, current))["status"] == "accepted"
    monkeypatch.setattr(module.dispatch_service, "decline_offer", AsyncMock(return_value={}))
    assert (await module.decline_offer(request, current))["status"] == "declined"

    monkeypatch.setattr(
        module.dispatch_service,
        "get_driver_state",
        AsyncMock(return_value={"status": "OFFLINE", "active_order": None}),
    )
    assert (await module.get_driver_state(current))["active_order"] is None
    active = SimpleNamespace(
        id="abcdef",
        state=OrderState.ACCEPTED,
        pickup_location={"lat": 1},
        dropoff_location={"lat": 2},
    )
    module.dispatch_service.get_driver_state.return_value = {
        "status": "ONLINE",
        "active_order": active,
    }
    assert (await module.get_driver_state(current))["active_order"]["short_id"] == "ZVCDEF"

    orders = [SimpleNamespace(state=OrderState.ACCEPTED, save=AsyncMock()) for _ in range(2)]

    class FakeOrder:
        find = MagicMock(return_value=QueryResult(orders))

    monkeypatch.setattr(order_models, "Order", FakeOrder)
    reset = await module.reset_driver_state(current)
    assert reset["orders_reset"] == 2
    assert all(order.state == OrderState.DELIVERED for order in orders)


@pytest.mark.asyncio
async def test_location_sync_and_sms_routers(monkeypatch):
    import app.location.router as location
    import app.sms.router as sms
    import app.sync.router as sync

    monkeypatch.setattr(
        location.LocationService,
        "find_nearby_restaurants",
        AsyncMock(return_value=["restaurant"]),
    )
    assert await location.nearby_restaurants(1, 2, 3) == ["restaurant"]
    monkeypatch.setattr(location.LocationService, "geocode", AsyncMock(return_value=["place"]))
    assert await location.geocode("Harare", "zw") == ["place"]

    current = user(id="driver")
    with pytest.raises(HTTPException) as exc:
        await sync.pull_changes(SyncRequest(driver_id="other", last_version=0), current)
    assert exc.value.status_code == 403
    monkeypatch.setattr(sync.SyncService, "get_deltas", AsyncMock(return_value=b"packed"))
    response = await sync.pull_changes(SyncRequest(driver_id="driver", last_version=0), current)
    assert response.body == b"packed"
    assert response.media_type == "application/x-msgpack"

    request = sms.SMSRequest(to="+263", message="hello")
    monkeypatch.setattr(sms, "sms", None)
    assert (await sms.send_sms(request, current))["provider"] == "mock"
    provider = SimpleNamespace(send=MagicMock(return_value={"ok": True}))
    monkeypatch.setattr(sms, "sms", provider)
    assert (await sms.send_sms(request, current))["provider"] == "africastalking"
    provider.send.side_effect = RuntimeError("provider down")
    with pytest.raises(HTTPException) as exc:
        await sms.send_sms(request, current)
    assert exc.value.status_code == 500


@pytest.mark.asyncio
async def test_http_integration_route_wiring(monkeypatch):
    """Exercise real FastAPI validation, serialization, and dependency wiring."""
    from fastapi import FastAPI
    from httpx import ASGITransport, AsyncClient

    import app.auth.router as auth
    import app.location.router as location

    test_app = FastAPI()
    test_app.include_router(auth.router, prefix="/auth")
    test_app.include_router(location.router, prefix="/location")
    test_app.dependency_overrides[auth.get_current_user] = lambda: user()
    monkeypatch.setattr(location.LocationService, "geocode", AsyncMock(return_value=[]))

    async with AsyncClient(
        transport=ASGITransport(app=test_app), base_url="http://test"
    ) as client:
        assert (await client.get("/auth/me")).status_code == 200
        assert (await client.get("/location/geocode", params={"q": "Harare"})).status_code == 200
        assert (await client.get("/location/geocode")).status_code == 422
