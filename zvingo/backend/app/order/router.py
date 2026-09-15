from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Annotated, Any, List, Optional
from app.order.schemas import (
    CheckoutCreate,
    CheckoutResponse,
    OrderCreate,
    OrderEventResponse,
    OrderItem,
    OrderResponse,
    OrderUpdateState,
)
from app.order.service import OrderService
from app.auth.authorization import (
    is_same_user,
    owning_merchant_id,
    require_order_consumer,
    require_order_participant,
    require_self,
)
from app.order.models import Order
from app.order.state_machine import (
    CANCELLABLE_STATES,
    ACTIVE_DRIVER_STATES,
    InvalidStateTransition,
    OrderConflict,
    OrderState,
    coerce_state,
)
from app.auth.router import get_current_user
from app.auth.models import User

router = APIRouter()

#: Default and maximum page sizes for order listings. Unbounded listings are a
#: latency and memory hazard once an account has thousands of orders.
DEFAULT_PAGE_SIZE = 50
MAX_PAGE_SIZE = 200

#: Which states each party to an order may drive it to through
#: ``PUT /orders/{id}/state``. A consumer cannot claim the food was picked up,
#: and a merchant cannot mark it delivered.
ROLE_TRANSITIONS = {
    "consumer": {OrderState.CANCELLED, OrderState.DELIVERED},
    "driver": {
        OrderState.ARRIVED_AT_MERCHANT,
        OrderState.PICKED_UP,
        OrderState.ARRIVED_AT_CUSTOMER,
        OrderState.DELIVERED,
        OrderState.CANCELLED,
    },
    "merchant": {
        OrderState.ACCEPTED,
        OrderState.ARRIVED_AT_MERCHANT,
        OrderState.READY_FOR_PICKUP,
        OrderState.CANCELLED,
    },
}


def _lat(location) -> Optional[float]:
    """Latitude from a Location or GeoJSON dict, or None when absent."""
    if location is None:
        return None
    if hasattr(location, "lat"):
        return location.lat
    coords = location.get("coordinates") if isinstance(location, dict) else None
    return coords[1] if coords else None


def _lng(location) -> Optional[float]:
    """Longitude from a Location or GeoJSON dict, or None when absent."""
    if location is None:
        return None
    if hasattr(location, "lng"):
        return location.lng
    coords = location.get("coordinates") if isinstance(location, dict) else None
    return coords[0] if coords else None


def _item(raw) -> OrderItem:
    """Normalize an order item, which may be a model or a raw Mongo dict."""
    get = raw.get if isinstance(raw, dict) else lambda key, default=None: getattr(raw, key, default)
    return OrderItem(
        name=get("name", ""),
        quantity=get("quantity", 1),
        price=get("price", 0),
        special_instructions=get("special_instructions"),
    )


def _state_str(state) -> str:
    """The plain wire spelling of an order state ("PICKED_UP")."""
    try:
        return coerce_state(state).value
    except InvalidStateTransition:
        return str(state)


def _to_response(
    order: Order,
    driver_name: Optional[str] = None,
    consumer: Optional[Any] = None,
) -> OrderResponse:
    """Build the wire representation of an order.

    ``consumer`` is the customer's ``User``, and is passed only when the caller
    has established the viewer is entitled to see it. Leave it out and the
    identity fields stay empty rather than leaking.
    """
    return OrderResponse(
        id=str(order.id),
        state=order.state,
        total_amount=order.total_amount,
        created_at=order.created_at,
        driver_id=order.driver_id,
        driver_name=driver_name,
        merchant_id=order.merchant_id,
        consumer_id=order.consumer_id,
        consumer_name=getattr(consumer, "full_name", None) if consumer else None,
        consumer_phone=getattr(consumer, "phone", None) if consumer else None,
        items=[_item(i) for i in (order.items or [])],
        pickup_lat=_lat(order.pickup_location),
        pickup_lng=_lng(order.pickup_location),
        delivery_lat=_lat(order.dropoff_location),
        delivery_lng=_lng(order.dropoff_location),
        delivery_instructions=order.delivery_instructions,
        group_id=order.group_id,
    )


