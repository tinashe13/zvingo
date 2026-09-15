"""The one correct way to authorize a request.

Authentication answers *who is calling*; this module answers *may they do
this*. Every router should reach for a helper here rather than hand-rolling an
``if x.id != y: raise HTTPException(403)``, because the hand-rolled version is
where the bugs live — a missing branch, a string/ObjectId mismatch, a check
that compares the wrong side of the relationship.

Two shapes are provided:

``is_*`` / ``can_*``
    Predicates returning ``bool``. Use them when the caller wants to *filter*
    rather than reject (e.g. hiding fields a merchant may not see).

``require_*``
    Raise :class:`fastapi.HTTPException` with 403 on failure. Use them at the
    top of a handler; the message is deliberately generic so a 403 never
    doubles as an existence oracle.

Rules encoded here
------------------
* An **order** is visible to exactly three parties: the consumer who placed
  it, the driver assigned to it, and the merchant user who owns the
  restaurant it was placed with.
* A **restaurant** is writable only by its owning merchant.
* A **user-scoped collection** (earnings, schedule, sync deltas, payments) is
  readable only by that user.
* An **admin** overrides nothing implicitly. Where admin access is intended it
  is spelled out with ``allow_admin=True``, so no route grants it by accident.
"""

from typing import Any, Optional

from fastapi import HTTPException, status

FORBIDDEN_DETAIL = "Not authorized to perform this action"


class Role:
    """Canonical role strings. ``User.role`` holds one of these."""

    CONSUMER = "consumer"
    DRIVER = "driver"
    MERCHANT = "merchant"
    ADMIN = "admin"

    ALL = (CONSUMER, DRIVER, MERCHANT, ADMIN)


def _uid(value: Any) -> Optional[str]:
    """Normalise anything id-shaped (ObjectId, document, str) to a string."""
    if value is None:
        return None
    if hasattr(value, "id") and not isinstance(value, str):
        value = value.id
    text = str(value).strip()
    return text or None


def forbidden(detail: str = FORBIDDEN_DETAIL) -> HTTPException:
    return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


# --- Roles --------------------------------------------------------------------


def has_role(user: Any, *roles: str) -> bool:
    """True when ``user.role`` is one of ``roles``."""
    return getattr(user, "role", None) in roles


def is_admin(user: Any) -> bool:
    return has_role(user, Role.ADMIN)


def require_any_role(user: Any, *roles: str, allow_admin: bool = False) -> Any:
    """403 unless the user holds one of ``roles`` (or is an admin, if allowed).

    Returns the user so it can be used inline::

        merchant = require_any_role(current_user, Role.MERCHANT)
    """
    if has_role(user, *roles) or (allow_admin and is_admin(user)):
        return user
    expected = " or ".join(roles) if roles else "a privileged role"
    raise forbidden(f"This action requires {expected} access")


# --- Identity -----------------------------------------------------------------


def is_same_user(user: Any, other_id: Any) -> bool:
    """True when ``other_id`` names this user."""
    left, right = _uid(user), _uid(other_id)
    return left is not None and left == right


def require_self(user: Any, other_id: Any, *, allow_admin: bool = False, detail: Optional[str] = None) -> Any:
    """403 unless ``other_id`` is the caller's own id.

    This is the check that stops ``GET /finance/earnings/driver/{driver_id}``
    style routes from becoming an enumeration of everyone else's data.
    """
    if is_same_user(user, other_id) or (allow_admin and is_admin(user)):
        return user
    raise forbidden(detail or "Not authorized to access another user's data")


# --- Orders -------------------------------------------------------------------


async def owning_merchant_id(order: Any) -> Optional[str]:
    """The merchant *user* id behind an order's restaurant, when resolvable.

    ``Order.merchant_id`` holds a **restaurant** id, not a user id — the name
    is historical. Resolving it is why this function exists; comparing
    ``order.merchant_id`` to a user id directly is always wrong.
    """
    try:
        from app.catalog.models import Restaurant

        restaurant = await Restaurant.get(order.merchant_id)
        return _uid(restaurant.merchant_id) if restaurant else None
    except Exception:
        return None


async def is_order_participant(order: Any, user: Any) -> bool:
    """True when ``user`` is the order's consumer, driver, or owning merchant."""
    if order is None or user is None:
        return False
    uid = _uid(user)
    if uid is None:
        return False
    if uid in (_uid(getattr(order, "consumer_id", None)), _uid(getattr(order, "driver_id", None))):
        return True
    return uid is not None and uid == await owning_merchant_id(order)


async def require_order_participant(
    order: Any, user: Any, *, allow_admin: bool = False, detail: Optional[str] = None
) -> Any:
    """403 unless the user is a party to this order. Returns the order."""
    if allow_admin and is_admin(user):
        return order
    if await is_order_participant(order, user):
        return order
    raise forbidden(detail or "Not authorized to view this order")


async def require_order_consumer(order: Any, user: Any, detail: Optional[str] = None) -> Any:
    """403 unless the user placed this order.

    Stricter than :func:`require_order_participant` — use it for actions only
    the buyer may take (cancel, confirm delivery, pay, review).
    """
    if is_same_user(user, getattr(order, "consumer_id", None)):
        return order
    raise forbidden(detail or "Not authorized to act on this order")


async def require_order_driver(order: Any, user: Any, detail: Optional[str] = None) -> Any:
    """403 unless the user is the driver assigned to this order."""
    driver_id = getattr(order, "driver_id", None)
    if driver_id and is_same_user(user, driver_id):
        return order
    raise forbidden(detail or "Not the assigned driver for this order")


async def require_order_merchant(order: Any, user: Any, detail: Optional[str] = None) -> Any:
    """403 unless the user owns the restaurant this order was placed with."""
    if is_same_user(user, await owning_merchant_id(order)):
        return order
    raise forbidden(detail or "Not the merchant for this order")


# --- Restaurants --------------------------------------------------------------


def is_restaurant_owner(restaurant: Any, user: Any) -> bool:
    return restaurant is not None and is_same_user(user, getattr(restaurant, "merchant_id", None))


def require_restaurant_owner(
    restaurant: Any, user: Any, *, allow_admin: bool = False, detail: Optional[str] = None
) -> Any:
    """403 unless the user is the restaurant's merchant. Returns the restaurant."""
    if is_restaurant_owner(restaurant, user) or (allow_admin and is_admin(user)):
        return restaurant
    raise forbidden(detail or "Not authorized to manage this restaurant")
