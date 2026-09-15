"""Driver-facing dispatch endpoints.

Every route here derives the driver from the JWT. A `driver_id` in a request
body is only ever accepted when it matches the authenticated principal — a
client must never be able to move, offer to, or act as another driver.
"""

from fastapi import APIRouter, Depends, BackgroundTasks, HTTPException
from pydantic import BaseModel
import redis.asyncio as aioredis
import structlog

from app.dispatch.schemas import DriverLocationUpdate
from app.dispatch.service import dispatch_service
from app.auth.router import get_current_user
from app.auth.models import User
from app.config import settings
from app.order.state_machine import (
    ACTIVE_DRIVER_STATES,
    RELEASABLE_STATES,
    InvalidStateTransition,
    OrderConflict,
    OrderState,
    coerce_state,
)
from app.rate_limiter import RateLimiter

router = APIRouter()
logger = structlog.get_logger()


async def get_redis():
    """Dependency to get Redis client."""
    return aioredis.from_url(settings.REDIS_URL, decode_responses=True)


@router.post("/location")
async def update_location(
    update: DriverLocationUpdate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Update the authenticated driver's location.

    The driver is taken from the token. A body that names a different driver is
    rejected outright rather than silently rewritten, so a buggy client fails
    loudly instead of scattering one driver's pings across another's track.
    """
    driver_id = str(current_user.id)
    if update.driver_id and update.driver_id != driver_id:
        logger.warning(
            "Rejected location update for another driver",
            authenticated_driver_id=driver_id,
            claimed_driver_id=update.driver_id,
        )
        raise HTTPException(
            status_code=403, detail="Cannot report a location for another driver"
        )
    update.driver_id = driver_id

    # Apply rate limiting (per driver, per window — see LOCATION_UPDATE_* settings)
    limiter = RateLimiter(redis)
    allowed, error_msg = await limiter.check_location_update(driver_id)

    if not allowed:
        raise HTTPException(status_code=429, detail=error_msg)

    background_tasks.add_task(dispatch_service.update_location, update)
    return {"status": "received"}


class OfferActionRequest(BaseModel):
    order_id: str


@router.post("/accept")
async def accept_offer(req: OfferActionRequest, current_user: User = Depends(get_current_user)):
    """Driver accepts a delivery offer.

    Acceptance is a conditional claim: if another driver got there first the
    caller receives 409 rather than a corrupted, double-assigned order.
    """
    driver_id = str(current_user.id)
    try:
        result = await dispatch_service.accept_offer(driver_id, req.order_id)
    except OrderConflict as e:
        raise HTTPException(status_code=409, detail=str(e))
    except InvalidStateTransition as e:
        raise HTTPException(status_code=400, detail=str(e))
    if not result:
        raise HTTPException(status_code=400, detail="Could not accept offer")
    return {"status": "accepted", "order_id": req.order_id}


@router.post("/decline")
async def decline_offer(req: OfferActionRequest, current_user: User = Depends(get_current_user)):
    """Driver declines a delivery offer; it moves straight to the next driver."""
    driver_id = str(current_user.id)
    await dispatch_service.decline_offer(driver_id, req.order_id)
    return {"status": "declined", "order_id": req.order_id}


@router.post("/complete")
async def complete_delivery(
    req: OfferActionRequest, current_user: User = Depends(get_current_user)
):
    """Driver marks their own delivery complete.

    Goes through the state machine, so it is recorded in the audit trail, the
    consumer is notified, and it is refused unless the food was actually picked
    up by *this* driver.
    """
    from app.order.service import OrderService

    driver_id = str(current_user.id)
    try:
        order = await OrderService.transition_state(
            req.order_id,
            OrderState.DELIVERED,
            actor_id=driver_id,
            reason="driver_completed",
            require_driver_id=driver_id,
            expected_states={OrderState.PICKED_UP, OrderState.ARRIVED_AT_CUSTOMER},
        )
    except OrderConflict as e:
        raise HTTPException(status_code=409, detail=str(e))
    except InvalidStateTransition as e:
        raise HTTPException(status_code=400, detail=str(e))
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return {"status": "delivered", "order_id": req.order_id}


@router.post("/release")
async def release_order(
    req: OfferActionRequest, current_user: User = Depends(get_current_user)
):
    """Driver hands an order back before pickup so it can be re-dispatched."""
    driver_id = str(current_user.id)
    order = await dispatch_service.release_order(driver_id, req.order_id)
    if order is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "This order cannot be handed back — either it is not yours or "
                "you have already collected it. Contact support instead."
            ),
        )
    return {"status": "released", "order_id": req.order_id}


@router.get("/state")
async def get_driver_state(current_user: User = Depends(get_current_user)):
    """Get the current driver state (online/offline + active order)."""
    driver_id = str(current_user.id)
    state = await dispatch_service.get_driver_state(driver_id)

    # Transform for frontend
    active_order = state["active_order"]
    order_data = None

    if active_order:
        # Minimal order data needed to resume flow
        order_data = {
            "order_id": str(active_order.id),
            "short_id": f"ZV{str(active_order.id)[-4:].upper()}",
            "state": active_order.state,
            "pickup": active_order.pickup_location,
            "dropoff": active_order.dropoff_location,
            # Add other necessary fields if needed by frontend
        }

    return {
        "status": state["status"],
        "active_order": order_data
    }


@router.post("/reset")
async def reset_driver_state(current_user: User = Depends(get_current_user)):
    """Clear the driver's stuck orders so they can take new work.

    This used to write ``state = DELIVERED`` straight onto every active order,
    bypassing the state machine entirely: an order the driver had merely
    accepted was recorded as delivered, the consumer was never notified, no
    audit event was written, and the driver was credited for a delivery that
    never happened. It is now state-aware:

    * ``PICKED_UP`` / ``ARRIVED_AT_CUSTOMER`` — the driver has the food, so the
      order is completed through the state machine (audit event, consumer
      notification, terminal state).
    * ``ACCEPTED`` / ``ARRIVED_AT_MERCHANT`` / ``READY_FOR_PICKUP`` — nothing was
      collected, so the order is handed back to dispatch and re-offered instead
      of being faked as delivered.
    """
    from app.order.models import Order
    from app.order.service import OrderService

    driver_id = str(current_user.id)

    active_orders = await Order.find({
        "driver_id": driver_id,
        "state": {"$in": [s.value for s in ACTIVE_DRIVER_STATES]},
    }).to_list()

    completed = 0
    released = 0
    for order in active_orders:
        order_id = str(order.id)
        try:
            state = coerce_state(order.state)
        except InvalidStateTransition:
            continue

        try:
            if state in RELEASABLE_STATES:
                if await dispatch_service.release_order(
                    driver_id, order_id, reason="driver_reset"
                ):
                    released += 1
            else:
                await OrderService.transition_state(
                    order_id,
                    OrderState.DELIVERED,
                    actor_id=driver_id,
                    reason="driver_reset_completion",
                    require_driver_id=driver_id,
                )
                completed += 1
        except (OrderConflict, InvalidStateTransition) as e:
            logger.warning(
                "Could not reset order", order_id=order_id, driver_id=driver_id, error=str(e)
            )
            continue

    total = completed + released
    return {
        "status": "reset",
        "orders_reset": total,
        "orders_completed": completed,
        "orders_released": released,
        "message": (
            f"Completed {completed} delivery(ies) and returned {released} "
            "order(s) to dispatch"
        ),
    }
