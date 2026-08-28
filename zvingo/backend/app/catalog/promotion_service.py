"""Promotion redemption logic.

Computes discounts from a promo code and records per-user usage. Kept separate
from the catalog router so order creation can reuse it without a circular
import.
"""

import structlog
from typing import Optional, Tuple

from app.time_utils import utc_now
from app.catalog.promotion_models import Promotion

logger = structlog.get_logger()


class PromotionError(Exception):
    """Raised when a promo code is invalid, expired, or not applicable."""


async def _find_promo(code: str) -> Optional[Promotion]:
    return await Promotion.find_one(Promotion.code == code)


async def compute_discount(
    code: str, consumer_id: str, order_subtotal_usd: float
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

    if consumer_id in promo.redeemed_by:
        raise PromotionError("You have already used this promo code")

    if promo.promo_type == "percentage":
        discount = round(order_subtotal_usd * (promo.discount_value / 100.0), 2)
    elif promo.promo_type == "flat":
        discount = round(promo.discount_value, 2)
    elif promo.promo_type == "free_delivery":
        # Free delivery is applied to the delivery fee by the caller; here we
        # return 0 and let the caller handle the fee waiver via is_free_delivery.
        discount = 0.0
    else:
        # Unknown type — fail safe.
        raise PromotionError("Unsupported promo type")

    if promo.max_discount_usd is not None:
        discount = min(discount, promo.max_discount_usd)

    return max(0.0, round(discount, 2))


async def record_redemption(code: str, consumer_id: str) -> None:
    """Increment usage counters after an order with this promo is placed."""
    promo = await _find_promo(code)
    if not promo:
        logger.warning("Record redemption for missing promo", code=code)
        return
    promo.current_uses += 1
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
    code: str, consumer_id: str, order_subtotal_usd: float
) -> Tuple[float, bool]:
    """Convenience wrapper returning (discount_usd, free_delivery)."""
    discount = await compute_discount(code, consumer_id, order_subtotal_usd)
    free_delivery = await is_free_delivery(code)
    return discount, free_delivery
