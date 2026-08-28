"""Tests for the post-refactor feature build-out:

- promo code redemption (service + validate endpoint)
- order reorder endpoint
- ratings & reviews router
- in-app chat router
- refund authorization + provider failure paths
- admin-only dependency
"""

from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from app.location.models import Location
from app.order.schemas import OrderCreate, OrderItem
from app.order.state_machine import OrderState
from app.payment.models import PaymentStatus


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


def user(id="user-1", role="consumer"):
    return SimpleNamespace(id=id, role=role, save=AsyncMock())


def promo(**overrides):
    values = {
        "id": "promo-1",
        "promo_id": "p1",
        "merchant_id": "merchant-1",
        "title": "Deal",
        "subtitle": "Save",
        "code": "SAVE10",
        "promo_type": "percentage",
        "discount_value": 10.0,
        "min_order_usd": 0.0,
        "max_discount_usd": None,
        "starts_at": datetime.now() - timedelta(days=1),
        "ends_at": None,
        "is_active": True,
        "max_uses": None,
        "max_uses_per_user": 1,
        "current_uses": 0,
        "redeemed_by": [],
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


# ── Promo service ─────────────────────────────────────────────


@pytest.mark.asyncio
async def test_promotion_service_discount_paths(monkeypatch):
    import app.catalog.promotion_service as module

    pct = promo()
    flat = promo(code="FLAT5", promo_type="flat", discount_value=5.0)
    fdl = promo(code="FREE", promo_type="free_delivery", discount_value=0.0)
    capped = promo(code="CAP", max_discount_usd=2.0)

    mapping = {"SAVE10": pct, "FLAT5": flat, "FREE": fdl, "CAP": capped}

    async def find(code):
        return mapping.get(code)

    monkeypatch.setattr(module, "_find_promo", find)

    assert await module.compute_discount("SAVE10", "u1", 100.0) == 10.0
    assert await module.compute_discount("FLAT5", "u1", 100.0) == 5.0
    assert await module.compute_discount("CAP", "u1", 100.0) == 2.0
    assert await module.compute_discount("FREE", "u1", 100.0) == 0.0
    assert await module.is_free_delivery("FREE") is True
    assert await module.is_free_delivery("SAVE10") is False

    discount, fd = await module.validate_and_compute("SAVE10", "u1", 100.0)
    assert (discount, fd) == (10.0, False)


@pytest.mark.asyncio
async def test_promotion_service_validation_errors(monkeypatch):
    import app.catalog.promotion_service as module

    now = datetime.now()
    cases = {
        "INVALID": promo(code="INVALID", is_active=False),  # inactive
        "FUTURE": promo(code="FUTURE", starts_at=now + timedelta(days=1)),
        "EXPIRED": promo(code="EXPIRED", ends_at=now - timedelta(days=1)),
        "MIN": promo(code="MIN", min_order_usd=50.0),
        "CAP": promo(code="CAP", max_uses=1, current_uses=1),
        "USED": promo(code="USED", redeemed_by=["u1"]),
        "NOPE": promo(code="NOPE", promo_type="mystery"),
    }

    async def find(code):
        return cases.get(code)

    monkeypatch.setattr(module, "_find_promo", find)

    with pytest.raises(module.PromotionError):
        await module.compute_discount("MISSING", "u1", 10.0)
    for code in ("INVALID", "FUTURE", "EXPIRED", "MIN", "CAP", "USED", "NOPE"):
        with pytest.raises(module.PromotionError):
            await module.compute_discount(code, "u1", 10.0)

    # Empty code is rejected early.
    with pytest.raises(module.PromotionError):
        await module.compute_discount("", "u1", 10.0)


@pytest.mark.asyncio
async def test_promotion_service_record_redemption(monkeypatch):
    import app.catalog.promotion_service as module

    p = promo()
    monkeypatch.setattr(module, "_find_promo", AsyncMock(return_value=p))
    await module.record_redemption("SAVE10", "u1")
    assert p.current_uses == 1
    assert p.redeemed_by == ["u1"]
    p.save.assert_awaited_once()

    # Missing promo is a no-op (never raises).
    monkeypatch.setattr(module, "_find_promo", AsyncMock(return_value=None))
    await module.record_redemption("MISSING", "u1")


# ── Promo validate endpoint ──────────────────────────────────


@pytest.mark.asyncio
async def test_validate_promo_endpoint(monkeypatch):
    import app.catalog.promotion_service as promo_service
    import app.catalog.router as module

    monkeypatch.setattr(
        promo_service, "validate_and_compute", AsyncMock(return_value=(5.0, True))
    )
    req = module.PromoValidateRequest(code="SAVE10", order_subtotal_usd=50.0)
    result = await module.validate_promo_code(req, user())
    assert result == {"code": "SAVE10", "discount_usd": 5.0, "free_delivery": True}

    monkeypatch.setattr(
        promo_service,
        "validate_and_compute",
        AsyncMock(side_effect=promo_service.PromotionError("bad code")),
    )
    with pytest.raises(HTTPException) as exc:
        await module.validate_promo_code(req, user())
    assert exc.value.status_code == 400


# ── Reorder ──────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_reorder_endpoint(monkeypatch):
    import app.order.router as module

    new_order = SimpleNamespace(
        id="order-2",
        state=OrderState.CREATED,
        total_amount=22,
        created_at=datetime.now(),
        merchant_id="restaurant-1",
        consumer_id="user-1",
        items=[SimpleNamespace(name="Burger", quantity=2, price=10)],
        pickup_location=Location.from_lat_lng(-17.8, 31.0),
        dropoff_location=Location.from_lat_lng(-17.9, 31.1),
    )
    monkeypatch.setattr(module.OrderService, "reorder", AsyncMock(return_value=new_order))
    result = await module.reorder("order-1", user())
    assert result.id == "order-2"

    monkeypatch.setattr(module.OrderService, "reorder", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.reorder("missing", user())
    assert exc.value.status_code == 404

    monkeypatch.setattr(module.OrderService, "reorder", AsyncMock(side_effect=ValueError("no")))
    with pytest.raises(HTTPException) as exc:
        await module.reorder("order-1", user())
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_reorder_service(monkeypatch):
    import app.dispatch.service as dispatch_module
    import app.notification.service as notification_module
    import app.order.service as module

    original = SimpleNamespace(
        id="order-1",
        merchant_id="restaurant-1",
        consumer_id="user-1",
        items=[SimpleNamespace(name="Burger", quantity=2, price=10, model_dump=MagicMock(return_value={"name": "Burger", "quantity": 2, "price": 10}))],
        total_amount=22,
        pickup_location=Location.from_lat_lng(-17.8, 31.0),
        dropoff_location=Location.from_lat_lng(-17.9, 31.1),
        tip_amount=1.0,
        delivery_fee=5.0,
        service_fee=1.0,
        tax_amount=0.5,
    )

    class FakeOrder:
        get = AsyncMock(return_value=original)
        instances = []

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "order-2"
            self.insert = AsyncMock(side_effect=lambda: FakeOrder.instances.append(self))

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(notification_module.notification_service, "notify_merchant", AsyncMock())
    monkeypatch.setattr(dispatch_module.dispatch_service, "dispatch_order", AsyncMock())
    monkeypatch.setattr(module.asyncio, "create_task", lambda coro: (coro.close(), MagicMock())[1])

    created = await module.OrderService.reorder("order-1", "user-1")
    assert created.merchant_id == "restaurant-1"
    assert created.total_amount == 22

    # Not the owner → ValueError.
    with pytest.raises(ValueError, match="Not your order"):
        await module.OrderService.reorder("order-1", "other")

    # Empty order → ValueError.
    original.items = []
    with pytest.raises(ValueError, match="empty"):
        await module.OrderService.reorder("order-1", "user-1")

    # Missing → None.
    FakeOrder.get.return_value = None
    assert await module.OrderService.reorder("missing", "user-1") is None


# ── Ratings & reviews ────────────────────────────────────────


@pytest.mark.asyncio
async def test_rating_review_creation_and_lists(monkeypatch):
    import app.catalog.models as catalog_models
    import app.rating.router as module
    import app.rating.schemas as schemas

    order = SimpleNamespace(
        id="order-1",
        consumer_id="user-1",
        driver_id="driver-1",
        merchant_id="restaurant-1",
        state=OrderState.DELIVERED,
    )

    class FakeOrder:
        get = AsyncMock(return_value=order)

    monkeypatch.setattr(module, "Order", FakeOrder)

    review = SimpleNamespace(
        id="review-1",
        order_id="order-1",
        consumer_id="user-1",
        restaurant_id="restaurant-1",
        driver_id="driver-1",
        restaurant_rating=5,
        driver_rating=4,
        comment="great",
        created_at=datetime.now(),
    )

    class FakeReview:
        order_id = Field()
        restaurant_id = Field()
        driver_id = Field()
        get = AsyncMock(return_value=None)
        find_one = AsyncMock(return_value=None)
        found = [review]

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "review-1"
            self.created_at = datetime.now()
            self.insert = AsyncMock()

        @classmethod
        def find(cls, *args):
            return Query(cls.found)

    monkeypatch.setattr(module, "Review", FakeReview)

    # Create review: not the consumer → 403.
    with pytest.raises(HTTPException) as exc:
        await module.create_review("order-1", schemas.ReviewCreate(restaurant_rating=5), user("other"))
    assert exc.value.status_code == 403

    # Not delivered → 400.
    order.consumer_id = "user-1"
    order.state = OrderState.CREATED
    with pytest.raises(HTTPException) as exc:
        await module.create_review("order-1", schemas.ReviewCreate(restaurant_rating=5), user())
    assert exc.value.status_code == 400
    order.state = OrderState.DELIVERED

    # Restaurant aggregate update with review_count set.
    restaurant = SimpleNamespace(review_count=10, rating=4.5, save=AsyncMock())
    class FakeRestaurant:
        get = AsyncMock(return_value=restaurant)

    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)

    created = await module.create_review(
        "order-1", schemas.ReviewCreate(restaurant_rating=5, driver_rating=4, comment="great"), user()
    )
    assert created.id == "review-1"
    assert restaurant.review_count == 11

    # Already reviewed → 400.
    FakeReview.find_one.return_value = review
    with pytest.raises(HTTPException) as exc:
        await module.create_review("order-1", schemas.ReviewCreate(restaurant_rating=5), user())
    assert exc.value.status_code == 400
    FakeReview.find_one.return_value = None

    # Missing order → 404.
    FakeOrder.get.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.create_review("missing", schemas.ReviewCreate(restaurant_rating=5), user())
    assert exc.value.status_code == 404

    # Lists.
    assert len(await module.list_restaurant_reviews("restaurant-1")) == 1
    assert len(await module.list_driver_reviews("driver-1")) == 1


@pytest.mark.asyncio
async def test_rating_review_restaurant_no_review_count(monkeypatch):
    import app.catalog.models as catalog_models
    import app.rating.router as module
    import app.rating.schemas as schemas

    order = SimpleNamespace(
        id="order-1", consumer_id="user-1", driver_id=None,
        merchant_id="restaurant-1", state=OrderState.DELIVERED,
    )
    class FakeOrder:
        get = AsyncMock(return_value=order)
    monkeypatch.setattr(module, "Order", FakeOrder)

    class FakeReview:
        order_id = Field()
        find_one = AsyncMock(return_value=None)

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "review-1"
            self.created_at = datetime.now()
            self.insert = AsyncMock()

    monkeypatch.setattr(module, "Review", FakeReview)

    restaurant = SimpleNamespace(review_count=None, rating=4.5, save=AsyncMock())
    class FakeRestaurant:
        get = AsyncMock(return_value=restaurant)
    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)

    created = await module.create_review(
        "order-1", schemas.ReviewCreate(restaurant_rating=4), user()
    )
    assert created.id == "review-1"
    assert restaurant.review_count == 1
    assert restaurant.rating == 4.0