async def _users_by_id(ids) -> dict:
    """Fetch several users in one query, keyed by string id.

    Order lists previously resolved each name with its own round trip, so a
    board of 30 orders cost 30 extra queries.
    """
    wanted = {str(i) for i in ids if i}
    if not wanted:
        return {}
    try:
        from app.order.service import _document_id

        users = await User.find(
            {"_id": {"$in": [_document_id(i) for i in wanted]}}
        ).to_list()
        return {str(u.id): u for u in users}
    except Exception:
        # A malformed id in the set must not blank out the whole board.
        return {}


async def _get_driver_name(driver_id: Optional[str]) -> Optional[str]:
    """Helper to fetch driver's full name from User model."""
    if not driver_id:
        return None
    try:
        driver = await User.get(driver_id)
        return driver.full_name if driver else None
    except Exception:
        return None


async def _driver_position(driver_id: str):
    """Last known (lat, lng) for a driver, or (None, None)."""
    r = None
    try:
        import redis.asyncio as aioredis

        from app.config import settings

        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        positions = await r.geopos("driver_locations", driver_id)
        if positions and positions[0]:
            lng, lat = positions[0]
            return float(lat), float(lng)
    except Exception:
        pass
    finally:
        if r is not None:
            # A leaked connection per request exhausts the pool under load.
            try:
                await r.close()
            except Exception:
                pass
    return None, None


async def _assert_order_access(order: Order, user: User):
    """403 unless the user is the order's consumer, driver, or owning merchant."""
    await require_order_participant(order, user)


async def _order_role(order: Order, user: User) -> Optional[str]:
    """How `user` relates to `order`: consumer, driver, merchant, or None."""
    if order.driver_id and is_same_user(user, order.driver_id):
        return "driver"
    if is_same_user(user, order.consumer_id):
        return "consumer"
    if is_same_user(user, await owning_merchant_id(order)):
        return "merchant"
    return None


def _paged(limit: int, offset: int) -> tuple:
    """Clamp pagination inputs to a sane window."""
    return max(1, min(limit, MAX_PAGE_SIZE)), max(0, offset)


@router.get("/{order_id}")
async def get_order(order_id: str, current_user: User = Depends(get_current_user)):
    """Get a single order by ID with driver info."""
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    await _assert_order_access(order, current_user)

    driver_name = await _get_driver_name(order.driver_id)

    driver_lat = driver_lng = None
    if order.driver_id:
        driver_lat, driver_lng = await _driver_position(order.driver_id)

    return {
        "id": str(order.id),
        "state": _state_str(order.state),
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
        "pickup_lat": _lat(order.pickup_location),
        "pickup_lng": _lng(order.pickup_location),
        "delivery_lat": _lat(order.dropoff_location),
        "delivery_lng": _lng(order.dropoff_location),
    }


@router.get("/{order_id}/events", response_model=List[OrderEventResponse])
async def get_order_events(
    order_id: str, current_user: User = Depends(get_current_user)
):
    """The order's audit trail: every state change, who made it and why.

    Visible to the same three parties as the order itself, so a consumer can see
    exactly what happened to their delivery and support can reconstruct it.
    """
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    await _assert_order_access(order, current_user)

    events = []
    for event in order.events or []:
        get = event.get if isinstance(event, dict) else (
            lambda key, default=None: getattr(event, key, default)
        )
        events.append(
            OrderEventResponse(
                state=_state_str(get("state")),
                timestamp=get("timestamp"),
                actor_id=get("actor_id"),
                reason=get("reason"),
            )
        )
    return events


