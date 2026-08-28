"""Admin platform management API.

Every route here requires `role == "admin"` via `get_current_admin`. The
endpoints are deliberately read-mostly: an admin can inspect users, orders,
payments, and restaurants, and take the few corrective actions support actually
needs (deactivate an account, force-cancel a stuck order, re-dispatch one that
never found a driver).
"""

import re
from datetime import timedelta
from typing import Optional

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query

from app.admin.schemas import (
    AdminUserUpdate,
    Page,
    PlatformStats,
    RestaurantAdminUpdate,
)
from app.auth.models import User
from app.auth.router import get_current_admin
from app.catalog.models import Restaurant
from app.observability.alerts import alert_service
from app.order.models import Order
from app.order.service import OrderService
from app.order.state_machine import InvalidStateTransition, OrderState
from app.payment.models import Payment, PaymentStatus
from app.time_utils import utc_now

router = APIRouter()
logger = structlog.get_logger()

ASSIGNABLE_ROLES = ("consumer", "driver", "merchant", "admin")

TERMINAL_STATES = (OrderState.DELIVERED, OrderState.CANCELLED)


def _skip(page: int, page_size: int) -> int:
    return (page - 1) * page_size


def _state_str(state) -> str:
    return str(getattr(state, "value", state))


def _user_record(user: User) -> dict:
    return {
        "id": str(user.id),
        "full_name": user.full_name,
        "phone": user.phone,
        "email": user.email,
        "role": user.role,
        "is_active": user.is_active,
        "is_dashing": user.is_dashing,
        "driver_rating": user.driver_rating,
        "driver_review_count": user.driver_review_count,
        "created_at": user.created_at.isoformat() if user.created_at else None,
    }


def _order_record(order: Order) -> dict:
    return {
        "id": str(order.id),
        "state": _state_str(order.state),
        "merchant_id": order.merchant_id,
        "consumer_id": order.consumer_id,
        "driver_id": order.driver_id,
        "group_id": order.group_id,
        "total_amount": order.total_amount,
        "delivery_fee": order.delivery_fee,
        "discount_amount": order.discount_amount,
        "promo_code": order.promo_code,
        "is_pickup": order.is_pickup,
        "scheduled_at": order.scheduled_at.isoformat() if order.scheduled_at else None,
        "retry_count": order.retry_count,
        "created_at": order.created_at.isoformat() if order.created_at else None,
        "updated_at": order.updated_at.isoformat() if order.updated_at else None,
    }


def _payment_record(payment: Payment) -> dict:
    return {
        "id": str(payment.id),
        "order_id": payment.order_id,
        "consumer_id": payment.consumer_id,
        "amount_usd": payment.amount_usd,
        "amount_local": payment.amount_local,
        "currency": payment.currency,
        "method": _state_str(payment.method),
        "status": _state_str(payment.status),
        "paynow_reference": payment.paynow_reference,
        "created_at": payment.created_at.isoformat() if payment.created_at else None,
    }


# ────────────────────────────────────────────────────────────────────
# Overview
# ────────────────────────────────────────────────────────────────────


@router.get("/stats", response_model=PlatformStats)
async def platform_stats(_: User = Depends(get_current_admin)):
    """Counts and GMV across the whole platform, for the admin dashboard."""
    users = {}
    for role in ASSIGNABLE_ROLES:
        users[role] = await User.find(User.role == role).count()
    users["total"] = await User.find_all().count()
    users["inactive"] = await User.find(User.is_active == False).count()  # noqa: E712

    orders = {}
    for state in OrderState:
        orders[state.value] = await Order.find(Order.state == state).count()
    orders["total"] = await Order.find_all().count()

    payments = {}
    for status in PaymentStatus:
        payments[status.value] = await Payment.find(Payment.status == status).count()

    today_start = utc_now().replace(hour=0, minute=0, second=0, microsecond=0)
    delivered = await Order.find(Order.state == OrderState.DELIVERED).to_list()
    gmv = {
        "all_time": round(sum(o.total_amount for o in delivered), 2),
        "today": round(
            sum(
                o.total_amount
                for o in delivered
                if o.updated_at and o.updated_at >= today_start
            ),
            2,
        ),
    }

    restaurants = {
        "total": await Restaurant.find_all().count(),
        "active": await Restaurant.find(Restaurant.is_active == True).count(),  # noqa: E712
    }

    return PlatformStats(
        users=users,
        orders=orders,
        payments=payments,
        gmv=gmv,
        restaurants=restaurants,
        generated_at=utc_now(),
    )


@router.get("/alerts")
async def list_alerts(
    limit: int = Query(default=50, ge=1, le=200), _: User = Depends(get_current_admin)
):
    """Recent operational alerts, newest first."""
    return {"alerts": alert_service.history(limit)}