# ── Chat ─────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_chat_send_and_list(monkeypatch):
    import app.chat.router as module
    import app.chat.schemas as schemas
    import app.catalog.models as catalog_models

    order = SimpleNamespace(
        id="order-1", consumer_id="user-1", driver_id="driver-1", merchant_id="restaurant-1"
    )

    class FakeOrder:
        get = AsyncMock(return_value=order)

    monkeypatch.setattr(module, "Order", FakeOrder)

    message = SimpleNamespace(
        id="m1", order_id="order-1", sender_id="user-1", sender_role="consumer",
        text="hello", created_at=datetime.now(),
    )

    class FakeMessage:
        order_id = Field()
        found = [message]

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "m1"
            self.created_at = datetime.now()
            self.insert = AsyncMock()

        @classmethod
        def find(cls, *args):
            return Query(cls.found)

    monkeypatch.setattr(module, "ChatMessage", FakeMessage)

    class Redis:
        publish = AsyncMock()
        close = AsyncMock()

    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: Redis())

    # Send as consumer (participant).
    sent = await module.send_message("order-1", schemas.ChatMessageCreate(text="hello"), user())
    assert sent.id == "m1"
    # List as consumer.
    listed = await module.list_messages("order-1", user())
    assert len(listed) == 1

    # Non-participant → 403.
    class FakeRestaurant:
        get = AsyncMock(return_value=SimpleNamespace(merchant_id="someone-else"))
    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    with pytest.raises(HTTPException) as exc:
        await module.send_message("order-1", schemas.ChatMessageCreate(text="x"), user("stranger"))
    assert exc.value.status_code == 403
    with pytest.raises(HTTPException) as exc:
        await module.list_messages("order-1", user("stranger"))
    assert exc.value.status_code == 403

    # Missing order → 404.
    FakeOrder.get.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.send_message("missing", schemas.ChatMessageCreate(text="x"), user())
    assert exc.value.status_code == 404
    with pytest.raises(HTTPException) as exc:
        await module.list_messages("missing", user())
    assert exc.value.status_code == 404

    # Merchant who owns the restaurant is a participant.
    FakeOrder.get.return_value = order
    class FakeRestaurant:
        get = AsyncMock(return_value=SimpleNamespace(merchant_id="merchant-1"))
    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    assert await module._can_participate(order, user("merchant-1", role="merchant")) is True


