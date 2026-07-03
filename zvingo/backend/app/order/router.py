from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from app.order.schemas import OrderCreate, OrderResponse, OrderUpdateState, OrderItem
from app.order.service import OrderService
from app.order.models import Order
from app.order.state_machine import InvalidStateTransition, OrderState
from app.auth.router import oauth2_scheme, get_current_user
from app.auth.models import User

router = APIRouter()


async def _get_driver_name(driver_id: Optional[str]) -> Optional[str]:
    """Helper to fetch driver's full name from User model."""
    if not driver_id:
        return None
    try:
        driver = await User.get(driver_id)
        return driver.full_name if driver else None
    except Exception:
        return None


async def _assert_order_access(order: Order, user: User):
    """403 unless the user is the order's consumer, driver, or owning merchant."""
    uid = str(user.id)
    if uid in (order.consumer_id, order.driver_id):
        return
    # Merchant check: Order.merchant_id is a Restaurant id owned by a merchant user
    try:
        from app.catalog.models import Restaurant
        restaurant = await Restaurant.get(order.merchant_id)
        if restaurant and restaurant.merchant_id == uid:
            return
    except Exception:
        pass
    raise HTTPException(status_code=403, detail="Not authorized to view this order")


@router.get("/{order_id}")
async def get_order(order_id: str, current_user: User = Depends(get_current_user)):
    """Get a single order by ID with driver info."""
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    await _assert_order_access(order, current_user)

    driver_name = await _get_driver_name(order.driver_id)
    
    # Get driver's current location from Redis if available
    driver_lat = None
    driver_lng = None
    if order.driver_id:
        try:
            import redis.asyncio as aioredis
            from app.config import settings
            r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
            pos = await r.geopos("driver_locations", order.driver_id)
            await r.close()
            if pos and pos[0]:
                driver_lng, driver_lat = pos[0]  # geopos returns (lng, lat)
        except Exception:
            pass
    
    # Ensure state is returned as plain string (not enum repr)
    state_str = order.state.value if hasattr(order.state, 'value') else str(order.state)
    if state_str.startswith('OrderState.'):
        state_str = state_str.replace('OrderState.', '')
    
    return {
        "id": str(order.id),
        "state": state_str,
        "total_amount": order.total_amount,
        "created_at": order.created_at.isoformat() if order.created_at else None,
        "driver_id": order.driver_id,
        "driver_name": driver_name,
        "driver_lat": driver_lat,
        "driver_lng": driver_lng,
        "merchant_id": order.merchant_id,
        "consumer_id": order.consumer_id,
        "items": [{"name": i.name if hasattr(i, 'name') else i.get("name", ""), 
                   "quantity": i.quantity if hasattr(i, 'quantity') else i.get("quantity", 1), 
                   "price": i.price if hasattr(i, 'price') else i.get("price", 0)} 
                  for i in (order.items or [])],
        "pickup_lat": order.pickup_location['coordinates'][1] if order.pickup_location else None,
        "pickup_lng": order.pickup_location['coordinates'][0] if order.pickup_location else None,
        "delivery_lat": order.dropoff_location['coordinates'][1] if order.dropoff_location else None,
        "delivery_lng": order.dropoff_location['coordinates'][0] if order.dropoff_location else None,
    }


@router.post("/{order_id}/cancel")
async def cancel_order(
    order_id: str,
    current_user: User = Depends(get_current_user)
):
    """Consumer cancels their order."""
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    
    # Verify the consumer owns this order
    if order.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to cancel this order")
    
    # Normalize state for comparison
    current_state = order.state.value if hasattr(order.state, 'value') else str(order.state)
    if current_state.startswith('OrderState.'):
        current_state = current_state.replace('OrderState.', '')
    
    # Only allow cancellation before pickup
    non_cancellable = ['PICKED_UP', 'ARRIVED_AT_CUSTOMER', 'DELIVERED', 'CANCELLED']
    if current_state in non_cancellable:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel order in state {current_state}. Order has already been picked up or delivered."
        )
    
    # Transition to CANCELLED
    try:
        order = await OrderService.transition_state(order_id, OrderState.CANCELLED, str(current_user.id))
    except InvalidStateTransition as e:
        raise HTTPException(status_code=400, detail=str(e))
    
    return {"status": "cancelled", "order_id": order_id, "message": "Order cancelled successfully"}

