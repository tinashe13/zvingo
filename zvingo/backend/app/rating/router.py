from fastapi import APIRouter, Depends, HTTPException
from typing import List
from app.rating.models import Review
from app.rating.schemas import ReviewCreate, ReviewResponse
from app.order.models import Order
from app.order.state_machine import OrderState
from app.rating.service import apply_driver_rating, apply_restaurant_rating
from app.auth.router import get_current_user
from app.auth.models import User

router = APIRouter()


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
        created_at=review.created_at,
    )


@router.post("/orders/{order_id}/review", response_model=ReviewResponse)
async def create_review(
    order_id: str, review_in: ReviewCreate, current_user: User = Depends(get_current_user)
):
    """Submit a review for a delivered order (one per order)."""
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

    review = Review(
        order_id=order_id,
        consumer_id=str(current_user.id),
        restaurant_id=order.merchant_id,
        driver_id=order.driver_id,
        restaurant_rating=review_in.restaurant_rating,
        driver_rating=review_in.driver_rating,
        comment=review_in.comment,
    )
    await review.insert()

    # Fold the new stars into the restaurant and driver aggregates.
    await apply_restaurant_rating(order.merchant_id, review.restaurant_rating)
    if review.driver_id and review.driver_rating is not None:
        await apply_driver_rating(review.driver_id, review.driver_rating)

    return _to_response(review)


@router.get("/restaurants/{restaurant_id}/reviews", response_model=List[ReviewResponse])
async def list_restaurant_reviews(restaurant_id: str):
    reviews = await Review.find(Review.restaurant_id == restaurant_id).sort(
        "-created_at"
    ).to_list()
    return [_to_response(r) for r in reviews]


@router.get("/drivers/{driver_id}/reviews", response_model=List[ReviewResponse])
async def list_driver_reviews(driver_id: str):
    reviews = await Review.find(Review.driver_id == driver_id).sort(
        "-created_at"
    ).to_list()
    return [_to_response(r) for r in reviews]


@router.get("/drivers/{driver_id}/summary")
async def driver_rating_summary(driver_id: str):
    """Aggregate rating for a driver, for the driver profile / ratings screen."""
    driver = await User.get(driver_id)
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    reviews = await Review.find(Review.driver_id == driver_id).to_list()
    rated = [r.driver_rating for r in reviews if r.driver_rating is not None]

    breakdown = {str(star): 0 for star in range(1, 6)}
    for stars in rated:
        breakdown[str(stars)] += 1

    return {
        "driver_id": driver_id,
        "driver_rating": driver.driver_rating,
        "driver_review_count": driver.driver_review_count,
        "rated_reviews": len(rated),
        "breakdown": breakdown,
    }
