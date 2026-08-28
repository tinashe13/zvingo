"""Chat streaming, driver rating aggregates, free-item promos, and auth guards."""

import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import HTTPException

from app.catalog.promotion_service import PromotionError, free_item_discount
from app.rating.service import fold_average
from app.time_utils import utc_now


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
    def __init__(self, pubsub):
        self._pubsub = pubsub
        self.closed = False
        self.close_error = None

    def pubsub(self):
        return self._pubsub

    async def close(self):
        if self.close_error:
            raise self.close_error
        self.closed = True


class Request:
    def __init__(self, disconnected=None, query_params=None, headers=None):
        self.disconnected = list(disconnected or [False])
        self.query_params = query_params or {}
        self.headers = headers or {}

    async def is_disconnected(self):
        if self.disconnected:
            return self.disconnected.pop(0)
        return True


class Query:
    def __init__(self, values=None):
        self.values = list(values or [])

    def sort(self, *args):
        return self

    async def to_list(self):
        return self.values


async def collect(response, limit=10):
    values = []
    async for item in response.body_iterator:
        values.append(item)
        if len(values) >= limit:
            break
    return values


def order(**overrides):
    values = {
        "id": "order-1",
        "consumer_id": "consumer-1",
        "driver_id": "driver-1",
        "merchant_id": "restaurant-1",
    }
    values.update(overrides)
    return SimpleNamespace(**values)


# ── chat SSE ────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_chat_stream_emits_connected_message_and_ping(monkeypatch):
    import app.chat.router as module

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "_can_participate", AsyncMock(return_value=True))
    pubsub = PubSub(get_messages=[{"type": "message", "data": '{"text":"hi"}'}, None])
    redis = Redis(pubsub)
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: redis)

    response = await module.stream_messages(
        Request([False, False, True]), "order-1", SimpleNamespace(id="consumer-1")
    )
    events = await collect(response)
    assert [e["event"] for e in events] == ["connected", "message", "ping"]
    assert pubsub.subscribed == ["chat_order-1"]
    assert redis.closed


@pytest.mark.asyncio
async def test_chat_stream_rejects_non_participants(monkeypatch):
    import app.chat.router as module

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.stream_messages(Request(), "missing", SimpleNamespace(id="u"))
    assert exc.value.status_code == 404

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "_can_participate", AsyncMock(return_value=False))
    with pytest.raises(HTTPException) as exc:
        await module.stream_messages(Request(), "order-1", SimpleNamespace(id="u"))
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_chat_stream_reports_errors_and_survives_cleanup_failures(monkeypatch):
    import app.chat.router as module

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "_can_participate", AsyncMock(return_value=True))

    pubsub = PubSub(get_messages=[RuntimeError("redis down")])
    pubsub.unsubscribe_error = RuntimeError("unsubscribe")
    redis = Redis(pubsub)
    redis.close_error = RuntimeError("close")
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: redis)

    events = await collect(
        await module.stream_messages(
            Request([False]), "order-1", SimpleNamespace(id="consumer-1")
        )
    )
    assert events[-1]["event"] == "error"

    pubsub = PubSub(get_messages=[asyncio.CancelledError()])
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: Redis(pubsub))
    events = await collect(
        await module.stream_messages(
            Request([False]), "order-1", SimpleNamespace(id="consumer-1")
        )
    )
    assert [e["event"] for e in events] == ["connected"]


@pytest.mark.asyncio
async def test_chat_stream_handles_a_redis_connection_failure(monkeypatch):
    import app.chat.router as module

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "_can_participate", AsyncMock(return_value=True))
    monkeypatch.setattr(
        module.aioredis, "from_url", MagicMock(side_effect=RuntimeError("no redis"))
    )
    events = await collect(
        await module.stream_messages(
            Request([False]), "order-1", SimpleNamespace(id="consumer-1")
        )
    )
    assert events[-1]["event"] == "error"


# ── rating aggregates ───────────────────────────────────────────────


def test_fold_average_starts_and_accumulates():
    assert fold_average(None, None, 5) == (5.0, 1)
    assert fold_average(4.0, 0, 5) == (5.0, 1)
    assert fold_average(4.0, 2, 5) == (4.33, 3)