@router.post("/", response_model=OrderResponse)
async def create_order(order_in: OrderCreate):
    try:
        order = await OrderService.create_order(order_in)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return OrderResponse(
        id=str(order.id),
        state=order.state,
        total_amount=order.total_amount,
        created_at=order.created_at,
        merchant_id=order.merchant_id,
        consumer_id=order.consumer_id,
        items=[{"name": i.name if hasattr(i, 'name') else i.get("name", ""), 
                "quantity": i.quantity if hasattr(i, 'quantity') else i.get("quantity", 1), 
                "price": i.price if hasattr(i, 'price') else i.get("price", 0)} 
               for i in order.items],
        pickup_lat=order.pickup_location['coordinates'][1] if order.pickup_location else None,
        pickup_lng=order.pickup_location['coordinates'][0] if order.pickup_location else None,
        delivery_lat=order.dropoff_location['coordinates'][1] if order.dropoff_location else None,
        delivery_lng=order.dropoff_location['coordinates'][0] if order.dropoff_location else None,
    )

@router.put("/{order_id}/state", response_model=OrderResponse)
async def update_order_state(order_id: str, state_update: OrderUpdateState, token: str = Depends(oauth2_scheme)):
    try:
        order = await OrderService.transition_state(order_id, state_update.state, state_update.driver_id)
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")

        # Format items properly (they're stored as dicts in MongoDB)
        formatted_items = []
        for i in order.items:
            if isinstance(i, dict):
                formatted_items.append(OrderItem(
                    name=i.get("name", ""),
                    quantity=i.get("quantity", 1),
                    price=i.get("price", 0)
                ))
            else:
                formatted_items.append(i)

        return OrderResponse(
            id=str(order.id),
            state=order.state,
            total_amount=order.total_amount,
            created_at=order.created_at,
            driver_id=order.driver_id,
            merchant_id=order.merchant_id,
            consumer_id=order.consumer_id,
            items=formatted_items,
            pickup_lat=order.pickup_location['coordinates'][1] if order.pickup_location else None,
            pickup_lng=order.pickup_location['coordinates'][0] if order.pickup_location else None,
            delivery_lat=order.dropoff_location['coordinates'][1] if order.dropoff_location else None,
            delivery_lng=order.dropoff_location['coordinates'][0] if order.dropoff_location else None,
        )
    except InvalidStateTransition as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/consumer/{consumer_id}", response_model=List[OrderResponse])
async def get_consumer_orders(consumer_id: str, current_user: User = Depends(get_current_user)):
    # Ownership check: consumers may only list their own orders
    if consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to view these orders")
    orders = await Order.find(Order.consumer_id == consumer_id).sort(-Order.created_at).to_list()
    return [
        OrderResponse(
            id=str(o.id),
            state=o.state,
            total_amount=o.total_amount,
            created_at=o.created_at,
            driver_id=o.driver_id,
            merchant_id=o.merchant_id,
            consumer_id=o.consumer_id,
            items=[{"name": i.name if hasattr(i, 'name') else i.get("name", ""), 
                    "quantity": i.quantity if hasattr(i, 'quantity') else i.get("quantity", 1), 
                    "price": i.price if hasattr(i, 'price') else i.get("price", 0)} 
                   for i in o.items],
            pickup_lat=o.pickup_location['coordinates'][1] if o.pickup_location else None,
            pickup_lng=o.pickup_location['coordinates'][0] if o.pickup_location else None,
            delivery_lat=o.dropoff_location['coordinates'][1] if o.dropoff_location else None,
            delivery_lng=o.dropoff_location['coordinates'][0] if o.dropoff_location else None,
        )
        for o in orders
    ]

