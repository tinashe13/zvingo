"""Order lifecycle service.

The only place an order's state is allowed to change. Every transition is
validated against the state machine and then written with a **conditional
update** (compare-and-set on the state the caller validated against), so two
concurrent writers can never both succeed. See `transition_state`.
"""

import asyncio
import uuid
from datetime import datetime
from app.time_utils import utc_now
from typing import Iterable, List, Optional, Sequence, Tuple
from app.order.models import Order, OrderEvent
from app.order.schemas import CheckoutCreate, OrderCreate
from app.order.state_machine import (
    ACTIVE_DRIVER_STATES,
    RELEASABLE_STATES,
    InvalidStateTransition,
    OrderConflict,
    OrderState,
    coerce_state,
    is_driver_claim,
    state_aliases,
    validate_transition,
)
from app.observability import metrics
import structlog

logger = structlog.get_logger()

#: A conditional update that loses its race is re-read and retried this many
#: times before the caller is told the order moved underneath them. Three is
#: enough for any realistic contention (at most a handful of actors touch one
#: order) while still terminating.
MAX_TRANSITION_ATTEMPTS = 3

#: Ceiling on the driver-load lookup that feeds dispatch scoring. Bounded so a
#: pathological data state cannot pull an unbounded result set into memory.
MAX_LOAD_LOOKUP = 500

#: Notification event names published to the consumer per destination state.
_CONSUMER_EVENTS = {
    OrderState.ACCEPTED: "order_accepted",
    OrderState.ARRIVED_AT_MERCHANT: "arrived_merchant",
    OrderState.PICKED_UP: "picked_up",
    OrderState.ARRIVED_AT_CUSTOMER: "arrived_customer",
    OrderState.DELIVERED: "delivered",
    OrderState.CANCELLED: "cancelled",
}


def _order_collection():
    """The live Motor collection for orders, or None when there isn't one.

    Returns None when Beanie has not been initialised or `Order` has been
    substituted by a test double. Callers then fall back to a plain document
    save, which is safe precisely because those contexts have no concurrency.
    """
    try:
        collection = Order.get_motor_collection()
    except Exception:
        return None
    if collection is None or not hasattr(collection, "find_one_and_update"):
        return None
    return collection


def _document_id(order_id):
    """Coerce an order id to the type stored in `_id`."""
    try:
        from bson import ObjectId

        return ObjectId(str(order_id))
    except Exception:
        return order_id