@pytest.mark.asyncio
async def test_apply_rating_updates_documents(monkeypatch):
    import app.auth.models as auth_models
    import app.catalog.models as catalog_models
    from app.rating.service import apply_driver_rating, apply_restaurant_rating

    restaurant = SimpleNamespace(rating=4.0, review_count=1, save=AsyncMock())
    monkeypatch.setattr(
        catalog_models.Restaurant, "get", AsyncMock(return_value=restaurant)
    )
    await apply_restaurant_rating("restaurant-1", 5)
    assert restaurant.rating == 4.5 and restaurant.review_count == 2

    driver = SimpleNamespace(driver_rating=None, driver_review_count=0, save=AsyncMock())
    monkeypatch.setattr(auth_models.User, "get", AsyncMock(return_value=driver))
    await apply_driver_rating("driver-1", 4)
    assert driver.driver_rating == 4.0 and driver.driver_review_count == 1


@pytest.mark.asyncio
async def test_apply_rating_tolerates_missing_documents(monkeypatch):
    import app.auth.models as auth_models
    import app.catalog.models as catalog_models
    from app.rating.service import apply_driver_rating, apply_restaurant_rating

    monkeypatch.setattr(catalog_models.Restaurant, "get", AsyncMock(return_value=None))
    await apply_restaurant_rating("missing", 5)
    monkeypatch.setattr(
        catalog_models.Restaurant, "get", AsyncMock(side_effect=RuntimeError("db"))
    )
    await apply_restaurant_rating("broken", 5)

    monkeypatch.setattr(auth_models.User, "get", AsyncMock(return_value=None))
    await apply_driver_rating("missing", 5)
    monkeypatch.setattr(
        auth_models.User, "get", AsyncMock(side_effect=RuntimeError("db"))
    )
    await apply_driver_rating("broken", 5)


@pytest.mark.asyncio
async def test_driver_rating_summary(monkeypatch):
    import app.rating.router as module

    driver = SimpleNamespace(driver_rating=4.5, driver_review_count=2)
    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=driver))
    reviews = [
        SimpleNamespace(driver_rating=5),
        SimpleNamespace(driver_rating=4),
        SimpleNamespace(driver_rating=None),
    ]
    monkeypatch.setattr(module.Review, "find", lambda *a, **k: Query(reviews))
    monkeypatch.setattr(module.Review, "driver_id", MagicMock(), raising=False)

    summary = await module.driver_rating_summary("driver-1")
    assert summary["driver_rating"] == 4.5
    assert summary["rated_reviews"] == 2
    assert summary["breakdown"] == {"1": 0, "2": 0, "3": 0, "4": 1, "5": 1}

    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.driver_rating_summary("missing")
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_create_review_folds_both_aggregates(monkeypatch):
    import app.rating.router as module
    from app.order.state_machine import OrderState
    from app.rating.schemas import ReviewCreate

    reviewed_order = SimpleNamespace(
        consumer_id="consumer-1",
        state=OrderState.DELIVERED,
        merchant_id="restaurant-1",
        driver_id="driver-1",
    )
    class FakeReview:
        order_id = MagicMock()
        find_one = AsyncMock(return_value=None)

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "review-1"
            self.created_at = utc_now()
            self.insert = AsyncMock()

    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=reviewed_order)))
    monkeypatch.setattr(module, "Review", FakeReview)
    restaurant_rating = AsyncMock()
    driver_rating = AsyncMock()
    monkeypatch.setattr(module, "apply_restaurant_rating", restaurant_rating)
    monkeypatch.setattr(module, "apply_driver_rating", driver_rating)

    await module.create_review(
        "order-1",
        ReviewCreate(restaurant_rating=5, driver_rating=4),
        SimpleNamespace(id="consumer-1"),
    )
    restaurant_rating.assert_awaited_once_with("restaurant-1", 5)
    driver_rating.assert_awaited_once_with("driver-1", 4)

    # No driver rating submitted — only the restaurant aggregate moves.
    driver_rating.reset_mock()
    await module.create_review(
        "order-1", ReviewCreate(restaurant_rating=3), SimpleNamespace(id="consumer-1")
    )
    driver_rating.assert_not_awaited()


# ── free_item promotions ────────────────────────────────────────────