@router.get("/merchant/{merchant_id}", response_model=List[OrderResponse])
async def get_merchant_orders(merchant_id: str, current_user: User = Depends(get_current_user)):
    # Ownership check: merchants may only list orders for their own account
    if merchant_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to view these orders")
    # The merchant_id passed here is the User ID (from auth/me)
    # But Orders are linked to Restaurant IDs (Order.merchant_id = Restaurant.id)
    # So we must find all restaurants owned by this merchant first.
    from app.catalog.models import Restaurant
    
    restaurants = await Restaurant.find(Restaurant.merchant_id == merchant_id).to_list()
    restaurant_ids = [str(r.id) for r in restaurants]
    
    if not restaurant_ids:
        return []

    # Query orders for any of the merchant's restaurants
    orders = await Order.find({"merchant_id": {"$in": restaurant_ids}}).sort(-Order.created_at).to_list()
    
    return [
        OrderResponse(
            id=str(o.id),
            state=o.state,
            total_amount=o.total_amount,
            created_at=o.created_at,
            driver_id=o.driver_id,
            merchant_id=o.merchant_id,
            consumer_id=o.consumer_id,
            items=[{"name": i.name if hasattr(i, 'name') else i.get("name", ""), 
                    "quantity": i.quantity if hasattr(i, 'quantity') else i.get("quantity", 1), 
                    "price": i.price if hasattr(i, 'price') else i.get("price", 0)} 
                   for i in o.items],
            pickup_lat=o.pickup_location['coordinates'][1] if o.pickup_location else None,
            pickup_lng=o.pickup_location['coordinates'][0] if o.pickup_location else None,
            delivery_lat=o.dropoff_location['coordinates'][1] if o.dropoff_location else None,
            delivery_lng=o.dropoff_location['coordinates'][0] if o.dropoff_location else None,
        )
        for o in orders
    ]

@router.post("/{order_id}/confirm-delivery")
async def consumer_confirm_delivery(
    order_id: str,
    current_user: User = Depends(get_current_user)
):
    """Consumer confirms that their order has been delivered."""
    from app.order.models import Order
    from app.order.state_machine import OrderState, validate_transition, InvalidStateTransition
    
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    
    # Verify the consumer owns this order
    if order.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to confirm this order")
    
    # Only allow confirmation when driver has arrived or is very close
    allowed_states = [OrderState.ARRIVED_AT_CUSTOMER, OrderState.PICKED_UP]
    if order.state not in [s.value for s in allowed_states]:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot confirm delivery in state {order.state}. Driver must be en route or arrived."
        )
    
    # Transition to DELIVERED
    try:
        order = await OrderService.transition_state(order_id, OrderState.DELIVERED, str(current_user.id))
    except InvalidStateTransition as e:
        raise HTTPException(status_code=400, detail=str(e))
    
    return {"status": "delivered", "order_id": order_id, "message": "Delivery confirmed successfully"}


@router.get("/driver/active", response_model=List[OrderResponse])
async def get_driver_active_orders(current_user: User = Depends(get_current_user)):
    driver_id = str(current_user.id)

    # Active states: ACCEPTED, ARRIVED_AT_MERCHANT, READY_FOR_PICKUP, PICKED_UP, ARRIVED_AT_CUSTOMER
    active_states = [
        OrderState.ACCEPTED,
        OrderState.ARRIVED_AT_MERCHANT,
        OrderState.READY_FOR_PICKUP,
        OrderState.PICKED_UP,
        OrderState.ARRIVED_AT_CUSTOMER
    ]
    
    orders = await Order.find(
        Order.driver_id == driver_id,
        {
            "state": {"$in": active_states}
        }
    ).sort(-Order.created_at).to_list()
    
    return [
        OrderResponse(
            id=str(o.id),
            state=o.state,
            total_amount=o.total_amount,
            created_at=o.created_at,
            driver_id=o.driver_id,
            merchant_id=o.merchant_id,
            consumer_id=o.consumer_id,
            items=[{"name": i.name if hasattr(i, 'name') else i.get("name", ""), 
                    "quantity": i.quantity if hasattr(i, 'quantity') else i.get("quantity", 1), 
                    "price": i.price if hasattr(i, 'price') else i.get("price", 0)} 
                   for i in o.items],
            pickup_lat=o.pickup_location['coordinates'][1] if o.pickup_location else None,
            pickup_lng=o.pickup_location['coordinates'][0] if o.pickup_location else None,
            delivery_lat=o.dropoff_location['coordinates'][1] if o.dropoff_location else None,
            delivery_lng=o.dropoff_location['coordinates'][0] if o.dropoff_location else None,
        )
        for o in orders
    ]
