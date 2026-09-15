"""Promotion validation and redemption.

Two separate concerns live here:

* **Validation** (`compute_discount`) is a pure read — it answers "what would
  this code be worth?" and is safe to call from a cart preview.
* **Redemption** (`record_redemption`) is a *claim*. It runs as a single
  conditional MongoDB `findAndModify`, so two concurrent checkouts racing for
  the last use of a limited promo cannot both win. Read-modify-write would
  happily hand out the same last redemption twice.

Kept out of the catalog router so order creation can reuse it without a
circular import.
"""

import structlog
from typing import Any, Iterable, Optional, Sequence, Tuple

from app.time_utils import utc_now
from app.catalog.promotion_models import Promotion

logger = structlog.get_logger()

SUPPORTED_PROMO_TYPES = ("percentage", "flat", "free_delivery", "free_item")


class PromotionError(Exception):
    """Raised when a promo code is invalid, expired, or not applicable."""


async def _find_promo(code: str) -> Optional[Promotion]:
    return await Promotion.find_one(Promotion.code == code)


def _promotion_collection():
    """The raw promotions collection, or None when Beanie is not initialised.

    Returning None (instead of raising) keeps unit tests and any caller running
    before `init_db` on the slower, non-atomic path rather than crashing.
    """
    try:
        return Promotion.get_pymongo_collection()
    except Exception:  # pragma: no cover - only hit before init_beanie
        return None


async def resolve_restaurant_id(merchant_id: Optional[str]) -> Optional[str]:
    """Resolve a client-supplied merchant_id to the restaurant's document id.

    Orders and checkout baskets carry `merchant_id`, which callers may set to
    either a Restaurant document id or a Restaurant.merchant_id — resolve both
    the same way order creation does, so it compares like ids against
    `Promotion.restaurant_id`. Returns None (not raises) on a bad id or a
    lookup failure, so a scoped promo fails closed rather than crashing.
    """
    if not merchant_id:
        return None
    from app.catalog.models import Restaurant

    try:
        restaurant = await Restaurant.get(merchant_id)
        if restaurant is None:
            restaurant = await Restaurant.find_one(Restaurant.merchant_id == merchant_id)
        return str(restaurant.id) if restaurant else None
    except Exception:
        return None


def _item_field(item: Any, field: str, default=None):
    """Read a field from an order item that may be a model or a plain dict."""
    if isinstance(item, dict):
        return item.get(field, default)
    return getattr(item, field, default)


def _uses_by(promo: Promotion, consumer_id: str) -> int:
    """How many times this consumer has redeemed the promo.

    Falls back to `redeemed_by` for promotions created before per-user counts
    were tracked, so legacy single-use codes stay single-use.
    """
    counts = promo.redemptions_by_user or {}
    if consumer_id in counts:
        return counts[consumer_id]
    return 1 if consumer_id in (promo.redeemed_by or []) else 0


async def _has_previous_order(consumer_id: str) -> bool:
    """True when this consumer has placed an order before.

    Used by `first_order_only` promos. A lookup failure fails *closed* (treated
    as "has ordered"), so an acquisition promo is never handed to a repeat
    customer because the database blinked.
    """
    try:
        from app.order.models import Order

        return await Order.find(Order.consumer_id == consumer_id).count() > 0
    except Exception as e:
        logger.warning(
            "First-order check failed; rejecting promo", consumer_id=consumer_id, error=str(e)
        )
        return True


def free_item_discount(promo: Promotion, items: Sequence[Any]) -> float:
    """Unit price of the cheapest cart line that matches the promo's free item.

    Raises PromotionError when the qualifying item is not in the cart, so the
    consumer gets an actionable message rather than a silent $0 discount.
    """
    target_id = promo.free_item_id
    target_name = (promo.free_item_name or "").strip().lower()
    if not target_id and not target_name:
        raise PromotionError("This promo code is not configured correctly")

    matches = []
    for item in items or []:
        item_id = _item_field(item, "id") or _item_field(item, "menu_item_id")
        name = str(_item_field(item, "name", "") or "").strip().lower()
        if (target_id and item_id == target_id) or (target_name and name == target_name):
            matches.append(float(_item_field(item, "price", 0.0) or 0.0))

    if not matches:
        label = promo.free_item_name or "the qualifying item"
        raise PromotionError(f"Add {label} to your order to use this promo code")

    # One free item, not one per line: discount the cheapest match.
    return round(min(matches), 2)


