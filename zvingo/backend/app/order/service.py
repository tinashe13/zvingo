import asyncio
from datetime import datetime
from app.time_utils import utc_now
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
        pickup = order_in.pickup
        if pickup is None or pickup.is_null_island:
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
                    pickup = restaurant.location
                    logger.info(
                        "Resolved pickup from restaurant",
                        restaurant_id=str(restaurant.id),
                        restaurant=restaurant.name,
                        pickup_lat=pickup.lat,
                        pickup_lng=pickup.lng,
                    )
            except Exception as e:
                logger.error(
                    "Failed to resolve restaurant pickup location",
                    merchant_id=order_in.merchant_id,
                    error=str(e),
                )
                # Fall through with None — dispatch will reject

        # Hard validation: prevent orders with unresolved pickup location
        if pickup is None or pickup.is_null_island:
            raise ValueError(
                "Pickup location unresolved. Provide a pickup Location or "
                "set a valid restaurant location."
            )

        if order_in.dropoff is None or order_in.dropoff.is_null_island:
            raise ValueError(
                "Dropoff location unresolved. Provide a dropoff Location "
                "with valid coordinates."
            )

        dropoff = order_in.dropoff

        order = Order(
            merchant_id=order_in.merchant_id,
            consumer_id=order_in.consumer_id,
            items=[i.model_dump() for i in order_in.items],
            total_amount=order_in.total_amount,
            pickup_location=pickup,
            dropoff_location=dropoff,
            idempotency_key=order_in.idempotency_key,
            tip_amount=order_in.tip_amount or 0.0,
            events=[OrderEvent(state=OrderState.CREATED)]
        )

        # Auto-calculate delivery fee using $5/5km block formula if not provided
        if not order_in.delivery_fee or order_in.delivery_fee <= 0:
            from app.finance.fee_calculator import calculate_delivery_fee_from_coords
            gross_fee, _, _ = calculate_delivery_fee_from_coords(
                pickup.lat, pickup.lng, dropoff.lat, dropoff.lng
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
            pickup.lat,
            pickup.lng
        ))
        
        return order

    @staticmethod
    async def transition_state(
        order_id: str,
        new_state: OrderState,
        actor_id: Optional[str] = None,
        driver_id: Optional[str] = None,
    ) -> Optional[Order]:
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
        order.updated_at = utc_now()
        # Driver assignment is explicit: only when a driver accepts an offer
        # (or otherwise takes the order) is `driver_id` set. The `actor_id`
        # is purely an audit-trail identifier and must never be conflated with
        # the driver.
        if driver_id is not None and new_state == OrderState.ACCEPTED:
            order.driver_id = driver_id

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
