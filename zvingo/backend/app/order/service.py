import asyncio
from datetime import datetime
from typing import Optional
from app.order.models import Order, OrderEvent
from app.order.schemas import OrderCreate
from app.order.state_machine import OrderState, validate_transition
import structlog

logger = structlog.get_logger()

class OrderService:
    @staticmethod
    async def create_order(order_in: OrderCreate) -> Order:
        # Idempotency: if a key is provided, check for existing order
        if order_in.idempotency_key:
            existing = await Order.find_one(Order.idempotency_key == order_in.idempotency_key)
            if existing:
                logger.info("Duplicate order blocked by idempotency key", key=order_in.idempotency_key)
                return existing

        # Resolve pickup location from restaurant record if not provided by client
        pickup_lat = order_in.pickup_lat
        pickup_lng = order_in.pickup_lng
        if pickup_lat == 0.0 and pickup_lng == 0.0:
            try:
                from app.catalog.models import Restaurant
                # First try: merchant_id may actually be a restaurant document id.
                restaurant = await Restaurant.get(order_in.merchant_id)
                # Fallback: resolve by merchant_id (common case).
                if restaurant is None:
                    restaurant = await Restaurant.find_one(
                        Restaurant.merchant_id == order_in.merchant_id
                    )
                if restaurant and restaurant.location:
                    # restaurant.location is a Pydantic Location model, not a dict
                    coords = restaurant.location.coordinates
                    pickup_lng, pickup_lat = coords[0], coords[1]
                    logger.info(
                        "Resolved pickup from restaurant",
                        restaurant_id=str(restaurant.id),
                        restaurant=restaurant.name,
                        pickup_lat=pickup_lat,
                        pickup_lng=pickup_lng,
                    )
            except Exception as e:
                logger.error(
                    "Failed to resolve restaurant pickup location",
                    merchant_id=order_in.merchant_id,
                    error=str(e),
                )
                # Fall through with 0,0 — dispatch will reject

        # Hard validation: prevent orders with unresolved pickup location
        if pickup_lat == 0.0 and pickup_lng == 0.0:
            raise ValueError(
                "Pickup location unresolved. Provide pickup_lat/pickup_lng or "
                "set a valid restaurant location."
            )

        order = Order(
            merchant_id=order_in.merchant_id,
            consumer_id=order_in.consumer_id,
            items=[i.model_dump() for i in order_in.items],
            total_amount=order_in.total_amount,
            pickup_location={"type": "Point", "coordinates": [pickup_lng, pickup_lat]},
            dropoff_location={"type": "Point", "coordinates": [order_in.dropoff_lng, order_in.dropoff_lat]},
            idempotency_key=order_in.idempotency_key,
            tip_amount=order_in.tip_amount or 0.0,
            events=[OrderEvent(state=OrderState.CREATED)]
        )

        # Auto-calculate delivery fee using $5/5km block formula if not provided
        if not order_in.delivery_fee or order_in.delivery_fee <= 0:
            from app.finance.fee_calculator import calculate_delivery_fee_from_coords
            gross_fee, _, _ = calculate_delivery_fee_from_coords(
                pickup_lat, pickup_lng, order_in.dropoff_lat, order_in.dropoff_lng
            )
            order.delivery_fee = gross_fee
        else:
            order.delivery_fee = order_in.delivery_fee

        await order.insert()
        
        # Trigger Dispatch
        from app.dispatch.service import dispatch_service
        from app.notification.service import notification_service

        # Notify Merchant
        await notification_service.notify_merchant(order.merchant_id, str(order.id))

        # Run dispatch in background to not block response
        asyncio.create_task(dispatch_service.dispatch_order(
            str(order.id), 
            order.pickup_location["coordinates"][1], 
            order.pickup_location["coordinates"][0]
        ))
        
        return order

    @staticmethod
    async def transition_state(order_id: str, new_state: OrderState, actor_id: Optional[str] = None) -> Optional[Order]:
        order = await Order.get(order_id)
        if not order:
            logger.warn("Order not found", order_id=order_id)
            return None

        logger.info("Attempting state transition", order_id=order_id, current_state=order.state, new_state=new_state, actor=actor_id)

        try:
            validate_transition(order.state, new_state)
        except Exception as e:
            logger.error("State transition validation failed", order_id=order_id, current_state=order.state, new_state=new_state, error=str(e))
            raise

        order.state = new_state
        order.updated_at = datetime.utcnow()
        if actor_id and new_state == OrderState.ACCEPTED:
            order.driver_id = actor_id

        order.events.append(OrderEvent(state=new_state, actor_id=actor_id))
        await order.save()

        logger.info("Order state changed successfully", order_id=order_id, state=new_state, actor=actor_id)

        # Notify consumer of state change (real-time update)
        if order.consumer_id:
            from app.notification.service import notification_service
            event_map = {
                OrderState.ACCEPTED: "order_accepted",
                OrderState.ARRIVED_AT_MERCHANT: "arrived_merchant",
                OrderState.PICKED_UP: "picked_up",
                OrderState.ARRIVED_AT_CUSTOMER: "arrived_customer",
                OrderState.DELIVERED: "delivered",
                OrderState.CANCELLED: "cancelled",
            }
            event_name = event_map.get(new_state, "status_update")
            asyncio.create_task(
                notification_service.notify_consumer(
                    order.consumer_id,
                    order_id,
                    event_name,
                    {"state": new_state.value, "driver_id": order.driver_id}
                )
            )

        return order