@router.post("/alerts/run")
async def run_alert_checks(_: User = Depends(get_current_admin)):
    """Run the alert checks immediately instead of waiting for the next poll."""
    return {"results": await alert_service.run_checks()}


# ────────────────────────────────────────────────────────────────────
# Users
# ────────────────────────────────────────────────────────────────────


@router.get("/users", response_model=Page)
async def list_users(
    role: Optional[str] = None,
    is_active: Optional[bool] = None,
    q: Optional[str] = Query(default=None, description="Match name, phone, or email"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=25, ge=1, le=100),
    _: User = Depends(get_current_admin),
):
    """Paginated user directory with role, status, and free-text filters."""
    query: dict = {}
    if role:
        query["role"] = role
    if is_active is not None:
        query["is_active"] = is_active
    if q:
        pattern = re.escape(q)
        query["$or"] = [
            {"full_name": {"$regex": pattern, "$options": "i"}},
            {"phone": {"$regex": pattern, "$options": "i"}},
            {"email": {"$regex": pattern, "$options": "i"}},
        ]

    total = await User.find(query).count()
    users = await (
        User.find(query)
        .sort(-User.created_at)
        .skip(_skip(page, page_size))
        .limit(page_size)
        .to_list()
    )
    return Page(
        page=page,
        page_size=page_size,
        total=total,
        records=[_user_record(u) for u in users],
    )


@router.get("/users/{user_id}")
async def get_user(user_id: str, _: User = Depends(get_current_admin)):
    user = await User.get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    orders = await Order.find(Order.consumer_id == user_id).count()
    deliveries = await Order.find(Order.driver_id == user_id).count()
    return {
        **_user_record(user),
        "order_count": orders,
        "delivery_count": deliveries,
        "vehicle": user.vehicle,
        "schedule": user.schedule,
    }


@router.patch("/users/{user_id}")
async def update_user(
    user_id: str,
    update: AdminUserUpdate,
    current_admin: User = Depends(get_current_admin),
):
    """Change a user's role, name, or active status.

    An admin cannot demote or deactivate their own account — that is how a
    deployment ends up with no administrator at all.
    """
    user = await User.get(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    is_self = str(user.id) == str(current_admin.id)

    if update.role is not None:
        if update.role not in ASSIGNABLE_ROLES:
            raise HTTPException(
                status_code=400,
                detail=f"role must be one of {', '.join(ASSIGNABLE_ROLES)}",
            )
        if is_self and update.role != "admin":
            raise HTTPException(
                status_code=400, detail="An admin cannot remove their own admin role"
            )
        user.role = update.role

    if update.is_active is not None:
        if is_self and not update.is_active:
            raise HTTPException(
                status_code=400, detail="An admin cannot deactivate their own account"
            )
        user.is_active = update.is_active

    if update.full_name is not None:
        user.full_name = update.full_name

    await user.save()
    logger.info(
        "Admin updated user",
        admin_id=str(current_admin.id),
        user_id=user_id,
        changes=update.model_dump(exclude_none=True),
    )
    return _user_record(user)


# ────────────────────────────────────────────────────────────────────
# Orders
# ────────────────────────────────────────────────────────────────────


@router.get("/orders", response_model=Page)
async def list_orders(
    state: Optional[OrderState] = None,
    merchant_id: Optional[str] = None,
    consumer_id: Optional[str] = None,
    driver_id: Optional[str] = None,
    group_id: Optional[str] = None,
    stuck_minutes: Optional[int] = Query(
        default=None,
        ge=1,
        description="Only orders that have sat in a non-terminal state this long",
    ),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=25, ge=1, le=100),
    _: User = Depends(get_current_admin),
):
    """Paginated order search across every merchant, consumer, and driver."""
    query: dict = {}
    if state is not None:
        query["state"] = state
    if merchant_id:
        query["merchant_id"] = merchant_id
    if consumer_id:
        query["consumer_id"] = consumer_id
    if driver_id:
        query["driver_id"] = driver_id
    if group_id:
        query["group_id"] = group_id
    if stuck_minutes is not None:
        query["state"] = {"$nin": list(TERMINAL_STATES)}
        query["updated_at"] = {"$lt": utc_now() - timedelta(minutes=stuck_minutes)}

    total = await Order.find(query).count()
    orders = await (
        Order.find(query)
        .sort(-Order.created_at)
        .skip(_skip(page, page_size))
        .limit(page_size)
        .to_list()
    )
    return Page(
        page=page,
        page_size=page_size,
        total=total,
        records=[_order_record(o) for o in orders],
    )


