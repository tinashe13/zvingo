"""Promotions: discount maths, restaurant scoping, caps, and atomic redemption."""

import asyncio
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

import app.catalog.promotion_service as promo_service
from app.catalog.promotion_service import PromotionError
from app.time_utils import utc_now


def promo(**overrides):
    values = {
        "id": "promo-1",
        "promo_id": "p1",
        "merchant_id": "merchant-1",
        "restaurant_id": None,
        "title": "Deal",
        "subtitle": "Save",
        "code": "SAVE",
        "promo_type": "percentage",
        "discount_value": 20.0,
        "min_order_usd": 0.0,
        "max_discount_usd": None,
        "free_item_id": None,
        "free_item_name": None,
        "starts_at": utc_now() - timedelta(days=1),
        "ends_at": None,
        "is_active": True,
        "max_uses": None,
        "max_uses_per_user": 1,
        "current_uses": 0,
        "redeemed_by": [],
        "redemptions_by_user": {},
        "first_order_only": False,
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def use(monkeypatch, target):
    monkeypatch.setattr(promo_service, "_find_promo", AsyncMock(return_value=target))
    return target


async def discount(code="SAVE", consumer="consumer-1", subtotal=50.0, **kwargs):
    return await promo_service.compute_discount(code, consumer, subtotal, **kwargs)


# ── Discount maths, per promo type ──────────────────────────────────


@pytest.mark.asyncio
async def test_percentage_discount(monkeypatch):
    use(monkeypatch, promo(promo_type="percentage", discount_value=20))
    assert await discount(subtotal=50.0) == 10.0


@pytest.mark.asyncio
async def test_percentage_is_capped_by_max_discount(monkeypatch):
    use(
        monkeypatch,
        promo(promo_type="percentage", discount_value=50, max_discount_usd=8.0),
    )
    assert await discount(subtotal=100.0) == 8.0


@pytest.mark.asyncio
async def test_percentage_over_one_hundred_cannot_pay_the_consumer(monkeypatch):
    """A fat-fingered 500% promo must not produce a negative order total."""
    use(monkeypatch, promo(promo_type="percentage", discount_value=500))
    assert await discount(subtotal=40.0) == 40.0


@pytest.mark.asyncio
async def test_flat_discount_never_exceeds_the_order(monkeypatch):
    use(monkeypatch, promo(promo_type="flat", discount_value=25.0))
    assert await discount(subtotal=100.0) == 25.0
    assert await discount(subtotal=10.0) == 10.0


@pytest.mark.asyncio
async def test_negative_flat_discount_is_clamped(monkeypatch):
    use(monkeypatch, promo(promo_type="flat", discount_value=-10.0))
    assert await discount(subtotal=50.0) == 0.0


@pytest.mark.asyncio
async def test_free_delivery_discounts_nothing_but_flags_the_waiver(monkeypatch):
    use(monkeypatch, promo(promo_type="free_delivery", discount_value=0))
    amount, free = await promo_service.validate_and_compute("SAVE", "consumer-1", 50.0)
    assert amount == 0.0
    assert free is True


@pytest.mark.asyncio
async def test_expired_free_delivery_does_not_waive_the_fee(monkeypatch):
    """`is_free_delivery` must apply the same lifecycle checks as the discount."""
    use(
        monkeypatch,
        promo(promo_type="free_delivery", ends_at=utc_now() - timedelta(days=1)),
    )
    assert await promo_service.is_free_delivery("SAVE") is False
    assert await promo_service.is_free_delivery("") is False


@pytest.mark.asyncio
async def test_free_item_requires_the_item_in_the_cart(monkeypatch):
    use(monkeypatch, promo(promo_type="free_item", free_item_name="Fries"))
    assert await discount(items=[{"name": "Fries", "price": 3.5}]) == 3.5
    with pytest.raises(PromotionError, match="Add Fries"):
        await discount(items=[{"name": "Burger", "price": 9.0}])


@pytest.mark.asyncio
async def test_unknown_promo_type_fails_safe(monkeypatch):
    use(monkeypatch, promo(promo_type="mystery"))
    with pytest.raises(PromotionError, match="Unsupported"):
        await discount()


# ── Minimum spend and lifecycle ─────────────────────────────────────


@pytest.mark.asyncio
async def test_minimum_spend_is_enforced(monkeypatch):
    use(monkeypatch, promo(min_order_usd=25.0))
    with pytest.raises(PromotionError, match=r"\$25.00"):
        await discount(subtotal=24.99)
    assert await discount(subtotal=25.0) == 5.0


@pytest.mark.asyncio
async def test_missing_inactive_and_out_of_window_codes_are_rejected(monkeypatch):
    with pytest.raises(PromotionError, match="required"):
        await discount(code="")

    use(monkeypatch, None)
    with pytest.raises(PromotionError, match="Invalid"):
        await discount()

    use(monkeypatch, promo(is_active=False))
    with pytest.raises(PromotionError, match="no longer active"):
        await discount()

    use(monkeypatch, promo(starts_at=utc_now() + timedelta(days=1)))
    with pytest.raises(PromotionError, match="not active yet"):
        await discount()

    use(monkeypatch, promo(ends_at=utc_now() - timedelta(minutes=1)))
    with pytest.raises(PromotionError, match="expired"):
        await discount()


# ── Restaurant scoping ──────────────────────────────────────────────


@pytest.mark.asyncio
async def test_scoped_promo_only_applies_at_its_own_restaurant(monkeypatch):
    use(monkeypatch, promo(restaurant_id="restaurant-1"))

    assert await discount(restaurant_id="restaurant-1") == 10.0

    with pytest.raises(PromotionError, match="not valid for this restaurant"):
        await discount(restaurant_id="restaurant-2")


@pytest.mark.asyncio
async def test_scoped_promo_fails_closed_when_the_restaurant_is_unknown(monkeypatch):
    """No resolvable restaurant must reject, not silently skip the scope check."""
    use(monkeypatch, promo(restaurant_id="restaurant-1"))
    with pytest.raises(PromotionError, match="not valid for this restaurant"):
        await discount(restaurant_id=None)


@pytest.mark.asyncio
async def test_unscoped_promo_works_anywhere(monkeypatch):
    use(monkeypatch, promo(restaurant_id=None))
    assert await discount(restaurant_id="restaurant-9") == 10.0


@pytest.mark.asyncio
async def test_resolve_restaurant_id_accepts_either_id_and_fails_closed(monkeypatch):
    import app.catalog.models as catalog_models

    shop = SimpleNamespace(id="restaurant-doc-1")

    class FakeRestaurant:
        merchant_id = SimpleNamespace(__eq__=lambda self, other: ("eq", other))
        get = AsyncMock(return_value=shop)
        find_one = AsyncMock(return_value=None)

    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    assert await promo_service.resolve_restaurant_id("restaurant-doc-1") == "restaurant-doc-1"

    FakeRestaurant.get = AsyncMock(return_value=None)
    FakeRestaurant.find_one = AsyncMock(return_value=shop)
    assert await promo_service.resolve_restaurant_id("merchant-1") == "restaurant-doc-1"

    FakeRestaurant.get = AsyncMock(side_effect=ValueError("bad id"))
    assert await promo_service.resolve_restaurant_id("garbage") is None
    assert await promo_service.resolve_restaurant_id(None) is None


# ── Usage limits ────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_global_cap_stops_further_redemption(monkeypatch):
    use(monkeypatch, promo(max_uses=100, current_uses=100))
    with pytest.raises(PromotionError, match="usage limit"):
        await discount()


@pytest.mark.asyncio
async def test_per_user_cap_counts_this_consumer_only(monkeypatch):
    use(
        monkeypatch,
        promo(max_uses_per_user=2, redemptions_by_user={"consumer-1": 2}),
    )
    with pytest.raises(PromotionError, match="already used"):
        await discount(consumer="consumer-1")
    assert await discount(consumer="consumer-2") == 10.0


@pytest.mark.asyncio
async def test_legacy_redeemed_by_still_counts_as_one_use(monkeypatch):
    use(monkeypatch, promo(redemptions_by_user={}, redeemed_by=["consumer-1"]))
    with pytest.raises(PromotionError, match="already used"):
        await discount(consumer="consumer-1")


# ── First-order promos ──────────────────────────────────────────────


@pytest.mark.asyncio
async def test_first_order_promo_rejects_a_returning_consumer(monkeypatch):
    use(monkeypatch, promo(first_order_only=True))
    monkeypatch.setattr(
        promo_service, "_has_previous_order", AsyncMock(return_value=True)
    )
    with pytest.raises(PromotionError, match="first orders only"):
        await discount()


@pytest.mark.asyncio
async def test_first_order_promo_accepts_a_new_consumer(monkeypatch):
    use(monkeypatch, promo(first_order_only=True))
    monkeypatch.setattr(
        promo_service, "_has_previous_order", AsyncMock(return_value=False)
    )
    assert await discount() == 10.0


@pytest.mark.asyncio
async def test_first_order_check_fails_closed_when_orders_cannot_be_read():
    """An unreadable order history must not hand out an acquisition promo."""
    assert await promo_service._has_previous_order("consumer-1") is True


# ── Atomic redemption ───────────────────────────────────────────────


class FakeCollection:
    """A collection double that enforces the promo's caps like MongoDB would."""

    def __init__(self, max_uses=None, max_uses_per_user=1):
        self.document = {
            "code": "SAVE",
            "is_active": True,
            "current_uses": 0,
            "max_uses": max_uses,
            "max_uses_per_user": max_uses_per_user,
            "redemptions_by_user": {},
            "redeemed_by": [],
        }
        self.lock = asyncio.Lock()

    def _matches(self, consumer_id):
        doc = self.document
        if not doc["is_active"]:
            return False
        if doc["max_uses"] is not None and doc["current_uses"] >= doc["max_uses"]:
            return False
        used = max(
            doc["redemptions_by_user"].get(consumer_id, 0),
            1 if consumer_id in doc["redeemed_by"] else 0,
        )
        return used < max(doc["max_uses_per_user"], 1)

    async def find_one_and_update(self, filter_doc, update):
        consumer_id = next(
            key.split(".", 1)[1]
            for key in update["$inc"]
            if key.startswith("redemptions_by_user.")
        )
        # The lock stands in for MongoDB's single-document atomicity.
        async with self.lock:
            await asyncio.sleep(0)  # yield, so a racing caller interleaves here
            if not self._matches(consumer_id):
                return None
            self.document["current_uses"] += 1
            counts = self.document["redemptions_by_user"]
            counts[consumer_id] = counts.get(consumer_id, 0) + 1
            if consumer_id not in self.document["redeemed_by"]:
                self.document["redeemed_by"].append(consumer_id)
            return dict(self.document)

    async def update_one(self, filter_doc, update):
        self.document["current_uses"] += update["$inc"]["current_uses"]


@pytest.mark.asyncio
async def test_a_limited_promo_cannot_be_over_redeemed_under_concurrency(monkeypatch):
    """Ten simultaneous checkouts, three uses left: exactly three may win."""
    collection = FakeCollection(max_uses=3, max_uses_per_user=1)
    monkeypatch.setattr(promo_service, "_promotion_collection", lambda: collection)

    results = await asyncio.gather(
        *[
            promo_service.record_redemption("SAVE", f"consumer-{i}")
            for i in range(10)
        ]
    )
    assert sum(results) == 3
    assert collection.document["current_uses"] == 3


@pytest.mark.asyncio
async def test_per_user_cap_holds_under_concurrency(monkeypatch):
    """One consumer firing five checkouts at once still redeems once."""
    collection = FakeCollection(max_uses=None, max_uses_per_user=1)
    monkeypatch.setattr(promo_service, "_promotion_collection", lambda: collection)

    results = await asyncio.gather(
        *[promo_service.record_redemption("SAVE", "consumer-1") for _ in range(5)]
    )
    assert sum(results) == 1
    assert collection.document["redemptions_by_user"] == {"consumer-1": 1}


@pytest.mark.asyncio
async def test_release_returns_a_claimed_redemption(monkeypatch):
    collection = FakeCollection()
    monkeypatch.setattr(promo_service, "_promotion_collection", lambda: collection)

    await promo_service.record_redemption("SAVE", "consumer-1")
    assert collection.document["current_uses"] == 1
    await promo_service.release_redemption("SAVE", "consumer-1")
    assert collection.document["current_uses"] == 0

    # No collection is a no-op, never a crash.
    monkeypatch.setattr(promo_service, "_promotion_collection", lambda: None)
    await promo_service.release_redemption("SAVE", "consumer-1")


# ── Merchant CRUD ownership ─────────────────────────────────────────


def merchant(id="merchant-1"):
    return SimpleNamespace(id=id, role="merchant")


@pytest.mark.asyncio
async def test_a_merchant_cannot_scope_a_promo_to_someone_elses_restaurant(monkeypatch):
    """Otherwise a merchant could burn a competitor's margin."""
    import app.catalog.router as module

    rival = SimpleNamespace(id="restaurant-9", merchant_id="merchant-2")
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=rival))

    payload = module.PromotionCreate(
        title="Deal", subtitle="Save", restaurant_id="restaurant-9"
    )
    with pytest.raises(HTTPException) as exc:
        await module.create_promotion(payload, merchant())
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_a_merchant_cannot_rescope_a_promo_onto_another_restaurant(monkeypatch):
    import app.catalog.router as module

    existing = SimpleNamespace(
        merchant_id="merchant-1", restaurant_id=None, save=AsyncMock()
    )
    rival = SimpleNamespace(id="restaurant-9", merchant_id="merchant-2")
    monkeypatch.setattr(module.Promotion, "get", AsyncMock(return_value=existing))
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=rival))

    with pytest.raises(HTTPException) as exc:
        await module.update_promotion(
            "promo-1", module.PromotionUpdate(restaurant_id="restaurant-9"), merchant()
        )
    assert exc.value.status_code == 403
    existing.save.assert_not_awaited()