# ── Admin dependency & refund paths ──────────────────────────


@pytest.mark.asyncio
async def test_get_current_admin(monkeypatch):
    import app.auth.router as module

    admin = user(role="admin")
    regular = user(role="consumer")

    assert await module.get_current_admin(admin) is admin
    with pytest.raises(HTTPException) as exc:
        await module.get_current_admin(regular)
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_paynow_refund_mock_and_live_failure(monkeypatch):
    import app.payment.paynow_client as module

    # Mock mode success.
    mock = module.PaynowClient()
    mock.mock_mode = True
    response = await mock.refund("ref", 10.0)
    assert response.success is True

    # Live mode without client → explicit failure.
    live = module.PaynowClient()
    live.mock_mode = False
    live._paynow = None
    response = await live.refund("ref", 10.0)
    assert response.success is False

    # Live mode with client but no refund endpoint → explicit failure.
    live._paynow = object()
    response = await live.refund("ref", 10.0)
    assert response.success is False


@pytest.mark.asyncio
async def test_refund_service_provider_failure(monkeypatch):
    import app.payment.service as module

    payment = SimpleNamespace(
        id="p1", order_id="o1", paynow_reference="ref", amount_usd=10.0,
        status=PaymentStatus.PAID, save=AsyncMock(),
    )
    class FakePayment:
        get = AsyncMock(return_value=payment)
    monkeypatch.setattr(module, "Payment", FakePayment)

    # Provider refund fails → status stays PAID.
    monkeypatch.setattr(
        module.paynow_client,
        "refund",
        AsyncMock(return_value=SimpleNamespace(success=False, error="nope")),
    )
    result = await module.PaymentService.refund_payment("p1")
    assert result is payment
    assert payment.status == PaymentStatus.PAID
    payment.save.assert_not_awaited()

    # Provider refund succeeds → REFUNDED.
    monkeypatch.setattr(
        module.paynow_client,
        "refund",
        AsyncMock(return_value=SimpleNamespace(success=True)),
    )
    result = await module.PaymentService.refund_payment("p1")
    assert result.status == PaymentStatus.REFUNDED
    payment.save.assert_awaited()