@router.get("/orders/{order_id}")
async def get_order(order_id: str, _: User = Depends(get_current_admin)):
    """Full order detail including its state-transition audit trail."""
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    payment = await Payment.find_one(Payment.order_id == order_id)
    return {
        **_order_record(order),
        "items": [
            i if isinstance(i, dict) else i.model_dump() for i in (order.items or [])
        ],
        "delivery_instructions": order.delivery_instructions,
        "events": [
            {
                "state": _state_str(e.state),
                "timestamp": e.timestamp.isoformat() if e.timestamp else None,
                "actor_id": e.actor_id,
            }
            for e in (order.events or [])
        ],
        "payment": _payment_record(payment) if payment else None,
    }


@router.post("/orders/{order_id}/cancel")
async def force_cancel_order(
    order_id: str, current_admin: User = Depends(get_current_admin)
):
    """Force an order to CANCELLED — for support unwinding a broken order."""
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    try:
        order = await OrderService.transition_state(
            order_id, OrderState.CANCELLED, actor_id=str(current_admin.id)
        )
    except InvalidStateTransition as e:
        raise HTTPException(status_code=400, detail=str(e))

    logger.info(
        "Admin cancelled order", admin_id=str(current_admin.id), order_id=order_id
    )
    return {"status": "cancelled", "order_id": order_id}


@router.post("/orders/{order_id}/redispatch")
async def redispatch_order(
    order_id: str, current_admin: User = Depends(get_current_admin)
):
    """Re-run dispatch for an order that never found a driver.

    Resets the retry counter so the ordinary retry loop keeps working on it.
    """
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if order.state in TERMINAL_STATES:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot re-dispatch an order in state {_state_str(order.state)}",
        )
    if not order.pickup_location:
        raise HTTPException(
            status_code=400, detail="Order has no pickup location to dispatch from"
        )

    order.retry_count = 0
    order.last_retry_at = None
    order.scheduled_dispatched = True
    await order.save()

    from app.dispatch.service import dispatch_service

    await dispatch_service.dispatch_order(
        order_id, order.pickup_location.lat, order.pickup_location.lng
    )
    logger.info(
        "Admin re-dispatched order", admin_id=str(current_admin.id), order_id=order_id
    )
    return {"status": "redispatched", "order_id": order_id}


# ────────────────────────────────────────────────────────────────────
# Payments & restaurants
# ────────────────────────────────────────────────────────────────────


@router.get("/payments", response_model=Page)
async def list_payments(
    status: Optional[PaymentStatus] = None,
    order_id: Optional[str] = None,
    consumer_id: Optional[str] = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=25, ge=1, le=100),
    _: User = Depends(get_current_admin),
):
    """Paginated payment ledger for reconciliation and refund triage."""
    query: dict = {}
    if status is not None:
        query["status"] = status
    if order_id:
        query["order_id"] = order_id
    if consumer_id:
        query["consumer_id"] = consumer_id

    total = await Payment.find(query).count()
    payments = await (
        Payment.find(query)
        .sort(-Payment.created_at)
        .skip(_skip(page, page_size))
        .limit(page_size)
        .to_list()
    )
    return Page(
        page=page,
        page_size=page_size,
        total=total,
        records=[_payment_record(p) for p in payments],
    )


@router.get("/restaurants", response_model=Page)
async def list_restaurants(
    is_active: Optional[bool] = None,
    merchant_id: Optional[str] = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=25, ge=1, le=100),
    _: User = Depends(get_current_admin),
):
    query: dict = {}
    if is_active is not None:
        query["is_active"] = is_active
    if merchant_id:
        query["merchant_id"] = merchant_id

    total = await Restaurant.find(query).count()
    restaurants = await (
        Restaurant.find(query).skip(_skip(page, page_size)).limit(page_size).to_list()
    )
    return Page(
        page=page,
        page_size=page_size,
        total=total,
        records=[
            {
                "id": str(r.id),
                "name": r.name,
                "merchant_id": r.merchant_id,
                "is_active": r.is_active,
                "rating": r.rating,
                "review_count": r.review_count,
                "menu_items": len(r.menu),
                "address": r.address,
            }
            for r in restaurants
        ],
    )


@router.patch("/restaurants/{restaurant_id}")
async def update_restaurant(
    restaurant_id: str,
    update: RestaurantAdminUpdate,
    current_admin: User = Depends(get_current_admin),
):
    """Suspend or reinstate a restaurant without going through its merchant."""
    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")

    if update.is_active is not None:
        restaurant.is_active = update.is_active
        await restaurant.save()
        logger.info(
            "Admin updated restaurant",
            admin_id=str(current_admin.id),
            restaurant_id=restaurant_id,
            is_active=update.is_active,
        )

    return {
        "id": str(restaurant.id),
        "name": restaurant.name,
        "is_active": restaurant.is_active,
    }
