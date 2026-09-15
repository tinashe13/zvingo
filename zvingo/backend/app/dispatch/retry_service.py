"""Background keeper for orders that dispatch has not placed with a driver.

Two loops run here:

**Offer sweep** (`DISPATCH_OFFER_SWEEP_SECONDS`, default 5s)
    An offer is held by one driver for `DISPATCH_OFFER_TIMEOUT_SECONDS`. When it
    lapses unanswered this sweep releases it and dispatch moves to the next best
    driver. It is driven off `offer_expires_at` in the database rather than an
    in-process timer, so an offer cannot be stranded by a backend restart.

**Retry loop** (`DISPATCH_RETRY_INTERVAL_SECONDS`, default 120s)
    A slower safety net for orders sitting in CREATED/OFFERED — no driver in
    range, a dispatch that crashed mid-flight, a pickup location that was
    unresolved at creation time. After `DISPATCH_MAX_RETRY_ATTEMPTS` the order is
    **dead-lettered**: retries stop, an operational alert is raised for ops, and
    the consumer is told once. An order nobody will ever collect has to surface
    to a human instead of leaving the consumer staring at a spinner.
"""

import asyncio
from datetime import timedelta
from app.time_utils import utc_now
from app.config import settings
from app.order.models import Order
from app.order.service import OrderService
from app.order.state_machine import OrderState
from app.dispatch.service import dispatch_service
from app.location.models import Location
from app.observability import metrics
import structlog

logger = structlog.get_logger()


def _setting(name: str, default):
    """Read a setting, falling back to a safe module default if undeclared."""
    value = getattr(settings, name, None)
    return default if value is None else value


# Configuration (see DISPATCH_* settings; defaults: 120s interval, 10 attempts)
RETRY_INTERVAL_SECONDS = settings.DISPATCH_RETRY_INTERVAL_SECONDS
MAX_RETRY_ATTEMPTS = settings.DISPATCH_MAX_RETRY_ATTEMPTS
#: How often lapsed offers are swept back into the dispatch pool.
OFFER_SWEEP_INTERVAL_SECONDS = int(_setting("DISPATCH_OFFER_SWEEP_SECONDS", 5))
#: Upper bound on orders handled in one sweep, so a backlog cannot stall the loop.
SWEEP_BATCH_SIZE = int(_setting("DISPATCH_SWEEP_BATCH_SIZE", 200))


