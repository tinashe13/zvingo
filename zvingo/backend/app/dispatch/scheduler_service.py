"""Dedicated poller for scheduled orders.

Scheduled orders used to ride on the dispatch retry loop, which meant up to a
two-minute delay and dispatch starting only *at* the requested time. This
service polls on a much tighter interval and releases an order
`SCHEDULED_DISPATCH_LEAD_MINUTES` ahead of its slot, so the driver is already
en route when the food is due.

Once released, an order is marked `scheduled_dispatched` and becomes an
ordinary order as far as the retry loop is concerned — this service never
touches it again.
"""

import asyncio
from datetime import timedelta
from typing import List, Optional

import structlog

from app.config import settings
from app.dispatch.service import dispatch_service
from app.location.models import Location
from app.order.models import Order
from app.order.state_machine import OrderState
from app.time_utils import utc_now

logger = structlog.get_logger()


class ScheduledOrderService:
    """Releases scheduled orders into dispatch as their slot approaches."""

    def __init__(self) -> None:
        self._task: Optional[asyncio.Task] = None

    async def due_orders(self) -> List[Order]:
        """Scheduled orders whose dispatch window has opened."""
        release_before = utc_now() + timedelta(
            minutes=settings.SCHEDULED_DISPATCH_LEAD_MINUTES
        )
        return await Order.find(
            {
                "state": OrderState.CREATED,
                "scheduled_at": {"$ne": None, "$lte": release_before},
                "scheduled_dispatched": {"$ne": True},
                "is_pickup": {"$ne": True},
            }
        ).to_list()

    async def _resolve_pickup(self, order: Order) -> Optional[tuple]:
        """Pickup coordinates for an order, re-resolved from the restaurant if unset."""
        lat = order.pickup_location.lat if order.pickup_location else 0
        lng = order.pickup_location.lng if order.pickup_location else 0
        if abs(lat) >= 0.01 or abs(lng) >= 0.01:
            return lat, lng

        try:
            from app.catalog.models import Restaurant

            restaurant = await Restaurant.get(order.merchant_id)
        except Exception as e:
            logger.error(
                "Failed to resolve pickup for scheduled order",
                order_id=str(order.id),
                error=str(e),
            )
            return None
        if not restaurant or not restaurant.location:
            return None
        order.pickup_location = Location.from_lat_lng(
            restaurant.location.lat, restaurant.location.lng
        )
        return restaurant.location.lat, restaurant.location.lng

    async def release_due_orders(self) -> int:
        """Dispatch every scheduled order that is now due. Returns the count."""
        due = await self.due_orders()
        released = 0

        for order in due:
            try:
                pickup = await self._resolve_pickup(order)
                if pickup is None:
                    logger.warning(
                        "Skipping scheduled order without a pickup location",
                        order_id=str(order.id),
                    )
                    continue

                lat, lng = pickup
                # Mark before dispatching: a crash mid-dispatch should leave the
                # order to the retry loop rather than re-releasing it here.
                order.scheduled_dispatched = True
                await order.save()

                await dispatch_service.dispatch_order(str(order.id), lat, lng)
                released += 1
                logger.info(
                    "Released scheduled order for dispatch",
                    order_id=str(order.id),
                    scheduled_at=order.scheduled_at.isoformat()
                    if order.scheduled_at
                    else None,
                )
            except Exception as e:
                logger.error(
                    "Failed to release scheduled order",
                    order_id=str(order.id),
                    error=str(e),
                    error_type=type(e).__name__,
                )
                continue

        return released

    async def _loop(self) -> None:
        while True:
            try:
                await asyncio.sleep(settings.SCHEDULED_POLL_INTERVAL_SECONDS)
                await self.release_due_orders()
            except asyncio.CancelledError:
                logger.info("Scheduled order poller cancelled")
                break
            except Exception as e:
                logger.error("Scheduled order poller error", error=str(e))
                continue

    async def start(self) -> None:
        if self._task is not None:
            return
        self._task = asyncio.create_task(self._loop())
        logger.info(
            "Scheduled order poller started",
            interval_seconds=settings.SCHEDULED_POLL_INTERVAL_SECONDS,
            lead_minutes=settings.SCHEDULED_DISPATCH_LEAD_MINUTES,
        )

    async def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            self._task = None
            logger.info("Scheduled order poller stopped")


scheduled_order_service = ScheduledOrderService()