@router.post("/{order_id}/cancel")
async def cancel_order(
    order_id: str,
    current_user: User = Depends(get_current_user)
):
    """Consumer cancels their order."""
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    await require_order_consumer(
        order, current_user, detail="Not authorized to cancel this order"
    )

    current_state = _state_str(order.state)
    # Cancellable states come from the state machine, so the two can never drift.
    if current_state not in {s.value for s in CANCELLABLE_STATES}:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel order in state {current_state}. Order has already been picked up or delivered."
        )
    if current_state in (OrderState.PICKED_UP.value, OrderState.ARRIVED_AT_CUSTOMER.value):
        # The driver already has the food — cancelling here needs support, not
        # a self-service button.
        raise HTTPException(
            status_code=400,
            detail=(
                "Your order has already been picked up. Contact support if "
                "something is wrong with it."
            ),
        )

    try:
        order = await OrderService.transition_state(
            order_id,
            OrderState.CANCELLED,
            str(current_user.id),
            reason="consumer_cancelled",
        )
    except OrderConflict as e:
        # A driver accepted (or support cancelled) while this request was in
        # flight. Tell the caller rather than silently corrupting the order.
        raise HTTPException(status_code=409, detail=str(e))
    except InvalidStateTransition as e:
        raise HTTPException(status_code=400, detail=str(e))

    return {"status": "cancelled", "order_id": order_id, "message": "Order cancelled successfully"}

@router.post("/", response_model=OrderResponse)
async def create_order(
    order_in: OrderCreate, current_user: User = Depends(get_current_user)
):
    """Create an order on behalf of the authenticated consumer.

    The consumer is derived from the JWT, never from the request body.
    """
    order_in.consumer_id = str(current_user.id)
    try:
        order = await OrderService.create_order(order_in)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return _to_response(order)