@pytest.mark.asyncio
async def test_a_missing_restaurant_scope_is_refused(monkeypatch):
    import app.catalog.router as module

    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.create_promotion(
            module.PromotionCreate(title="D", subtitle="S", restaurant_id="nope"),
            merchant(),
        )
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_owning_merchant_may_scope_to_their_own_restaurant(monkeypatch):
    import app.catalog.router as module

    mine = SimpleNamespace(id="restaurant-1", merchant_id="merchant-1")
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=mine))

    created = []

    class FakePromotion:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "promo-new"
            self.insert = AsyncMock(side_effect=lambda: created.append(self))

    monkeypatch.setattr(module, "Promotion", FakePromotion)
    promo_out = await module.create_promotion(
        module.PromotionCreate(
            title="Deal", subtitle="Save", restaurant_id="restaurant-1",
            first_order_only=True,
        ),
        merchant(),
    )
    assert promo_out.restaurant_id == "restaurant-1"
    assert promo_out.first_order_only is True
    assert created


@pytest.mark.asyncio
async def test_promotion_listing_is_paginated_and_drops_exhausted_promos(monkeypatch):
    import app.catalog.router as module

    promos = [SimpleNamespace(max_uses=None, current_uses=0) for _ in range(30)]
    promos.append(SimpleNamespace(max_uses=1, current_uses=1))  # exhausted

    class FakeQuery:
        def __init__(self, values):
            self.values = values
            self.limit_value = None

        def sort(self, *a):
            return self

        def skip(self, value):
            return self

        def limit(self, value):
            self.limit_value = value
            return self

        async def to_list(self):
            return self.values

    query = FakeQuery(promos)
    monkeypatch.setattr(module, "Promotion", SimpleNamespace(find=lambda *a: query))

    page = await module.list_active_promotions(limit=10)
    assert len(page) == 10
    assert query.limit_value is not None
    assert all(p.max_uses is None or p.current_uses < p.max_uses for p in page)


