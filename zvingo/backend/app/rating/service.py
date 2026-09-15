"""Rating aggregation and driver performance metrics.

Reviews are stored individually; the restaurant and driver documents carry a
running average so listing screens never have to scan the review collection.
Averages are folded in incrementally rather than recomputed, which keeps review
submission O(1) and restaurant listing O(0) in review count.
"""

from datetime import timedelta
from typing import Optional, Tuple

import structlog

from app.time_utils import utc_now

logger = structlog.get_logger()

#: A delivery counts as on time when it goes from driver-accepted to delivered
#: within this many minutes. Zvingo's published promise is 30–45 minutes, so 45
#: is the outer edge of that band.
ON_TIME_SLA_MINUTES = 45

#: Rolling window for the driver performance rates shown in the driver app.
METRICS_WINDOW_DAYS = 30


def fold_average(
    current: Optional[float], count: Optional[int], new_stars: int
) -> Tuple[float, int]:
    """Fold one new rating into a running (average, count) pair."""
    count = count or 0
    if count <= 0 or current is None:
        return float(new_stars), 1
    total = current * count
    count += 1
    return round((total + new_stars) / count, 2), count


async def resolve_restaurant(restaurant_id: str):
    """Load a restaurant by document id, falling back to its merchant id.

    Orders carry `merchant_id`, which callers set to either the restaurant's
    document id or the owning merchant's user id. Ratings must land on the
    restaurant either way, otherwise every review silently vanishes.
    """
    from app.catalog.models import Restaurant

    try:
        restaurant = await Restaurant.get(restaurant_id)
    except Exception as e:
        logger.warning(
            "Failed to load restaurant for rating", restaurant_id=restaurant_id, error=str(e)
        )
        return None
    if restaurant is not None:
        return restaurant
    try:
        return await Restaurant.find_one(Restaurant.merchant_id == restaurant_id)
    except Exception:
        return None


async def apply_restaurant_rating(restaurant_id: str, stars: int) -> None:
    """Update a restaurant's aggregate rating with a new review."""
    restaurant = await resolve_restaurant(restaurant_id)
    if not restaurant:
        return
    restaurant.rating, restaurant.review_count = fold_average(
        restaurant.rating, restaurant.review_count, stars
    )
    await restaurant.save()


async def apply_driver_rating(driver_id: str, stars: int) -> None:
    """Update a driver's aggregate rating with a new review."""
    from app.auth.models import User

    try:
        driver = await User.get(driver_id)
    except Exception as e:
        logger.warning(
            "Failed to load driver for rating", driver_id=driver_id, error=str(e)
        )
        return
    if not driver:
        return
    driver.driver_rating, driver.driver_review_count = fold_average(
        driver.driver_rating, driver.driver_review_count, stars
    )
    await driver.save()


def _percent(numerator: int, denominator: int) -> Optional[float]:
    if denominator <= 0:
        return None
    return round(min(100.0, 100.0 * numerator / denominator), 1)


async def driver_performance(driver_id: str) -> dict:
    """Delivery performance over the last `METRICS_WINDOW_DAYS`.

    Every rate is ``None`` rather than ``0`` when there is nothing to measure,
    so the driver app can show "—" instead of an insulting 0%.

    * ``completion_rate``  delivered ÷ (delivered + cancelled while assigned)
    * ``on_time_rate``     delivered within `ON_TIME_SLA_MINUTES` of acceptance
    * ``acceptance_rate``  offers accepted ÷ offers pushed (lifetime, read from
      the dispatcher's own per-driver counters — the only place both halves of
      the ratio are counted at the same moment)
    """
    from app.order.models import Order
    from app.order.state_machine import OrderState

    metrics = {
        "lifetime_deliveries": 0,
        "window_days": METRICS_WINDOW_DAYS,
        "deliveries_in_window": 0,
        "completion_rate": None,
        "on_time_rate": None,
        "acceptance_rate": None,
        "offers_received": 0,
        "offers_accepted": 0,
    }

    # Acceptance is lifetime and independent of the order window, so it is
    # resolved first — a driver with no orders yet can still have an
    # acceptance rate, and an order-read failure must not hide it.
    try:
        from app.notification.offer_metrics import offer_stats

        stats = await offer_stats(driver_id)
    except Exception as e:  # pragma: no cover - Redis optional for metrics
        logger.warning("Offer counters unavailable", driver_id=driver_id, error=str(e))
        stats = {}
    metrics["offers_received"] = stats.get("offers_sent", 0)
    metrics["offers_accepted"] = stats.get("offers_accepted", 0)
    metrics["acceptance_rate"] = _percent(
        metrics["offers_accepted"], metrics["offers_received"]
    )

    cutoff = utc_now() - timedelta(days=METRICS_WINDOW_DAYS)
    try:
        metrics["lifetime_deliveries"] = await Order.find(
            {"driver_id": driver_id, "state": OrderState.DELIVERED}
        ).count()
        window_orders = await Order.find(
            {"driver_id": driver_id, "created_at": {"$gte": cutoff}}
        ).to_list()
    except Exception as e:
        logger.warning("Driver metrics unavailable", driver_id=driver_id, error=str(e))
        return metrics

    delivered = [o for o in window_orders if o.state == OrderState.DELIVERED]
    cancelled = [o for o in window_orders if o.state == OrderState.CANCELLED]
    metrics["deliveries_in_window"] = len(delivered)
    metrics["completion_rate"] = _percent(
        len(delivered), len(delivered) + len(cancelled)
    )

    on_time = 0
    measurable = 0
    for order in delivered:
        events = {}
        for event in order.events or []:
            state = getattr(event.state, "value", event.state)
            events.setdefault(state, event.timestamp)
        accepted_at = events.get(OrderState.ACCEPTED.value)
        delivered_at = events.get(OrderState.DELIVERED.value)
        if not accepted_at or not delivered_at:
            continue
        measurable += 1
        if (delivered_at - accepted_at) <= timedelta(minutes=ON_TIME_SLA_MINUTES):
            on_time += 1
    metrics["on_time_rate"] = _percent(on_time, measurable)

    return metrics
