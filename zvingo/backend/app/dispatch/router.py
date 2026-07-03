from fastapi import APIRouter, Depends, BackgroundTasks, HTTPException
from pydantic import BaseModel
import redis.asyncio as aioredis
from app.dispatch.schemas import DriverLocationUpdate
from app.dispatch.service import dispatch_service
from app.auth.router import oauth2_scheme, get_current_user
from app.auth.models import User
from app.config import settings
from app.rate_limiter import RateLimiter

router = APIRouter()


async def get_redis():
    """Dependency to get Redis client."""
    return aioredis.from_url(settings.REDIS_URL, decode_responses=True)


@router.post("/location")
async def update_location(
    update: DriverLocationUpdate,
    background_tasks: BackgroundTasks,
    token: str = Depends(oauth2_scheme),
    redis: aioredis.Redis = Depends(get_redis),
):
    """Update driver location with rate limiting."""
    # Apply rate limiting (max 20 updates per 60 seconds per driver)
    limiter = RateLimiter(redis)
    allowed, error_msg = await limiter.check_location_update(update.driver_id)

    if not allowed:
        raise HTTPException(status_code=429, detail=error_msg)

    background_tasks.add_task(dispatch_service.update_location, update)
    return {"status": "received"}


class OfferActionRequest(BaseModel):
    order_id: str


@router.post("/accept")
async def accept_offer(req: OfferActionRequest, current_user: User = Depends(get_current_user)):
    """Driver accepts a delivery offer."""
    driver_id = str(current_user.id)
    result = await dispatch_service.accept_offer(driver_id, req.order_id)
    if not result:
        raise HTTPException(status_code=400, detail="Could not accept offer")
    return {"status": "accepted", "order_id": req.order_id}


@router.post("/decline")
async def decline_offer(req: OfferActionRequest, current_user: User = Depends(get_current_user)):
    """Driver declines a delivery offer."""
    driver_id = str(current_user.id)
    result = await dispatch_service.decline_offer(driver_id, req.order_id)
    return {"status": "declined", "order_id": req.order_id}


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
    """
    Reset driver state: clear any stuck orders by marking them as DELIVERED.
    This is a debug/recovery endpoint for when orders get stuck.
    """
    from app.order.models import Order
    from app.order.state_machine import OrderState
    
    driver_id = str(current_user.id)
    
    # Find any active orders for this driver
    active_orders = await Order.find({
        "driver_id": driver_id,
        "state": {"$in": [
            OrderState.ACCEPTED,
            OrderState.ARRIVED_AT_MERCHANT,
            OrderState.READY_FOR_PICKUP,
            OrderState.PICKED_UP,
            OrderState.ARRIVED_AT_CUSTOMER
        ]}
    }).to_list()
    
    reset_count = 0
    for order in active_orders:
        # Mark as delivered to free up the driver
        order.state = OrderState.DELIVERED
        await order.save()
        reset_count += 1
    
    return {
        "status": "reset",
        "orders_reset": reset_count,
        "message": f"Reset {reset_count} stuck order(s) to DELIVERED state"
    }
