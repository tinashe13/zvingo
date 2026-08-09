"""
Background task to retry dispatching orders that are stuck in OFFERED state.
Re-offers them to drivers every 2 minutes to find available drivers.
"""

import asyncio
from datetime import datetime, timedelta
from app.time_utils import utc_now
from app.config import settings
from app.order.models import Order
from app.order.state_machine import OrderState
from app.dispatch.service import dispatch_service
import structlog

logger = structlog.get_logger()

# Configuration (see DISPATCH_* settings; defaults: 120s interval, 10 attempts)
RETRY_INTERVAL_SECONDS = settings.DISPATCH_RETRY_INTERVAL_SECONDS
MAX_RETRY_ATTEMPTS = settings.DISPATCH_MAX_RETRY_ATTEMPTS


class OrderRetryService:
    """Background service to retry dispatching stuck orders."""

    _task = None

    @classmethod
    async def start(cls):
        """Start the background retry task."""
        if cls._task is not None:
            return

        cls._task = asyncio.create_task(cls._retry_loop())
        logger.info("Order retry service started", interval_seconds=RETRY_INTERVAL_SECONDS)

    @classmethod
    async def stop(cls):
        """Stop the background retry task."""
        if cls._task is not None:
            cls._task.cancel()
            cls._task = None
            logger.info("Order retry service stopped")

    @classmethod
    async def _retry_loop(cls):
        """Main retry loop - runs every 2 minutes."""
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
            # Find orders stuck in OFFERED state (driver never accepted)
            # OR orders stuck in CREATED state (no drivers found on initial dispatch)
            # CREATED orders older than RETRY_INTERVAL_SECONDS are eligible for retry
            cutoff = utc_now() - timedelta(seconds=RETRY_INTERVAL_SECONDS)
            stuck_orders = await Order.find(
                {"$or": [
                    {"state": OrderState.OFFERED},
                    {"state": OrderState.CREATED, "created_at": {"$lt": cutoff}}
                ]}
            ).to_list()

            if not stuck_orders:
                return

            logger.info("Processing stuck orders", count=len(stuck_orders))

            for order in stuck_orders:
                try:
                    # Check if order has retry count and is under max attempts
                    retry_count = order.retry_count if hasattr(order, 'retry_count') else 0

                    if retry_count >= MAX_RETRY_ATTEMPTS:
                        logger.warn(
                            "Order max retries exceeded",
                            order_id=str(order.id),
                            retry_count=retry_count
                        )
                        continue

                    # Check if enough time has passed since last retry
                    last_retry = order.last_retry_at if hasattr(order, 'last_retry_at') else None
                    if last_retry:
                        time_since_last_retry = utc_now() - last_retry
                        if time_since_last_retry.total_seconds() < RETRY_INTERVAL_SECONDS:
                            # Not enough time has passed
                            continue

                    # Get pickup location — re-resolve from restaurant if stored as (0,0)
                    pickup_lat = order.pickup_location['coordinates'][1]
                    pickup_lng = order.pickup_location['coordinates'][0]

                    if abs(pickup_lat) < 0.01 and abs(pickup_lng) < 0.01:
                        # Pickup wasn't resolved at order creation — fix it now
                        try:
                            from app.catalog.models import Restaurant
                            restaurant = await Restaurant.get(order.merchant_id)
                            if restaurant and restaurant.location:
                                coords = restaurant.location.coordinates
                                pickup_lng, pickup_lat = coords[0], coords[1]
                                # Patch the order so future retries use correct location
                                order.pickup_location = {
                                    "type": "Point",
                                    "coordinates": [pickup_lng, pickup_lat]
                                }
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


# Global instance
retry_service = OrderRetryService()