# ── Remaining coverage: promo/pickup/scheduled order paths ─────────


@pytest.mark.asyncio
async def test_promotion_service_find_promo_and_free_delivery_exception(monkeypatch):
    import app.catalog.promotion_service as module

    p = promo(code="FREE", promo_type="free_delivery")

    class FakePromotion:
        code = Field()
        find_one = AsyncMock(return_value=p)

    monkeypatch.setattr(module, "Promotion", FakePromotion)

    # Exercise the real _find_promo (not the patched helper).
    assert await module._find_promo("FREE") is p
    # is_free_delivery swallows lookup exceptions.
    FakePromotion.find_one = AsyncMock(side_effect=RuntimeError("db"))
    assert await module.is_free_delivery("FREE") is False
    # Empty code → False without lookup.
    assert await module.is_free_delivery("") is False


@pytest.mark.asyncio
async def test_order_service_promo_and_pickup_paths(monkeypatch):
    import app.catalog.promotion_service as promo_module
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
    monkeypatch.setattr(module.asyncio, "create_task", lambda coro: (coro.close(), MagicMock())[1])

    # Promo validation error → ValueError propagates.
    monkeypatch.setattr(
        promo_module,
        "validate_and_compute",
        AsyncMock(side_effect=promo_module.PromotionError("bad")),
    )
    with pytest.raises(ValueError, match="bad"):
        await module.OrderService.create_order(
            OrderCreate(
                merchant_id="m", consumer_id="c",
                items=[OrderItem(name="x", quantity=1, price=10)],
                total_amount=10,
                pickup=Location.from_lat_lng(-17.8, 31.0),
                dropoff=Location.from_lat_lng(-17.9, 31.1),
                promo_code="BAD",
            )
        )

    # Free-delivery promo → delivery_fee 0, discount recorded, no dispatch skip.
    monkeypatch.setattr(
        promo_module,
        "validate_and_compute",
        AsyncMock(return_value=(5.0, True)),
    )
    monkeypatch.setattr(promo_module, "record_redemption", AsyncMock())
    created = await module.OrderService.create_order(
        OrderCreate(
            merchant_id="m", consumer_id="c",
            items=[OrderItem(name="x", quantity=1, price=10)],
            total_amount=10,
            pickup=Location.from_lat_lng(-17.8, 31.0),
            dropoff=Location.from_lat_lng(-17.9, 31.1),
            promo_code="SAVE10",
        )
    )
    assert created.delivery_fee == 0.0
    assert created.discount_amount == 5.0
    promo_module.record_redemption.assert_awaited_once()

    # Self-pickup → delivery_fee 0 and no dispatch.
    dispatch_module.dispatch_service.dispatch_order.reset_mock()
    pickup = await module.OrderService.create_order(
        OrderCreate(
            merchant_id="m", consumer_id="c",
            items=[OrderItem(name="x", quantity=1, price=10)],
            total_amount=10, is_pickup=True,
            pickup=Location.from_lat_lng(-17.8, 31.0),
            dropoff=Location.from_lat_lng(-17.9, 31.1),
        )
    )
    assert pickup.delivery_fee == 0.0
    assert not dispatch_module.dispatch_service.dispatch_order.called

    # Scheduled in the future → no dispatch.
    from app.time_utils import utc_now
    scheduled = await module.OrderService.create_order(
        OrderCreate(
            merchant_id="m", consumer_id="c",
            items=[OrderItem(name="x", quantity=1, price=10)],
            total_amount=10,
            scheduled_at=utc_now() + timedelta(hours=1),
            pickup=Location.from_lat_lng(-17.8, 31.0),
            dropoff=Location.from_lat_lng(-17.9, 31.1),
        )
    )
    assert scheduled.scheduled_at is not None
    assert not dispatch_module.dispatch_service.dispatch_order.called


