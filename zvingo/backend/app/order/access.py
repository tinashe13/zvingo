"""Shared authorization check for order-scoped resources.

An order is visible to exactly three parties: the consumer who placed it, the
driver assigned to it, and the merchant user who owns the restaurant it was
placed with. Order details, chat, and the live tracking channels all gate on
this same rule, so it lives in one place.
"""

from typing import Optional


async def can_access_order(order, user) -> bool:
    """True when `user` is the order's consumer, driver, or owning merchant."""
    uid = str(user.id)
    if uid in (order.consumer_id, order.driver_id):
        return True
    try:
        from app.catalog.models import Restaurant

        restaurant = await Restaurant.get(order.merchant_id)
        if restaurant and restaurant.merchant_id == uid:
            return True
    except Exception:
        pass
    return False


async def owning_merchant_id(order) -> Optional[str]:
    """The merchant user id behind an order's restaurant, when resolvable."""
    try:
        from app.catalog.models import Restaurant

        restaurant = await Restaurant.get(order.merchant_id)
        return restaurant.merchant_id if restaurant else None
    except Exception:
        return None