def promo(**overrides):
    values = {
        "promo_type": "free_item",
        "free_item_id": None,
        "free_item_name": "Fries",
        "max_discount_usd": None,
        "redemptions_by_user": {},
        "redeemed_by": [],
        "max_uses_per_user": 1,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def test_free_item_discount_matches_by_name_and_id():
    items = [
        {"name": "Burger", "price": 10.0},
        {"name": "fries", "price": 3.5},
        {"name": "Fries", "price": 4.0},
    ]
    # Cheapest matching line wins — one free item, not one per line.
    assert free_item_discount(promo(), items) == 3.5

    by_id = promo(free_item_id="menu-1", free_item_name=None)
    assert free_item_discount(by_id, [{"id": "menu-1", "price": 6.0}]) == 6.0
    assert (
        free_item_discount(by_id, [SimpleNamespace(menu_item_id="menu-1", price=7.0)])
        == 7.0
    )


def test_free_item_discount_errors_are_actionable():
    with pytest.raises(PromotionError) as exc:
        free_item_discount(promo(free_item_name=None), [{"name": "Burger"}])
    assert "not configured" in str(exc.value)

    with pytest.raises(PromotionError) as exc:
        free_item_discount(promo(), [{"name": "Burger", "price": 10.0}])
    assert "Add Fries" in str(exc.value)

    with pytest.raises(PromotionError) as exc:
        free_item_discount(promo(free_item_id="menu-9", free_item_name=None), [])
    assert "qualifying item" in str(exc.value)


@pytest.mark.asyncio
async def test_compute_discount_handles_free_item_and_caps(monkeypatch):
    import app.catalog.promotion_service as module

    free_item = promo(
        code="FREEFRIES",
        is_active=True,
        starts_at=None,
        ends_at=None,
        min_order_usd=0.0,
        max_uses=None,
        current_uses=0,
        discount_value=0.0,
    )
    monkeypatch.setattr(module, "_find_promo", AsyncMock(return_value=free_item))

    discount = await module.compute_discount(
        "FREEFRIES", "consumer-1", 20.0, [{"name": "Fries", "price": 4.0}]
    )
    assert discount == 4.0

    # A discount can never exceed the order it is applied to.
    assert (
        await module.compute_discount(
            "FREEFRIES", "consumer-1", 2.0, [{"name": "Fries", "price": 4.0}]
        )
        == 2.0
    )


@pytest.mark.asyncio
async def test_per_user_limit_counts_redemptions(monkeypatch):
    import app.catalog.promotion_service as module

    twice = promo(
        code="TWICE",
        promo_type="flat",
        discount_value=2.0,
        is_active=True,
        starts_at=None,
        ends_at=None,
        min_order_usd=0.0,
        max_uses=None,
        current_uses=0,
        max_uses_per_user=2,
        redemptions_by_user={"consumer-1": 1},
        save=AsyncMock(),
    )
    monkeypatch.setattr(module, "_find_promo", AsyncMock(return_value=twice))

    # One use so far, limit two — still allowed.
    assert await module.compute_discount("TWICE", "consumer-1", 20.0) == 2.0

    twice.redemptions_by_user = {"consumer-1": 2}
    with pytest.raises(PromotionError) as exc:
        await module.compute_discount("TWICE", "consumer-1", 20.0)
    assert "already used" in str(exc.value)

    # A legacy promo with no per-user counts still reads as one use.
    legacy = promo(
        code="OLD",
        promo_type="flat",
        discount_value=1.0,
        is_active=True,
        starts_at=None,
        ends_at=None,
        min_order_usd=0.0,
        max_uses=None,
        current_uses=0,
        redemptions_by_user={},
        redeemed_by=["consumer-1"],
    )
    monkeypatch.setattr(module, "_find_promo", AsyncMock(return_value=legacy))
    with pytest.raises(PromotionError):
        await module.compute_discount("OLD", "consumer-1", 20.0)


@pytest.mark.asyncio
async def test_record_redemption_increments_per_user_counts(monkeypatch):
    import app.catalog.promotion_service as module

    target = promo(
        code="SAVE", current_uses=1, redeemed_by=["consumer-1"], redemptions_by_user={},
        save=AsyncMock(),
    )
    monkeypatch.setattr(module, "_find_promo", AsyncMock(return_value=target))

    await module.record_redemption("SAVE", "consumer-1")
    # The legacy `redeemed_by` entry counted as one, so this is the second.
    assert target.redemptions_by_user == {"consumer-1": 2}
    assert target.current_uses == 2
    assert target.redeemed_by == ["consumer-1"]

    await module.record_redemption("SAVE", "consumer-2")
    assert target.redemptions_by_user["consumer-2"] == 1
    assert "consumer-2" in target.redeemed_by


def test_item_field_reads_dicts_and_models():
    from app.catalog.promotion_service import _item_field

    assert _item_field({"name": "Fries"}, "name") == "Fries"
    assert _item_field(SimpleNamespace(name="Fries"), "name") == "Fries"
    assert _item_field({}, "name", "fallback") == "fallback"


# ── promo type validation in the catalog router ─────────────────────


@pytest.mark.asyncio
async def test_create_promotion_validates_type(monkeypatch):
    import app.catalog.router as module

    merchant = SimpleNamespace(id="merchant-1", role="merchant")

    with pytest.raises(HTTPException) as exc:
        await module.create_promotion(
            module.PromotionCreate(title="T", subtitle="S", promo_type="bogus"), merchant
        )
    assert exc.value.status_code == 400

    with pytest.raises(HTTPException) as exc:
        await module.create_promotion(
            module.PromotionCreate(title="T", subtitle="S", promo_type="free_item"),
            merchant,
        )
    assert "free_item_id or free_item_name" in exc.value.detail

    class FakePromotion:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.insert = AsyncMock()

    monkeypatch.setattr(module, "Promotion", FakePromotion)
    promo_doc = await module.create_promotion(
        module.PromotionCreate(
            title="T", subtitle="S", promo_type="free_item", free_item_name="Fries"
        ),
        merchant,
    )
    assert promo_doc.free_item_name == "Fries"


@pytest.mark.asyncio
async def test_update_promotion_validates_type(monkeypatch):
    import app.catalog.router as module

    existing = SimpleNamespace(merchant_id="merchant-1", save=AsyncMock())
    monkeypatch.setattr(
        module, "Promotion", SimpleNamespace(get=AsyncMock(return_value=existing))
    )
    merchant = SimpleNamespace(id="merchant-1", role="merchant")

    with pytest.raises(HTTPException) as exc:
        await module.update_promotion(
            "promo-1", module.PromotionUpdate(promo_type="bogus"), merchant
        )
    assert exc.value.status_code == 400

    await module.update_promotion(
        "promo-1", module.PromotionUpdate(promo_type="free_delivery"), merchant
    )
    assert existing.promo_type == "free_delivery"


@pytest.mark.asyncio
async def test_validate_promo_endpoint_passes_the_cart(monkeypatch):
    import app.catalog.router as module
    import app.catalog.promotion_service as promo_service

    validate = AsyncMock(return_value=(4.0, False))
    monkeypatch.setattr(promo_service, "validate_and_compute", validate)

    result = await module.validate_promo_code(
        module.PromoValidateRequest(
            code="FREEFRIES",
            order_subtotal_usd=20.0,
            items=[{"name": "Fries", "price": 4.0}],
        ),
        SimpleNamespace(id="consumer-1"),
    )
    assert result["discount_usd"] == 4.0
    assert validate.await_args.args[3] == [{"name": "Fries", "price": 4.0}]


# ── auth guards ─────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_deactivated_accounts_cannot_authenticate(monkeypatch):
    import app.auth.router as module
    from app.auth.service import AuthService

    inactive = SimpleNamespace(id="user-1", is_active=False)
    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=inactive))
    token = AuthService.create_access_token({"sub": "user-1"})

    with pytest.raises(HTTPException) as exc:
        await module.get_current_user(token)
    assert exc.value.status_code == 403
    assert exc.value.detail == module.INACTIVE_ACCOUNT_DETAIL


@pytest.mark.asyncio
async def test_login_refuses_a_deactivated_account(monkeypatch):
    import app.auth.router as module

    monkeypatch.setattr(
        module.AuthService,
        "authenticate_user",
        AsyncMock(return_value=SimpleNamespace(id="user-1", is_active=False)),
    )
    form = SimpleNamespace(username="user@example.com", password="password")
    with pytest.raises(HTTPException) as exc:
        await module.login_for_access_token(form)
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_flexible_auth_accepts_query_param_or_header(monkeypatch):
    import app.auth.router as module
    from app.auth.service import AuthService

    active = SimpleNamespace(id="user-1", is_active=True)
    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=active))
    token = AuthService.create_access_token({"sub": "user-1"})

    assert await module.get_current_user_flexible(Request(query_params={"token": token})) is active
    assert (
        await module.get_current_user_flexible(
            Request(headers={"authorization": f"Bearer {token}"})
        )
        is active
    )

    with pytest.raises(HTTPException) as exc:
        await module.get_current_user_flexible(Request(headers={"authorization": "Basic x"}))
    assert exc.value.status_code == 401