@pytest.mark.asyncio
async def test_chat_can_participate_restaurant_exception(monkeypatch):
    import app.chat.router as module
    import app.catalog.models as catalog_models

    order = SimpleNamespace(
        id="order-1", consumer_id="u1", driver_id="d1", merchant_id="r1"
    )

    class BrokenRestaurant:
        get = AsyncMock(side_effect=RuntimeError("db"))

    monkeypatch.setattr(catalog_models, "Restaurant", BrokenRestaurant)

    # Not consumer/driver and restaurant lookup fails → not a participant.
    assert await module._can_participate(order, user("stranger")) is False


@pytest.mark.asyncio
async def test_review_restaurant_aggregate_exception_swallowed(monkeypatch):
    import app.catalog.models as catalog_models
    import app.rating.router as module
    import app.rating.schemas as schemas

    order = SimpleNamespace(
        id="order-1", consumer_id="user-1", driver_id=None,
        merchant_id="restaurant-1", state=OrderState.DELIVERED,
    )
    class FakeOrder:
        get = AsyncMock(return_value=order)
    monkeypatch.setattr(module, "Order", FakeOrder)

    class FakeReview:
        order_id = Field()
        find_one = AsyncMock(return_value=None)

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "review-1"
            self.created_at = datetime.now()
            self.insert = AsyncMock()

    monkeypatch.setattr(module, "Review", FakeReview)

    class BrokenRestaurant:
        get = AsyncMock(side_effect=RuntimeError("db"))
    monkeypatch.setattr(catalog_models, "Restaurant", BrokenRestaurant)

    # Aggregate update fails but the review is still returned.
    created = await module.create_review(
        "order-1", schemas.ReviewCreate(restaurant_rating=5), user()
    )
    assert created.id == "review-1"


@pytest.mark.asyncio
async def test_refund_router_404_after_service_none(monkeypatch):
    import app.payment.router as module
    from app.payment.models import PaymentStatus as PS

    payment = SimpleNamespace(id="p1", consumer_id="user-1", status=PS.PAID)
    class FakePayment:
        get = AsyncMock(return_value=payment)
    monkeypatch.setattr(module, "Payment", FakePayment)
    monkeypatch.setattr(module.PaymentService, "refund_payment", AsyncMock(return_value=None))

    with pytest.raises(HTTPException) as exc:
        await module.refund_payment("p1", user(role="admin"))
    assert exc.value.status_code == 404
