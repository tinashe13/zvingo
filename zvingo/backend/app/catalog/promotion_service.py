"""Promotion redemption logic.

Computes discounts from a promo code and records per-user usage. Kept separate
from the catalog router so order creation can reuse it without a circular
import.
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
) -> float:
    """Validate a promo code and return the discount in USD.

    Raises PromotionError with a user-facing message when the code cannot be
    applied. Does NOT mutate state; call ``record_redemption`` after the order
    is successfully created.
    """
    if not code:
        raise PromotionError("Promo code is required")

    promo = await _find_promo(code)
    if not promo:
        raise PromotionError("Invalid promo code")
    if not promo.is_active:
        raise PromotionError("This promo code is no longer active")

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

    if promo.promo_type == "percentage":
        discount = round(order_subtotal_usd * (promo.discount_value / 100.0), 2)
    elif promo.promo_type == "flat":
        discount = round(promo.discount_value, 2)
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


async def record_redemption(code: str, consumer_id: str) -> None:
    """Increment usage counters after an order with this promo is placed."""
    promo = await _find_promo(code)
    if not promo:
        logger.warning("Record redemption for missing promo", code=code)
        return
    promo.current_uses += 1
    counts = dict(promo.redemptions_by_user or {})
    counts[consumer_id] = _uses_by(promo, consumer_id) + 1
    promo.redemptions_by_user = counts
    if consumer_id not in promo.redeemed_by:
        promo.redeemed_by.append(consumer_id)
    await promo.save()


async def is_free_delivery(code: str) -> bool:
    """Return True when a valid promo grants free delivery."""
    if not code:
        return False
    try:
        promo = await _find_promo(code)
        return bool(promo and promo.promo_type == "free_delivery" and promo.is_active)
    except Exception:
        return False


async def validate_and_compute(
    code: str,
    consumer_id: str,
    order_subtotal_usd: float,
    items: Optional[Iterable[Any]] = None,
) -> Tuple[float, bool]:
    """Convenience wrapper returning (discount_usd, free_delivery)."""
    discount = await compute_discount(code, consumer_id, order_subtotal_usd, items)
    free_delivery = await is_free_delivery(code)
    return discount, free_delivery
