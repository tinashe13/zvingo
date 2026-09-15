"""Order authorization — thin façade over :mod:`app.auth.authorization`.

The real rules live in ``app/auth/authorization.py`` so that orders, chat,
tracking, payments and ratings all consult one implementation. This module
stays because a dozen callers import from it; each name below is the same
object the authorization module exposes.

New code should prefer the richer helpers directly::

    from app.auth.authorization import (
        require_order_participant,   # any party to the order (403 on failure)
        require_order_consumer,      # only the buyer
        require_order_driver,        # only the assigned driver
        require_order_merchant,      # only the owning merchant
    )
"""

from app.auth.authorization import (  # noqa: F401  (re-exported)
    is_order_participant,
    owning_merchant_id,
    require_order_consumer,
    require_order_driver,
    require_order_merchant,
    require_order_participant,
)

__all__ = [
    "can_access_order",
    "is_order_participant",
    "owning_merchant_id",
    "require_order_consumer",
    "require_order_driver",
    "require_order_merchant",
    "require_order_participant",
]


async def can_access_order(order, user) -> bool:
    """True when `user` is the order's consumer, driver, or owning merchant."""
    return await is_order_participant(order, user)
