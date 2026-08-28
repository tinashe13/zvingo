"""Rating aggregation.

Reviews are stored individually; the restaurant and driver documents carry a
running average so listing screens never have to scan the review collection.
Averages are folded in incrementally rather than recomputed, which keeps review
submission O(1).
"""

from typing import Optional, Tuple

import structlog

logger = structlog.get_logger()


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


async def apply_restaurant_rating(restaurant_id: str, stars: int) -> None:
    """Update a restaurant's aggregate rating with a new review."""
    from app.catalog.models import Restaurant

    try:
        restaurant = await Restaurant.get(restaurant_id)
    except Exception as e:
        logger.warning(
            "Failed to load restaurant for rating", restaurant_id=restaurant_id, error=str(e)
        )
        return
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
