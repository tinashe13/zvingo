from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Annotated, List, Optional
from app.rating.models import Review
from app.rating.schemas import ReviewCreate, ReviewResponse
from app.order.models import Order
from app.order.state_machine import OrderState
from app.rating.service import (
    ON_TIME_SLA_MINUTES,
    apply_driver_rating,
    apply_restaurant_rating,
    driver_performance,
    resolve_restaurant,
)
from app.auth.router import get_current_user
from app.auth.models import User

router = APIRouter()

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 100

#: Feedback shown on the driver's ratings screen.
RECENT_FEEDBACK_LIMIT = 10


def _to_response(review: Review) -> ReviewResponse:
    return ReviewResponse(
        id=str(review.id),
        order_id=review.order_id,
        consumer_id=review.consumer_id,
        restaurant_id=review.restaurant_id,
        driver_id=review.driver_id,
        restaurant_rating=review.restaurant_rating,
        driver_rating=review.driver_rating,
        comment=review.comment,
        tags=list(getattr(review, "tags", None) or []),
        created_at=review.created_at,
    )


def _page(query, offset: int, limit: int):
    return query.skip(offset).limit(limit)


def _mask_name(full_name: Optional[str]) -> str:
    """"John Smith" → "John S." — drivers see who, not personal detail."""
    parts = (full_name or "").strip().split()
    if not parts:
        return "A customer"
    if len(parts) == 1:
        return parts[0]
    return f"{parts[0]} {parts[-1][0]}."


@router.post("/orders/{order_id}/review", response_model=ReviewResponse)
async def create_review(
    order_id: str, review_in: ReviewCreate, current_user: User = Depends(get_current_user)
):
    """Submit a review for a delivered order (one per order).

    Only the consumer who placed the order may review it, only once, and only
    after it has actually been delivered.
    """
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if order.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not your order to review")

    if order.state != OrderState.DELIVERED:
        raise HTTPException(
            status_code=400, detail="Can only review a delivered order"
        )

    existing = await Review.find_one(Review.order_id == order_id)
    if existing:
        raise HTTPException(status_code=400, detail="This order has already been reviewed")

    if review_in.driver_rating is not None and not order.driver_id:
        raise HTTPException(
            status_code=400,
            detail="This order had no driver, so it cannot be given a driver rating",
        )

    review = Review(
        order_id=order_id,
        consumer_id=str(current_user.id),
        restaurant_id=order.merchant_id,
        driver_id=order.driver_id,
        restaurant_rating=review_in.restaurant_rating,
        driver_rating=review_in.driver_rating,
        comment=review_in.comment,
        tags=review_in.tags,
    )
    try:
        await review.insert()
    except Exception as e:
        # The unique index on order_id is the real guard against a double
        # submit racing the find_one above.
        if "duplicate key" in str(e).lower():
            raise HTTPException(
                status_code=400, detail="This order has already been reviewed"
            )
        raise

    # Fold the new stars into the restaurant and driver aggregates.
    await apply_restaurant_rating(order.merchant_id, review.restaurant_rating)
    if review.driver_id and review.driver_rating is not None:
        await apply_driver_rating(review.driver_id, review.driver_rating)

    return _to_response(review)


@router.get("/orders/{order_id}/review", response_model=Optional[ReviewResponse])
async def get_order_review(
    order_id: str, current_user: User = Depends(get_current_user)
):
    """The consumer's own review for an order, or null if they haven't left one.

    Lets the app show "You rated this 5★" instead of prompting again.
    """
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not your order")
    review = await Review.find_one(Review.order_id == order_id)
    return _to_response(review) if review else None


@router.get("/restaurants/{restaurant_id}/reviews", response_model=List[ReviewResponse])
async def list_restaurant_reviews(
    restaurant_id: str,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
):
    reviews = await _page(
        Review.find(Review.restaurant_id == restaurant_id).sort("-created_at"),
        offset,
        limit,
    ).to_list()
    return [_to_response(r) for r in reviews]


@router.get("/restaurants/{restaurant_id}/summary")
async def restaurant_rating_summary(restaurant_id: str):
    """Stored aggregate for a restaurant, plus the star distribution.

    The average and count are read straight off the restaurant document — they
    are folded in on write, never recomputed here. Only the distribution needs
    the review collection, and it is capped by the same index.
    """
    restaurant = await resolve_restaurant(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")

    reviews = await Review.find(Review.restaurant_id == restaurant_id).to_list()
    breakdown = {str(star): 0 for star in range(1, 6)}
    for review in reviews:
        stars = getattr(review, "restaurant_rating", None)
        if stars in (1, 2, 3, 4, 5):
            breakdown[str(stars)] += 1

    return {
        "restaurant_id": restaurant_id,
        "rating": restaurant.rating,
        "review_count": restaurant.review_count,
        "reviewed_orders": len(reviews),
        "breakdown": breakdown,
    }


@router.get("/drivers/{driver_id}/reviews", response_model=List[ReviewResponse])
async def list_driver_reviews(
    driver_id: str,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
):
    reviews = await _page(
        Review.find(Review.driver_id == driver_id).sort("-created_at"), offset, limit
    ).to_list()
    return [_to_response(r) for r in reviews]


@router.get("/drivers/{driver_id}/summary")
async def driver_rating_summary(driver_id: str):
    """Everything the driver app's ratings screen renders, in one call.

    Ratings come from the driver's stored aggregate (folded on write); the
    performance rates come from `app.rating.service.driver_performance`. Any
    rate that cannot be measured yet is `null`, never a misleading 0.
    """
    driver = await User.get(driver_id)
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    reviews = await Review.find(Review.driver_id == driver_id).sort("-created_at").to_list()
    rated = [r.driver_rating for r in reviews if r.driver_rating is not None]

    breakdown = {str(star): 0 for star in range(1, 6)}
    for stars in rated:
        if stars in (1, 2, 3, 4, 5):
            breakdown[str(stars)] += 1

    recent = []
    for review in reviews[:RECENT_FEEDBACK_LIMIT]:
        if review.driver_rating is None:
            continue
        name = None
        try:
            consumer = await User.get(review.consumer_id)
            name = consumer.full_name if consumer else None
        except Exception:
            name = None
        created_at = getattr(review, "created_at", None)
        recent.append(
            {
                "customer_name": _mask_name(name),
                "rating": review.driver_rating,
                "comment": getattr(review, "comment", None) or "",
                "tags": list(getattr(review, "tags", None) or []),
                "created_at": created_at.isoformat() if created_at else None,
            }
        )

    performance = await driver_performance(driver_id)

    return {
        "driver_id": driver_id,
        "driver_rating": driver.driver_rating,
        "driver_review_count": driver.driver_review_count,
        "rated_reviews": len(rated),
        "breakdown": breakdown,
        "recent_feedback": recent,
        "on_time_sla_minutes": ON_TIME_SLA_MINUTES,
        **performance,
    }