@pytest.mark.asyncio
async def test_validate_endpoint_surfaces_promo_errors_as_400(monkeypatch):
    import app.catalog.router as module

    monkeypatch.setattr(
        promo_service,
        "validate_and_compute",
        AsyncMock(side_effect=PromotionError("This promo code has expired")),
    )
    monkeypatch.setattr(
        promo_service, "resolve_restaurant_id", AsyncMock(return_value=None)
    )

    request = module.PromoValidateRequest(code="OLD", order_subtotal_usd=20.0)
    with pytest.raises(HTTPException) as exc:
        await module.validate_promo_code(request, SimpleNamespace(id="consumer-1"))
    assert exc.value.status_code == 400
    assert "expired" in exc.value.detail


@pytest.mark.asyncio
async def test_a_promo_code_cannot_be_reused_by_another_promotion(monkeypatch):
    """The code is the redemption key — two promos sharing one is a mispricing."""
    import app.catalog.router as module

    taken = SimpleNamespace(id="promo-existing", merchant_id="merchant-1")
    monkeypatch.setattr(module.Promotion, "find_one", AsyncMock(return_value=taken))

    with pytest.raises(HTTPException) as exc:
        await module.create_promotion(
            module.PromotionCreate(title="D", subtitle="S", code="SAVE10"), merchant()
        )
    assert exc.value.status_code == 409

    # Re-saving the *same* promotion under its own code is fine.
    monkeypatch.setattr(module.Promotion, "get", AsyncMock(return_value=SimpleNamespace(
        id="promo-existing", merchant_id="merchant-1", save=AsyncMock()
    )))
    updated = await module.update_promotion(
        "promo-existing", module.PromotionUpdate(code="SAVE10"), merchant()
    )
    assert updated.code == "SAVE10"
