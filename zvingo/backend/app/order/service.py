import asyncio
import uuid
from datetime import datetime
from app.time_utils import utc_now
from typing import List, Optional, Tuple
from app.order.models import Order, OrderEvent
from app.order.schemas import CheckoutCreate, OrderCreate
from app.order.state_machine import OrderState, validate_transition
from app.observability import metrics
import structlog

logger = structlog.get_logger()

class OrderService:
    @staticmethod
    async def create_order(
        order_in: OrderCreate,
        group_id: Optional[str] = None,
        promo_override: Optional[Tuple[float, bool]] = None,
    ) -> Order:
        """Create a single order.

        `group_id` links sibling orders from one multi-restaurant checkout.
        `promo_override` supplies an already-validated (discount, free_delivery)
        pair — the checkout flow uses it so a promo is validated, split, and
        redeemed exactly once across the whole basket instead of per order.
        """
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

        # ── Promo discount ──────────────────────────────
        discount = 0.0
        free_delivery = False
        if promo_override is not None:
            discount, free_delivery = promo_override
        elif order_in.promo_code:
            from app.catalog.promotion_service import (
                validate_and_compute,
                PromotionError,
            )
            try:
                discount, free_delivery = await validate_and_compute(
                    order_in.promo_code,
                    order_in.consumer_id,
                    order_in.total_amount,
                    order_in.items,
                )
            except PromotionError as e:
                raise ValueError(str(e))

        order = Order(
            merchant_id=order_in.merchant_id,
            consumer_id=order_in.consumer_id,
            items=[i.model_dump() for i in order_in.items],
            total_amount=order_in.total_amount,
            pickup_location=pickup,
            dropoff_location=dropoff,
            idempotency_key=order_in.idempotency_key,
            group_id=group_id,
            tip_amount=order_in.tip_amount or 0.0,
            is_pickup=order_in.is_pickup,
            scheduled_at=order_in.scheduled_at,
            promo_code=order_in.promo_code,
            discount_amount=discount,
            events=[OrderEvent(state=OrderState.CREATED)]
        )

        # Auto-calculate delivery fee using $5/5km block formula if not provided.
        # Self-pickup has no delivery fee; free-delivery promos waive it.
        if order_in.is_pickup or free_delivery:
            order.delivery_fee = 0.0
        elif not order_in.delivery_fee or order_in.delivery_fee <= 0:
            from app.finance.fee_calculator import calculate_delivery_fee_from_coords
            gross_fee, _, _ = calculate_delivery_fee_from_coords(
                pickup.lat, pickup.lng, dropoff.lat, dropoff.lng
            )
            order.delivery_fee = gross_fee
        else:
            order.delivery_fee = order_in.delivery_fee

        await order.insert()

        if order_in.is_pickup:
            kind = "pickup"
        elif order_in.scheduled_at is not None:
            kind = "scheduled"
        else:
            kind = "delivery"
        metrics.orders_total.inc(kind=kind)

        # Record promo usage after the order is durably stored. With an
        # override the caller owns redemption, so it is recorded once there.
        if order_in.promo_code and promo_override is None:
            from app.catalog.promotion_service import record_redemption
            await record_redemption(order_in.promo_code, order_in.consumer_id)

        # Trigger Dispatch
        from app.dispatch.service import dispatch_service
        from app.notification.service import notification_service

        # Notify Merchant
        await notification_service.notify_merchant(order.merchant_id, str(order.id))

        # Skip immediate dispatch for self-pickup (no driver) and scheduled
        # orders (ScheduledOrderService releases those as their slot nears).
        if order_in.is_pickup or (
            order_in.scheduled_at is not None and order_in.scheduled_at > utc_now()
        ):
            return order

        # Run dispatch in background to not block response
        asyncio.create_task(dispatch_service.dispatch_order(
            str(order.id),
            pickup.lat,
            pickup.lng
        ))

        return order

    @staticmethod
    def split_discount(discount: float, weights: List[float]) -> List[float]:
        """Split a discount across baskets in proportion to their subtotals.

        Cent-rounding remainders land on the largest basket so the parts always
        sum back to the original discount.
        """
        if discount <= 0 or not weights:
            return [0.0] * len(weights)

        total = sum(weights)
        if total <= 0:
            # Degenerate case (all-zero baskets) — split evenly.
            share = round(discount / len(weights), 2)
            parts = [share] * len(weights)
        else:
            parts = [round(discount * (w / total), 2) for w in weights]

        remainder = round(discount - sum(parts), 2)
        if remainder:
            largest = max(range(len(parts)), key=lambda i: weights[i])
            parts[largest] = round(parts[largest] + remainder, 2)
        return parts

    @staticmethod
    async def create_checkout(
        checkout: CheckoutCreate, consumer_id: str
    ) -> Tuple[str, List[Order], float]:
        """Create one order per restaurant from a multi-restaurant cart.

        Returns (group_id, orders, discount_total). Any promo code is validated
        once against the combined subtotal, split across the baskets in
        proportion to their value, and redeemed once. A free-delivery promo
        waives the fee on the first basket only — one promo, one waived fee.

        Note that creation is not atomic: if a later basket is rejected (an
        unresolvable pickup location, say) the earlier baskets are already
        created and the caller sees the error. Passing `idempotency_key` makes a
        retry safe — each basket derives its own key, so the orders that already
        exist are returned rather than duplicated.
        """
        group_id = uuid.uuid4().hex

        discount_total = 0.0
        free_delivery = False
        if checkout.promo_code:
            from app.catalog.promotion_service import (
                validate_and_compute,
                PromotionError,
            )
            all_items = [item for basket in checkout.baskets for item in basket.items]
            try:
                discount_total, free_delivery = await validate_and_compute(
                    checkout.promo_code, consumer_id, checkout.subtotal, all_items
                )
            except PromotionError as e:
                raise ValueError(str(e))

        shares = OrderService.split_discount(
            discount_total, [b.subtotal for b in checkout.baskets]
        )

        # Build every OrderCreate up front so schema-level problems surface
        # before any order is written.
        payloads = []
        for index, basket in enumerate(checkout.baskets):
            basket_key = (
                f"{checkout.idempotency_key}:{basket.merchant_id}"
                if checkout.idempotency_key
                else None
            )
            payloads.append(
                (
                    OrderCreate(
                        merchant_id=basket.merchant_id,
                        consumer_id=consumer_id,
                        items=basket.items,
                        total_amount=basket.subtotal,
                        pickup=basket.pickup,
                        dropoff=checkout.dropoff,
                        delivery_instructions=checkout.delivery_instructions,
                        # The tip is for the whole basket; attach it to the
                        # first order so it is not multiplied per restaurant.
                        tip_amount=checkout.tip_amount if index == 0 else 0.0,
                        delivery_fee=basket.delivery_fee or 0.0,
                        service_fee=basket.service_fee or 0.0,
                        tax_amount=basket.tax_amount or 0.0,
                        idempotency_key=basket_key,
                        is_pickup=basket.is_pickup,
                        scheduled_at=checkout.scheduled_at,
                        promo_code=checkout.promo_code,
                    ),
                    (shares[index], free_delivery and index == 0),
                )
            )

        orders = []
        for order_in, override in payloads:
            orders.append(
                await OrderService.create_order(
                    order_in, group_id=group_id, promo_override=override
                )
            )

        logger.info(
            "Multi-restaurant checkout created",
            group_id=group_id,
            consumer_id=consumer_id,
            basket_count=len(orders),
            discount_total=discount_total,
        )

        if checkout.promo_code:
            from app.catalog.promotion_service import record_redemption
            await record_redemption(checkout.promo_code, consumer_id)

        return group_id, orders, discount_total

    @staticmethod
    async def reorder(order_id: str, consumer_id: str) -> Optional[Order]:
        """Clone a previous order's items into a new order for the consumer."""
        original = await Order.get(order_id)
        if not original:
            return None
        if original.consumer_id != consumer_id:
            raise ValueError("Not your order to reorder")

        if not original.items:
            raise ValueError("Cannot reorder an empty order")

        new_order = Order(
            merchant_id=original.merchant_id,
            consumer_id=consumer_id,
            items=[dict(i) if isinstance(i, dict) else i.model_dump() for i in original.items],
            total_amount=original.total_amount,
            pickup_location=original.pickup_location,
            dropoff_location=original.dropoff_location,
            tip_amount=original.tip_amount,
            delivery_fee=original.delivery_fee,
            service_fee=original.service_fee,
            tax_amount=original.tax_amount,
            events=[OrderEvent(state=OrderState.CREATED)],
        )
        await new_order.insert()
        metrics.orders_total.inc(kind="reorder")

        from app.notification.service import notification_service
        await notification_service.notify_merchant(new_order.merchant_id, str(new_order.id))

        from app.dispatch.service import dispatch_service
        asyncio.create_task(dispatch_service.dispatch_order(
            str(new_order.id),
            new_order.pickup_location.lat if new_order.pickup_location else 0,
            new_order.pickup_location.lng if new_order.pickup_location else 0,
        ))

        return new_order

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
        metrics.order_transitions_total.inc(state=new_state.value)

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