@router.post("/checkout", response_model=CheckoutResponse)
async def checkout(
    checkout_in: CheckoutCreate, current_user: User = Depends(get_current_user)
):
    """Check out a cart that spans one or more restaurants.

    Each restaurant's basket becomes its own order — separate merchant, driver,
    and lifecycle — but all of them share a `group_id` so the consumer app can
    still show a single basket and one live tracking screen. A promo code is
    validated against the combined subtotal, split across the baskets in
    proportion to their value, and redeemed once.
    """
    try:
        group_id, orders, discount_total = await OrderService.create_checkout(
            checkout_in, str(current_user.id)
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    return CheckoutResponse(
        group_id=group_id,
        promo_code=checkout_in.promo_code,
        discount_total=discount_total,
        subtotal=checkout_in.subtotal,
        orders=[_to_response(o) for o in orders],
    )


@router.get("/group/{group_id}", response_model=List[OrderResponse])
async def get_order_group(
    group_id: str, current_user: User = Depends(get_current_user)
):
    """All orders placed together in one multi-restaurant checkout."""
    orders = (
        await Order.find(Order.group_id == group_id)
        .sort(-Order.created_at)
        .limit(MAX_PAGE_SIZE)
        .to_list()
    )
    if not orders:
        raise HTTPException(status_code=404, detail="Order group not found")
    for order in orders:
        await _assert_order_access(order, current_user)
    # The merchant owns these orders, so they may see who each one is for.
    # Batched: one query for every consumer and driver on the page.
    people = await _users_by_id(
        [o.consumer_id for o in orders] + [o.driver_id for o in orders]
    )
    return [
        _to_response(
            o,
            driver_name=getattr(people.get(str(o.driver_id)), "full_name", None),
            consumer=people.get(str(o.consumer_id)),
        )
        for o in orders
    ]


@router.post("/{order_id}/reorder", response_model=OrderResponse)
async def reorder(
    order_id: str, current_user: User = Depends(get_current_user)
):
    """Place a new order from a previous order's items (one-tap reorder)."""
    try:
        order = await OrderService.reorder(order_id, str(current_user.id))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return _to_response(order)

@router.put("/{order_id}/state", response_model=OrderResponse)
async def update_order_state(
    order_id: str,
    state_update: OrderUpdateState,
    current_user: User = Depends(get_current_user),
):
    """Transition an order's state.

    The authenticated caller must be a party to the order, and may only move it
    to a state their role is allowed to reach: a consumer can cancel or confirm
    delivery, a merchant can confirm and mark ready, and the assigned driver can
    report progress. The actor is derived from the token — never from the request
    body — and a driver can only be assigned via the explicit driver-accept flow
    (`DispatchService.accept_offer` / the SMS ACCEPT command), so this endpoint
    can never be used to impersonate a driver.
    """
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    await _assert_order_access(order, current_user)

    role = await _order_role(order, current_user)
    target = coerce_state(state_update.state)
    allowed = ROLE_TRANSITIONS.get(role or "", set())
    if target not in allowed:
        raise HTTPException(
            status_code=403,
            detail=f"You are not allowed to move this order to {target.value}",
        )

    try:
        order = await OrderService.transition_state(
            order_id,
            target,
            actor_id=str(current_user.id),
            reason=f"{role}_state_update",
            # A driver may only advance the order they are actually carrying.
            require_driver_id=str(current_user.id) if role == "driver" else None,
        )
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")

        return _to_response(order)
    except OrderConflict as e:
        raise HTTPException(status_code=409, detail=str(e))
    except InvalidStateTransition as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/consumer/{consumer_id}", response_model=List[OrderResponse])
async def get_consumer_orders(
    consumer_id: str,
    current_user: User = Depends(get_current_user),
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    """The consumer's own orders, newest first."""
    # Ownership check: consumers may only list their own orders
    require_self(
        current_user, consumer_id, detail="Not authorized to view these orders"
    )
    limit, offset = _paged(limit, offset)
    orders = (
        await Order.find(Order.consumer_id == consumer_id)
        .sort(-Order.created_at)
        .skip(offset)
        .limit(limit)
        .to_list()
    )
    return [_to_response(o) for o in orders]

@router.get("/merchant/{merchant_id}", response_model=List[OrderResponse])
async def get_merchant_orders(
    merchant_id: str,
    current_user: User = Depends(get_current_user),
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    """Orders across every restaurant this merchant account owns, newest first."""
    # Ownership check: merchants may only list orders for their own account
    require_self(
        current_user, merchant_id, detail="Not authorized to view these orders"
    )
    # The merchant_id passed here is the User ID (from auth/me)
    # But Orders are linked to Restaurant IDs (Order.merchant_id = Restaurant.id)
    # So we must find all restaurants owned by this merchant first.
    from app.catalog.models import Restaurant

    restaurants = await Restaurant.find(Restaurant.merchant_id == merchant_id).to_list()
    restaurant_ids = [str(r.id) for r in restaurants]

    if not restaurant_ids:
        return []

    limit, offset = _paged(limit, offset)
    # Query orders for any of the merchant's restaurants
    orders = (
        await Order.find({"merchant_id": {"$in": restaurant_ids}})
        .sort(-Order.created_at)
        .skip(offset)
        .limit(limit)
        .to_list()
    )

    return [_to_response(o) for o in orders]

@router.post("/{order_id}/confirm-delivery")
async def consumer_confirm_delivery(
    order_id: str,
    current_user: User = Depends(get_current_user)
):
    """Consumer confirms that their order has been delivered."""
    from app.order.models import Order

    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    await require_order_consumer(
        order, current_user, detail="Not authorized to confirm this order"
    )

    # Only allow confirmation when driver has arrived or is very close
    allowed_states = {OrderState.ARRIVED_AT_CUSTOMER.value, OrderState.PICKED_UP.value}
    current_state = _state_str(order.state)
    if current_state not in allowed_states:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot confirm delivery in state {current_state}. Driver must be en route or arrived."
        )

    try:
        order = await OrderService.transition_state(
            order_id,
            OrderState.DELIVERED,
            str(current_user.id),
            reason="consumer_confirmed_delivery",
        )
    except OrderConflict as e:
        raise HTTPException(status_code=409, detail=str(e))
    except InvalidStateTransition as e:
        raise HTTPException(status_code=400, detail=str(e))

    return {"status": "delivered", "order_id": order_id, "message": "Delivery confirmed successfully"}


@router.get("/driver/active", response_model=List[OrderResponse])
async def get_driver_active_orders(
    current_user: User = Depends(get_current_user),
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
):
    """Every delivery the authenticated driver is currently carrying."""
    driver_id = str(current_user.id)
    limit, _ = _paged(limit, 0)

    orders = (
        await Order.find(
            Order.driver_id == driver_id,
            {"state": {"$in": [s.value for s in ACTIVE_DRIVER_STATES]}},
        )
        .sort(-Order.created_at)
        .limit(limit)
        .to_list()
    )

    return [_to_response(o) for o in orders]
