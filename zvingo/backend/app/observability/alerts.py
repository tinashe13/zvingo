"""Operational alerting for stuck orders, failed payments, and dead dispatches.

A background poller inspects the database on a fixed interval and raises an
alert whenever a condition crosses its threshold. Alerts are:

* emitted as a structured ``alert`` log event (so any log-based alerting
  pipeline can trigger on them),
* published to the Redis ``alerts`` channel (so an ops dashboard can subscribe),
* counted in `zvingo_alerts_total`, and
* kept in a bounded in-memory ring buffer exposed at ``GET /admin/alerts``.

Each alert carries a dedupe key; the same key is not re-raised until the alert
window has elapsed, so a single stuck order does not page every poll.
"""

import asyncio
import json
from collections import deque
from datetime import timedelta
from typing import Deque, Dict, List, Optional

import redis.asyncio as aioredis
import structlog

from app.config import settings
from app.observability import metrics
from app.time_utils import utc_now

logger = structlog.get_logger()

ALERT_CHANNEL = "alerts"

# Order states that should always be progressing; sitting in one of these for
# longer than ALERT_STUCK_ORDER_MINUTES means nobody is moving the order along.
NON_TERMINAL_STATES = [
    "CREATED",
    "OFFERED",
    "ACCEPTED",
    "ARRIVED_AT_MERCHANT",
    "READY_FOR_PICKUP",
    "PICKED_UP",
    "ARRIVED_AT_CUSTOMER",
]


class AlertService:
    """Detects and records operational alerts."""

    def __init__(self) -> None:
        self._task: Optional[asyncio.Task] = None
        self._history: Deque[dict] = deque(maxlen=settings.ALERT_HISTORY_SIZE)
        self._last_raised: Dict[str, object] = {}

    # ── history ────────────────────────────────────────────────────
    def history(self, limit: int = 50) -> List[dict]:
        """Most recent alerts, newest first."""
        return list(self._history)[-limit:][::-1]

    def clear(self) -> None:
        self._history.clear()
        self._last_raised.clear()

    # ── raising ────────────────────────────────────────────────────
    def _is_muted(self, dedupe_key: str) -> bool:
        last = self._last_raised.get(dedupe_key)
        if last is None:
            return False
        return utc_now() - last < timedelta(minutes=settings.ALERT_WINDOW_MINUTES)

    async def raise_alert(
        self, kind: str, message: str, dedupe_key: str, **context
    ) -> Optional[dict]:
        """Record an alert unless an identical one is still within its window."""
        if self._is_muted(dedupe_key):
            return None

        now = utc_now()
        self._last_raised[dedupe_key] = now
        alert = {
            "kind": kind,
            "message": message,
            "dedupe_key": dedupe_key,
            "raised_at": now.isoformat(),
            "context": context,
        }
        self._history.append(alert)
        metrics.alerts_total.inc(kind=kind)
        logger.warning("alert", **alert)

        try:
            r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
            try:
                await r.publish(ALERT_CHANNEL, json.dumps(alert))
            finally:
                await r.close()
        except Exception as e:  # Redis must never break alerting
            logger.error("Failed to publish alert", error=str(e))

        return alert

    # ── checks ─────────────────────────────────────────────────────
    async def check_stuck_orders(self) -> int:
        """Alert on orders that have not changed state in too long."""
        from app.order.models import Order

        cutoff = utc_now() - timedelta(minutes=settings.ALERT_STUCK_ORDER_MINUTES)
        stuck = await Order.find(
            {"state": {"$in": NON_TERMINAL_STATES}, "updated_at": {"$lt": cutoff}}
        ).to_list()

        for order in stuck:
            state = getattr(order.state, "value", order.state)
            await self.raise_alert(
                "stuck_order",
                f"Order {order.id} has been in {state} for over "
                f"{settings.ALERT_STUCK_ORDER_MINUTES} minutes",
                dedupe_key=f"stuck_order:{order.id}:{state}",
                order_id=str(order.id),
                state=str(state),
                merchant_id=order.merchant_id,
                driver_id=order.driver_id,
            )
        return len(stuck)

    async def check_failed_payments(self) -> int:
        """Alert when failed payments spike within the alert window."""
        from app.payment.models import Payment, PaymentStatus

        cutoff = utc_now() - timedelta(minutes=settings.ALERT_WINDOW_MINUTES)
        failed = await Payment.find(
            {"status": PaymentStatus.FAILED, "updated_at": {"$gte": cutoff}}
        ).count()

        if failed >= settings.ALERT_FAILED_PAYMENT_THRESHOLD:
            await self.raise_alert(
                "failed_payments",
                f"{failed} payments failed in the last "
                f"{settings.ALERT_WINDOW_MINUTES} minutes",
                dedupe_key="failed_payments",
                failed_count=failed,
                threshold=settings.ALERT_FAILED_PAYMENT_THRESHOLD,
            )
        return failed

    async def check_dispatch_exhaustion(self) -> int:
        """Alert on orders that burned through their dispatch retry budget."""
        from app.order.models import Order
        from app.order.state_machine import OrderState

        exhausted = await Order.find(
            {
                "state": {"$in": [OrderState.CREATED, OrderState.OFFERED]},
                "retry_count": {"$gte": settings.DISPATCH_MAX_RETRY_ATTEMPTS},
            }
        ).to_list()

        for order in exhausted:
            await self.raise_alert(
                "dispatch_exhausted",
                f"Order {order.id} exhausted {order.retry_count} dispatch "
                "attempts without a driver",
                dedupe_key=f"dispatch_exhausted:{order.id}",
                order_id=str(order.id),
                retry_count=order.retry_count,
                merchant_id=order.merchant_id,
            )
        return len(exhausted)

    async def run_checks(self) -> dict:
        """Run every check once, isolating failures so one bad check is not fatal."""
        results = {}
        for name, check in (
            ("stuck_orders", self.check_stuck_orders),
            ("failed_payments", self.check_failed_payments),
            ("dispatch_exhausted", self.check_dispatch_exhaustion),
        ):
            try:
                results[name] = await check()
            except Exception as e:
                logger.error("Alert check failed", check=name, error=str(e))
                results[name] = None
        return results

    # ── lifecycle ──────────────────────────────────────────────────
    async def _loop(self) -> None:
        while True:
            try:
                await asyncio.sleep(settings.ALERT_POLL_INTERVAL_SECONDS)
                await self.run_checks()
            except asyncio.CancelledError:
                logger.info("Alert monitor cancelled")
                break
            except Exception as e:
                logger.error("Alert monitor error", error=str(e))
                continue

    async def start(self) -> None:
        if self._task is not None or not settings.ALERTS_ENABLED:
            return
        self._task = asyncio.create_task(self._loop())
        logger.info(
            "Alert monitor started",
            interval_seconds=settings.ALERT_POLL_INTERVAL_SECONDS,
        )

    async def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            self._task = None
            logger.info("Alert monitor stopped")


alert_service = AlertService()