def _event_document(event: OrderEvent) -> dict:
    """A plain BSON-safe dict for `$push`-ing an audit event."""
    return {
        "state": coerce_state(event.state).value,
        "timestamp": event.timestamp,
        "actor_id": event.actor_id,
        "reason": event.reason,
        "metadata": event.metadata or {},
    }


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
                resolve_restaurant_id,
                PromotionError,
            )
            try:
                discount, free_delivery = await validate_and_compute(
                    order_in.promo_code,
                    order_in.consumer_id,
                    order_in.total_amount,
                    order_in.items,
                    restaurant_id=await resolve_restaurant_id(order_in.merchant_id),
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
            events=[OrderEvent(state=OrderState.CREATED, reason="order_created")],
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
                resolve_restaurant_id,
                PromotionError,
            )
            all_items = [item for basket in checkout.baskets for item in basket.items]
            # A restaurant-scoped promo only applies when every basket in the
            # checkout resolves to that same restaurant — mixed baskets pass
            # None through, which compute_discount rejects for a scoped promo.
            basket_restaurant_ids = {
                await resolve_restaurant_id(b.merchant_id) for b in checkout.baskets
            }
            restaurant_id = (
                next(iter(basket_restaurant_ids))
                if len(basket_restaurant_ids) == 1
                else None
            )
            try:
                discount_total, free_delivery = await validate_and_compute(
                    checkout.promo_code,
                    consumer_id,
                    checkout.subtotal,
                    all_items,
                    restaurant_id=restaurant_id,
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
        """Clone a previous order's items into a new order for the consumer.

        The *items* are carried over; everything price- and location-derived is
        recomputed, because a fee quoted weeks ago must not be charged today and
        the restaurant may have moved. A self-pickup order is re-created as a
        self-pickup order and is not dispatched to a driver.
        """
        original = await Order.get(order_id)
        if not original:
            return None
        if original.consumer_id != consumer_id:
            raise ValueError("Not your order to reorder")

        if not original.items:
            raise ValueError("Cannot reorder an empty order")

        pickup = await OrderService._resolve_pickup(original)
        dropoff = original.dropoff_location
        if dropoff is None or dropoff.is_null_island:
            raise ValueError(
                "The original order has no delivery address. Place this order "
                "from the cart so a delivery address can be chosen."
            )
        is_pickup_only = bool(getattr(original, "is_pickup", False))
        if not is_pickup_only and (pickup is None or pickup.is_null_island):
            # Creating an order dispatch can never act on just strands the
            # consumer, so refuse it here the way create_order does.
            raise ValueError(
                "This restaurant's pickup location is unavailable, so the order "
                "cannot be placed right now."
            )

        is_pickup = is_pickup_only
        new_order = Order(
            merchant_id=original.merchant_id,
            consumer_id=consumer_id,
            items=[dict(i) if isinstance(i, dict) else i.model_dump() for i in original.items],
            total_amount=original.total_amount,
            pickup_location=pickup,
            dropoff_location=dropoff,
            delivery_instructions=getattr(original, "delivery_instructions", None),
            tip_amount=getattr(original, "tip_amount", 0.0) or 0.0,
            delivery_fee=0.0 if is_pickup else (getattr(original, "delivery_fee", 0.0) or 0.0),
            service_fee=original.service_fee,
            tax_amount=original.tax_amount,
            is_pickup=is_pickup,
            events=[OrderEvent(state=OrderState.CREATED, actor_id=consumer_id,
                               reason="reorder", metadata={"source_order_id": str(order_id)})],
        )

        # Re-quote the delivery fee against today's distance rather than
        # inheriting a stale one.
        if not is_pickup and pickup is not None and not pickup.is_null_island:
            try:
                from app.finance.fee_calculator import calculate_delivery_fee_from_coords

                gross_fee, _, _ = calculate_delivery_fee_from_coords(
                    pickup.lat, pickup.lng, dropoff.lat, dropoff.lng
                )
                new_order.delivery_fee = gross_fee
            except Exception as e:  # pragma: no cover - defensive
                logger.warning("Reorder fee re-quote failed", order_id=str(order_id), error=str(e))

        await new_order.insert()
        metrics.orders_total.inc(kind="reorder")

        from app.notification.service import notification_service
        await notification_service.notify_merchant(new_order.merchant_id, str(new_order.id))

        # Self-pickup never involves a driver, so it is never dispatched.
        if is_pickup:
            return new_order

        from app.dispatch.service import dispatch_service
        asyncio.create_task(dispatch_service.dispatch_order(
            str(new_order.id),
            pickup.lat if pickup else 0,
            pickup.lng if pickup else 0,
        ))

        return new_order

    @staticmethod
    async def _resolve_pickup(order):
        """The order's pickup point, re-resolved from the restaurant if unset."""
        pickup = getattr(order, "pickup_location", None)
        if pickup is not None and not pickup.is_null_island:
            return pickup
        try:
            from app.catalog.models import Restaurant

            restaurant = await Restaurant.get(order.merchant_id)
            if restaurant is None:
                restaurant = await Restaurant.find_one(
                    Restaurant.merchant_id == order.merchant_id
                )
            if restaurant and restaurant.location:
                return restaurant.location
        except Exception as e:
            logger.warning(
                "Could not resolve pickup location",
                order_id=str(getattr(order, "id", None)),
                error=str(e),
            )
        return pickup

    # ──────────────────────────────────────────────────────────────
    # State transitions
    # ──────────────────────────────────────────────────────────────

    @staticmethod
    async def transition_state(
        order_id: str,
        new_state: OrderState,
        actor_id: Optional[str] = None,
        driver_id: Optional[str] = None,
        *,
        reason: Optional[str] = None,
        require_driver_id: Optional[str] = None,
        expected_states: Optional[Iterable] = None,
    ) -> Optional[Order]:
        """Move an order to `new_state`, atomically.

        The move is validated against the state machine and then written with a
        conditional update that also matches on the state we validated against.
        If another actor changed the order in between, the write matches nothing
        and we re-read and re-validate. Two drivers accepting the same order,
        or a merchant cancelling while a driver accepts, therefore produce one
        winner and one :class:`OrderConflict` — never a corrupt order.

        Args:
            actor_id: the principal to record in the audit trail. Never used to
                assign the order; see `driver_id`.
            driver_id: assign this driver as part of the move. Only honoured for
                a move to ACCEPTED, and only while the order is unassigned (or
                already assigned to this same driver, making retries idempotent).
            reason: machine-readable cause recorded on the audit event.
            require_driver_id: refuse the move unless the order is currently
                assigned to this driver. Drivers reporting progress on an order
                pass their own id, so one driver cannot advance another's job.
            expected_states: refuse the move unless the order is currently in one
                of these states, over and above the state machine's rules.
        """
        target = coerce_state(new_state)
        expected = (
            frozenset(coerce_state(s) for s in expected_states)
            if expected_states is not None
            else None
        )

        for attempt in range(MAX_TRANSITION_ATTEMPTS):
            order = await Order.get(order_id)
            if not order:
                logger.warning("Order not found", order_id=order_id)
                return None

            current = coerce_state(order.state)
            logger.info(
                "Attempting state transition",
                order_id=order_id,
                current_state=current.value,
                new_state=target.value,
                actor=actor_id,
            )

            if expected is not None and current not in expected:
                raise OrderConflict(
                    f"Order is {current.value}, expected "
                    f"{' or '.join(sorted(s.value for s in expected))}"
                )

            if require_driver_id is not None and str(
                order.driver_id or ""
            ) != str(require_driver_id):
                raise OrderConflict("This order is not assigned to you")

            assign_driver = driver_id if target is OrderState.ACCEPTED and driver_id else None

            # The single permitted self-transition: a driver claiming an order a
            # merchant already confirmed into ACCEPTED, or retrying their own
            # accept. Everything else goes through the table.
            if not (assign_driver and is_driver_claim(current, target, assign_driver)):
                try:
                    validate_transition(current, target)
                except InvalidStateTransition as e:
                    logger.warning(
                        "State transition validation failed",
                        order_id=order_id,
                        current_state=current.value,
                        new_state=target.value,
                        error=str(e),
                    )
                    raise

            if assign_driver and order.driver_id not in (None, "", assign_driver):
                raise OrderConflict("This order has already been taken by another driver")

            event = OrderEvent(
                state=target,
                actor_id=actor_id,
                reason=reason,
                metadata={"from": current.value},
            )
            applied = await OrderService._compare_and_set(
                order, current, target, event, assign_driver=assign_driver,
                require_driver_id=require_driver_id,
            )
            if not applied:
                logger.info(
                    "State transition lost a race, retrying",
                    order_id=order_id,
                    attempt=attempt + 1,
                    expected_state=current.value,
                )
                continue

            metrics.order_transitions_total.inc(state=target.value)
            logger.info(
                "Order state changed successfully",
                order_id=order_id,
                state=target.value,
                actor=actor_id,
                reason=reason,
            )

            OrderService._notify_consumer(order, order_id, target)
            return order

        raise OrderConflict(
            "The order changed while this update was being applied. Please retry."
        )

    @staticmethod
    async def _compare_and_set(
        order,
        current: OrderState,
        target: OrderState,
        event: OrderEvent,
        *,
        assign_driver: Optional[str] = None,
        require_driver_id: Optional[str] = None,
    ) -> bool:
        """Write the transition only while the order is still in `current`.

        Returns True when the write landed (and mirrors it onto the in-memory
        document), False when another writer got there first.
        """
        now = utc_now()
        collection = _order_collection()

        if collection is None:
            # No live Mongo collection: Beanie is not initialised or `Order` is
            # a test double. There is no concurrent writer to guard against, so
            # a plain save is correct.
            OrderService._apply_in_memory(order, target, event, now, assign_driver)
            await order.save()
            return True

        criteria = {
            "_id": _document_id(getattr(order, "id", None)),
            "state": {"$in": state_aliases(current)},
        }
        if require_driver_id is not None:
            criteria["driver_id"] = require_driver_id
        if assign_driver is not None:
            # Claim only an unassigned order — or one already claimed by this
            # same driver, which keeps a retried accept idempotent.
            criteria["$or"] = [
                {"driver_id": None},
                {"driver_id": {"$exists": False}},
                {"driver_id": assign_driver},
            ]

        changes = {"state": target.value, "updated_at": now}
        if assign_driver is not None:
            changes["driver_id"] = assign_driver
        if target is OrderState.ACCEPTED:
            # The offer has been answered; stop advertising it.
            changes["offered_driver_id"] = None
            changes["offer_expires_at"] = None

        update = {"$set": changes, "$push": {"events": _event_document(event)}}

        try:
            result = await collection.find_one_and_update(criteria, update)
        except Exception as e:
            logger.error(
                "Conditional order update failed",
                order_id=str(getattr(order, "id", None)),
                error=str(e),
            )
            raise

        if result is None:
            return False

        OrderService._apply_in_memory(order, target, event, now, assign_driver)
        return True

    @staticmethod
    def _apply_in_memory(order, target, event, now, assign_driver):
        """Mirror a persisted transition onto the in-memory document."""
        order.state = target
        order.updated_at = now
        if assign_driver is not None:
            order.driver_id = assign_driver
        if target is OrderState.ACCEPTED:
            order.offered_driver_id = None
            order.offer_expires_at = None
        events = getattr(order, "events", None)
        if events is None:
            order.events = [event]
        else:
            events.append(event)

    @staticmethod
    def _notify_consumer(order, order_id: str, target: OrderState) -> None:
        """Push the state change to the consumer's realtime channel."""
        if not getattr(order, "consumer_id", None):
            return
        from app.notification.service import notification_service

        event_name = _CONSUMER_EVENTS.get(target, "status_update")
        asyncio.create_task(
            notification_service.notify_consumer(
                order.consumer_id,
                order_id,
                event_name,
                {"state": target.value, "driver_id": order.driver_id},
            )
        )

    @staticmethod
    async def release_driver(
        order_id: str,
        driver_id: str,
        actor_id: Optional[str] = None,
        reason: str = "driver_released",
    ) -> Optional[Order]:
        """Take a pre-pickup order off a driver and return it to the pool.

        This is deliberately *not* a state-machine transition: walking an order
        backwards through `PUT /orders/{id}/state` must stay impossible. It is a
        single conditional update that only fires while the order is still
        assigned to this driver and still in a
        :data:`~app.order.state_machine.RELEASABLE_STATES` state — once the food
        is picked up the order can only be completed or cancelled by a human.

        Returns the order when released, None when there was nothing to release.
        """
        order = await Order.get(order_id)
        if not order:
            return None
        current = coerce_state(order.state)
        if order.driver_id != driver_id or current not in RELEASABLE_STATES:
            return None

        now = utc_now()
        event = OrderEvent(
            state=OrderState.CREATED,
            actor_id=actor_id or driver_id,
            reason=reason,
            metadata={"from": current.value, "released_driver_id": driver_id},
        )
        collection = _order_collection()
        changes = {
            "state": OrderState.CREATED.value,
            "driver_id": None,
            "updated_at": now,
            "offered_driver_id": None,
            "offer_expires_at": None,
        }

        if collection is None:
            order.state = OrderState.CREATED
            order.driver_id = None
            order.updated_at = now
            order.offered_driver_id = None
            order.offer_expires_at = None
            (order.events if getattr(order, "events", None) is not None else []).append(event)
            await order.save()
        else:
            result = await collection.find_one_and_update(
                {
                    "_id": _document_id(order.id),
                    "driver_id": driver_id,
                    "state": {"$in": state_aliases(current)},
                },
                {
                    "$set": changes,
                    "$push": {"events": _event_document(event)},
                    # The driver who walked away must not be re-offered the same
                    # order immediately.
                    "$addToSet": {"declined_by": driver_id},
                },
            )
            if result is None:
                return None
            order.state = OrderState.CREATED
            order.driver_id = None
            order.updated_at = now

        metrics.order_transitions_total.inc(state=OrderState.CREATED.value)
        logger.info(
            "Driver released from order",
            order_id=str(order_id),
            driver_id=driver_id,
            from_state=current.value,
            reason=reason,
        )
        return order

    # ──────────────────────────────────────────────────────────────
    # Dispatch bookkeeping
    # ──────────────────────────────────────────────────────────────

    @staticmethod
    async def record_offer(order_id: str, driver_id: str, expires_at: datetime) -> None:
        """Record that `driver_id` currently holds the offer for this order.

        Durable (unlike the Redis offer lock) so a backend restart cannot cause
        the same order to be offered to a second driver while the first is still
        deciding, and so the driver's sync feed can find the offer addressed to
        them without leaking every open order on the platform.
        """
        collection = _order_collection()
        if collection is None:
            return
        try:
            await collection.update_one(
                {"_id": _document_id(order_id)},
                {
                    "$set": {
                        "offered_driver_id": driver_id,
                        "offer_expires_at": expires_at,
                    },
                    "$addToSet": {"offered_to": driver_id},
                },
            )
        except Exception as e:
            logger.warning("Could not record offer", order_id=str(order_id), error=str(e))

    @staticmethod
    async def record_decline(order_id: str, driver_id: str) -> None:
        """Record a decline so the order is never re-offered to this driver."""
        collection = _order_collection()
        if collection is None:
            return
        try:
            await collection.update_one(
                {"_id": _document_id(order_id), "offered_driver_id": driver_id},
                {"$set": {"offered_driver_id": None, "offer_expires_at": None}},
            )
            await collection.update_one(
                {"_id": _document_id(order_id)},
                {"$addToSet": {"declined_by": driver_id}},
            )
        except Exception as e:
            logger.warning("Could not record decline", order_id=str(order_id), error=str(e))

    @staticmethod
    async def clear_expired_offer(order_id: str) -> None:
        """Drop a lapsed offer so the order can be offered to the next driver."""
        collection = _order_collection()
        if collection is None:
            return
        try:
            await collection.update_one(
                {"_id": _document_id(order_id)},
                {"$set": {"offered_driver_id": None, "offer_expires_at": None}},
            )
        except Exception as e:
            logger.warning("Could not clear offer", order_id=str(order_id), error=str(e))

    @staticmethod
    async def reset_offer_history(order_id: str) -> None:
        """Forget who has already been offered this order.

        Called when the candidate pool is exhausted, so the next retry round
        starts from a clean slate instead of never offering to anybody again.
        Declines are kept — a driver who said no should not be nagged.
        """
        collection = _order_collection()
        if collection is None:
            return
        try:
            await collection.update_one(
                {"_id": _document_id(order_id)},
                {"$set": {"offered_to": [], "offered_driver_id": None,
                          "offer_expires_at": None}},
            )
        except Exception as e:
            logger.warning(
                "Could not reset offer history", order_id=str(order_id), error=str(e)
            )

    @staticmethod
    async def claim_scheduled_release(order, pickup=None) -> bool:
        """Claim a scheduled order for dispatch. True only for the winner.

        Several workers can be polling for due orders at once; the conditional
        filter means exactly one of them releases the order, so a scheduled
        order is never dispatched twice. Any pickup point resolved along the way
        is persisted in the same write, so later retries do not re-resolve it.
        """
        changes = {"scheduled_dispatched": True}
        if pickup is not None and hasattr(pickup, "model_dump"):
            changes["pickup_location"] = pickup.model_dump()

        collection = _order_collection()
        if collection is None:
            if getattr(order, "scheduled_dispatched", False):
                return False
            order.scheduled_dispatched = True
            await order.save()
            return True

        result = await collection.find_one_and_update(
            {
                "_id": _document_id(getattr(order, "id", None)),
                "scheduled_dispatched": {"$ne": True},
            },
            {"$set": changes},
        )
        if result is None:
            return False
        order.scheduled_dispatched = True
        return True

    @staticmethod
    async def mark_dispatch_escalated(order_id: str) -> bool:
        """Flag an order as dead-lettered. True the first time only.

        The conditional filter makes the escalation fire exactly once even if
        several workers notice the exhausted order in the same sweep, so ops is
        paged once and the consumer is told once.
        """
        now = utc_now()
        event = OrderEvent(
            state=OrderState.CREATED,
            actor_id="system",
            reason="dispatch_escalated",
            metadata={"escalated_at": now.isoformat()},
        )
        collection = _order_collection()
        if collection is None:
            order = await Order.get(order_id)
            if order is None or getattr(order, "dispatch_escalated", False):
                return False
            order.dispatch_escalated = True
            order.dispatch_escalated_at = now
            await order.save()
            return True

        result = await collection.find_one_and_update(
            {"_id": _document_id(order_id), "dispatch_escalated": {"$ne": True}},
            {
                "$set": {"dispatch_escalated": True, "dispatch_escalated_at": now},
                "$push": {"events": _event_document(event)},
            },
        )
        return result is not None

    # ──────────────────────────────────────────────────────────────
    # Queries
    # ──────────────────────────────────────────────────────────────

    @staticmethod
    async def active_load(driver_ids: Sequence[str]) -> dict:
        """How many live deliveries each of these drivers is already carrying.

        One query for the whole candidate set — never one per driver.
        """
        ids = [d for d in driver_ids if d]
        if not ids:
            return {}
        try:
            orders = await Order.find(
                {
                    "driver_id": {"$in": ids},
                    "state": {"$in": [s.value for s in ACTIVE_DRIVER_STATES]},
                }
            ).limit(MAX_LOAD_LOOKUP).to_list()
        except Exception as e:
            logger.debug("Driver load lookup unavailable", error=str(e))
            return {}
        loads: dict = {}
        for order in orders:
            key = getattr(order, "driver_id", None)
            if key:
                loads[key] = loads.get(key, 0) + 1
        return loads