class OrderRetryService:
    """Background service to retry dispatching stuck orders."""

    _task = None
    _offer_task = None

    @classmethod
    async def start(cls):
        """Start the background retry and offer-expiry tasks."""
        if cls._task is None:
            cls._task = asyncio.create_task(cls._retry_loop())
            logger.info("Order retry service started", interval_seconds=RETRY_INTERVAL_SECONDS)
        if cls._offer_task is None:
            cls._offer_task = asyncio.create_task(cls._offer_sweep_loop())
            logger.info(
                "Offer expiry sweep started",
                interval_seconds=OFFER_SWEEP_INTERVAL_SECONDS,
            )

    @classmethod
    async def stop(cls):
        """Stop the background tasks."""
        if cls._task is not None:
            cls._task.cancel()
            cls._task = None
            logger.info("Order retry service stopped")
        if cls._offer_task is not None:
            cls._offer_task.cancel()
            cls._offer_task = None
            logger.info("Offer expiry sweep stopped")

    # ── Offer expiry ───────────────────────────────────────────────

    @classmethod
    async def _offer_sweep_loop(cls):
        while True:
            try:
                await asyncio.sleep(OFFER_SWEEP_INTERVAL_SECONDS)
                await cls.sweep_expired_offers()
            except asyncio.CancelledError:
                logger.info("Offer sweep cancelled")
                break
            except Exception as e:
                logger.error("Offer sweep error", error=str(e), error_type=type(e).__name__)
                continue

    @classmethod
    async def sweep_expired_offers(cls) -> int:
        """Re-dispatch every order whose outstanding offer has lapsed.

        Returns the number of orders handed on to the next driver.
        """
        now = utc_now()
        try:
            lapsed = await Order.find(
                {
                    "state": OrderState.OFFERED.value,
                    "driver_id": None,
                    "offered_driver_id": {"$ne": None},
                    "offer_expires_at": {"$lt": now},
                }
            ).limit(SWEEP_BATCH_SIZE).to_list()
        except Exception as e:
            logger.error("Could not query lapsed offers", error=str(e))
            return 0

        handled = 0
        for order in lapsed:
            try:
                pickup = await OrderService._resolve_pickup(order)
                if pickup is None or pickup.is_null_island:
                    logger.warning(
                        "Lapsed offer has no pickup location",
                        order_id=str(order.id),
                    )
                    await OrderService.clear_expired_offer(str(order.id))
                    continue
                logger.info(
                    "Offer lapsed, moving to the next driver",
                    order_id=str(order.id),
                    driver_id=order.offered_driver_id,
                )
                await dispatch_service.dispatch_order(
                    str(order.id), pickup.lat, pickup.lng
                )
                handled += 1
            except Exception as e:
                logger.error(
                    "Failed to re-offer a lapsed order",
                    order_id=str(order.id),
                    error=str(e),
                    error_type=type(e).__name__,
                )
                continue
        return handled

    # ── Retry loop ─────────────────────────────────────────────────

    @classmethod
    async def _retry_loop(cls):
        """Main retry loop - runs every DISPATCH_RETRY_INTERVAL_SECONDS."""
        while True:
            try:
                await asyncio.sleep(RETRY_INTERVAL_SECONDS)
                await cls._process_stuck_orders()
            except asyncio.CancelledError:
                logger.info("Retry loop cancelled")
                break
            except Exception as e:
                logger.error("Retry loop error", error=str(e), error_type=type(e).__name__)
                # Continue even if there's an error
                continue

    @classmethod
    async def _process_stuck_orders(cls):
        """Find and re-dispatch orders stuck in OFFERED state."""
        try:
            # Retry-eligible orders are:
            #   1. stuck in OFFERED (offered, but no driver accepted), or
            #   2. stuck in CREATED past the retry cutoff (no driver was found
            #      on the initial dispatch).
            # Self-pickup orders never have a driver, so they are excluded.
            # Scheduled orders belong to ScheduledOrderService until it releases
            # them (`scheduled_dispatched`), after which they retry normally.
            # Dead-lettered orders are ops' problem now, not the loop's.
            cutoff = utc_now() - timedelta(seconds=RETRY_INTERVAL_SECONDS)
            created_stuck = {
                "state": OrderState.CREATED,
                "created_at": {"$lt": cutoff},
                "is_pickup": {"$ne": True},
            }
            stuck_orders = await Order.find(
                {
                    "dispatch_escalated": {"$ne": True},
                    "$or": [
                        {"state": OrderState.OFFERED},
                        # A merchant confirming an order moves it to ACCEPTED
                        # without a driver. Dispatch must keep working on it, or
                        # the order strands with the kitchen and never ships.
                        {"state": OrderState.ACCEPTED, "driver_id": None,
                         "is_pickup": {"$ne": True}},
                        {**created_stuck, "scheduled_at": None},
                        {**created_stuck, "scheduled_dispatched": True},
                    ],
                }
            ).limit(SWEEP_BATCH_SIZE).to_list()

            if not stuck_orders:
                return

            logger.info("Processing stuck orders", count=len(stuck_orders))

            for order in stuck_orders:
                try:
                    # Check if order has retry count and is under max attempts
                    retry_count = order.retry_count if hasattr(order, 'retry_count') else 0

                    if retry_count >= MAX_RETRY_ATTEMPTS:
                        await cls._escalate(order, retry_count)
                        continue

                    # Check if enough time has passed since last retry
                    last_retry = order.last_retry_at if hasattr(order, 'last_retry_at') else None
                    if last_retry:
                        time_since_last_retry = utc_now() - last_retry
                        if time_since_last_retry.total_seconds() < RETRY_INTERVAL_SECONDS:
                            # Not enough time has passed
                            continue

                    # Get pickup location — re-resolve from restaurant if stored as (0,0)
                    pickup_lat = order.pickup_location.lat if order.pickup_location else 0
                    pickup_lng = order.pickup_location.lng if order.pickup_location else 0

                    if abs(pickup_lat) < 0.01 and abs(pickup_lng) < 0.01:
                        # Pickup wasn't resolved at order creation — fix it now
                        try:
                            from app.catalog.models import Restaurant
                            restaurant = await Restaurant.get(order.merchant_id)
                            if restaurant and restaurant.location:
                                pickup_lng, pickup_lat = restaurant.location.lng, restaurant.location.lat
                                # Patch the order so future retries use correct location
                                order.pickup_location = Location.from_lat_lng(pickup_lat, pickup_lng)
                                logger.info(
                                    "Fixed order pickup location from restaurant",
                                    order_id=str(order.id),
                                    restaurant=restaurant.name,
                                    pickup_lat=pickup_lat, pickup_lng=pickup_lng
                                )
                        except Exception as e:
                            logger.error("Failed to resolve restaurant location on retry",
                                         order_id=str(order.id), error=str(e))
                            continue  # Skip this order — can't dispatch without location

                    logger.info(
                        "Re-dispatching order",
                        order_id=str(order.id),
                        retry_count=retry_count,
                        location=[pickup_lat, pickup_lng]
                    )

                    # Re-dispatch
                    await dispatch_service.dispatch_order(
                        str(order.id), pickup_lat, pickup_lng
                    )

                    # Update retry metadata
                    order.retry_count = retry_count + 1
                    order.last_retry_at = utc_now()
                    await order.save()

                except Exception as e:
                    logger.error(
                        "Error processing stuck order",
                        order_id=str(order.id),
                        error=str(e),
                        error_type=type(e).__name__
                    )
                    continue

        except Exception as e:
            logger.error(
                "Error in _process_stuck_orders",
                error=str(e),
                error_type=type(e).__name__
            )

    # ── Dead letter ────────────────────────────────────────────────

    @classmethod
    async def _escalate(cls, order, retry_count: int) -> None:
        """Dead-letter an order that burned through its dispatch budget.

        Raises an ops alert and tells the consumer, exactly once — the flag is
        set with a conditional update, so a duplicate sweep is a no-op.
        """
        order_id = str(order.id)
        logger.warning(
            "Order max retries exceeded",
            order_id=order_id,
            retry_count=retry_count,
        )
        metrics.dispatch_retry_exhausted_total.inc()

        if getattr(order, "dispatch_escalated", False):
            return
        if not await OrderService.mark_dispatch_escalated(order_id):
            return

        try:
            from app.observability.alerts import alert_service

            await alert_service.raise_alert(
                "dispatch_dead_letter",
                f"Order {order_id} could not be placed with any driver after "
                f"{retry_count} attempts and needs manual dispatch",
                dedupe_key=f"dispatch_dead_letter:{order_id}",
                order_id=order_id,
                retry_count=retry_count,
                merchant_id=getattr(order, "merchant_id", None),
                consumer_id=getattr(order, "consumer_id", None),
            )
        except Exception as e:
            logger.error("Could not raise dead-letter alert", order_id=order_id, error=str(e))

        try:
            from app.notification.service import notification_service

            if getattr(order, "consumer_id", None):
                await notification_service.notify_consumer(
                    order.consumer_id,
                    order_id,
                    "dispatch_delayed",
                    {
                        "state": str(getattr(order.state, "value", order.state)),
                        "message": (
                            "We're having trouble finding a driver for your order. "
                            "Our team has been alerted and will be in touch."
                        ),
                    },
                )
        except Exception as e:
            logger.error(
                "Could not notify consumer of dead-lettered order",
                order_id=order_id,
                error=str(e),
            )


# Global instance
retry_service = OrderRetryService()