async def compute_discount(
    code: str,
    consumer_id: str,
    order_subtotal_usd: float,
    items: Optional[Iterable[Any]] = None,
    restaurant_id: Optional[str] = None,
) -> float:
    """Validate a promo code and return the discount in USD.

    Raises PromotionError with a user-facing message when the code cannot be
    applied. Does NOT mutate state; call ``record_redemption`` after the order
    is successfully created.

    Rules, in the order they are checked:

    1. the code exists and is active
    2. it is scoped to this restaurant (or to no restaurant at all)
    3. `starts_at` <= now <= `ends_at`
    4. the cart meets `min_order_usd`
    5. the global `max_uses` cap has room
    6. this consumer is under `max_uses_per_user`
    7. `first_order_only` promos require a consumer with no prior orders

    `restaurant_id` is the resolved Restaurant document id the order is
    actually being placed against (see `resolve_restaurant_id`). When the
    promo is scoped to a specific restaurant, redemption against any other
    restaurant — or with no restaurant id available at all — is rejected.
    """
    if not code:
        raise PromotionError("Promo code is required")

    promo = await _find_promo(code)
    if not promo:
        raise PromotionError("Invalid promo code")
    if not promo.is_active:
        raise PromotionError("This promo code is no longer active")
    if promo.restaurant_id and promo.restaurant_id != restaurant_id:
        raise PromotionError("This promo code is not valid for this restaurant")

    now = utc_now()
    if promo.starts_at and now < promo.starts_at:
        raise PromotionError("This promo code is not active yet")
    if promo.ends_at and now > promo.ends_at:
        raise PromotionError("This promo code has expired")

    if order_subtotal_usd < promo.min_order_usd:
        raise PromotionError(
            f"Minimum order of ${promo.min_order_usd:.2f} required"
        )

    if promo.max_uses is not None and promo.current_uses >= promo.max_uses:
        raise PromotionError("This promo code has reached its usage limit")

    if _uses_by(promo, consumer_id) >= max(promo.max_uses_per_user, 1):
        raise PromotionError("You have already used this promo code")

    if getattr(promo, "first_order_only", False) and await _has_previous_order(
        consumer_id
    ):
        raise PromotionError("This promo code is for first orders only")

    if promo.promo_type == "percentage":
        percent = max(0.0, min(float(promo.discount_value), 100.0))
        discount = round(order_subtotal_usd * (percent / 100.0), 2)
    elif promo.promo_type == "flat":
        discount = round(max(0.0, promo.discount_value), 2)
    elif promo.promo_type == "free_delivery":
        # Free delivery is applied to the delivery fee by the caller; here we
        # return 0 and let the caller handle the fee waiver via is_free_delivery.
        discount = 0.0
    elif promo.promo_type == "free_item":
        discount = free_item_discount(promo, list(items or []))
    else:
        # Unknown type — fail safe.
        raise PromotionError("Unsupported promo type")

    if promo.max_discount_usd is not None:
        discount = min(discount, promo.max_discount_usd)

    # Never discount more than the order is worth.
    discount = min(discount, round(order_subtotal_usd, 2))

    return max(0.0, round(discount, 2))


def _claim_filter(code: str, consumer_id: str) -> dict:
    """Mongo filter that only matches a promo which still has room to redeem.

    Both caps are expressed as `$expr` comparisons against the document's own
    fields, so the check and the increment happen in one atomic operation.
    """
    user_key = f"$redemptions_by_user.{consumer_id}"
    return {
        "code": code,
        "is_active": True,
        "$expr": {
            "$and": [
                {
                    "$or": [
                        {"$eq": [{"$ifNull": ["$max_uses", None]}, None]},
                        {"$lt": ["$current_uses", "$max_uses"]},
                    ]
                },
                {
                    "$lt": [
                        {
                            "$max": [
                                {"$ifNull": [user_key, 0]},
                                {
                                    "$cond": [
                                        {
                                            "$in": [
                                                consumer_id,
                                                {"$ifNull": ["$redeemed_by", []]},
                                            ]
                                        },
                                        1,
                                        0,
                                    ]
                                },
                            ]
                        },
                        {"$max": [{"$ifNull": ["$max_uses_per_user", 1]}, 1]},
                    ]
                },
            ]
        },
    }


async def record_redemption(code: str, consumer_id: str) -> bool:
    """Atomically claim one redemption of `code` for `consumer_id`.

    Returns True when the claim succeeded. False means the promo ran out (or
    this consumer hit their per-user cap) between validation and checkout —
    the caller should drop the discount rather than honour it.
    """
    collection = _promotion_collection()
    if collection is None:
        logger.warning("Promotions collection unavailable", code=code)
        return False

    user_key = f"redemptions_by_user.{consumer_id}"
    result = await collection.find_one_and_update(
        _claim_filter(code, consumer_id),
        {
            "$inc": {"current_uses": 1, user_key: 1},
            "$addToSet": {"redeemed_by": consumer_id},
            "$set": {"updated_at": utc_now()},
        },
    )
    if result is None:
        logger.warning(
            "Promo redemption rejected (exhausted, inactive, or unknown code)",
            code=code,
            consumer_id=consumer_id,
        )
        return False
    return True


async def release_redemption(code: str, consumer_id: str) -> None:
    """Give a claimed redemption back, e.g. when order creation then failed."""
    collection = _promotion_collection()
    if collection is None:
        return
    user_key = f"redemptions_by_user.{consumer_id}"
    await collection.update_one(
        {"code": code, "current_uses": {"$gt": 0}},
        {"$inc": {"current_uses": -1, user_key: -1}},
    )


async def is_free_delivery(code: str) -> bool:
    """Return True when a valid promo grants free delivery."""
    if not code:
        return False
    try:
        promo = await _find_promo(code)
        if not promo or promo.promo_type != "free_delivery" or not promo.is_active:
            return False
        now = utc_now()
        if promo.starts_at and now < promo.starts_at:
            return False
        if promo.ends_at and now > promo.ends_at:
            return False
        return True
    except Exception:
        return False


async def validate_and_compute(
    code: str,
    consumer_id: str,
    order_subtotal_usd: float,
    items: Optional[Iterable[Any]] = None,
    restaurant_id: Optional[str] = None,
) -> Tuple[float, bool]:
    """Convenience wrapper returning (discount_usd, free_delivery)."""
    discount = await compute_discount(
        code, consumer_id, order_subtotal_usd, items, restaurant_id
    )
    free_delivery = await is_free_delivery(code)
    return discount, free_delivery
