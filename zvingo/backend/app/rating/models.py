"""Ratings & reviews for orders, drivers, and restaurants."""

from typing import List, Optional
from datetime import datetime
from app.time_utils import utc_now
from beanie import Document, Indexed
from pydantic import BaseModel, Field


class Rating(BaseModel):
    """An individual star rating with optional comment."""

    stars: int = Field(ge=1, le=5)
    comment: Optional[str] = None
    created_at: datetime = Field(default_factory=utc_now)


class Review(Document):
    """A consumer's review of a delivered order.

    One review per order. It captures ratings for the restaurant and, when a
    driver was involved, the driver. Aggregates are stored on the restaurant
    (rating / review_count) and driver documents.
    """

    order_id: Indexed(str, unique=True)
    consumer_id: Indexed(str)
    restaurant_id: Indexed(str)
    driver_id: Optional[Indexed(str)] = None

    restaurant_rating: int = Field(ge=1, le=5)
    driver_rating: Optional[int] = Field(default=None, ge=1, le=5)
    comment: Optional[str] = None
    #: Structured quick-feedback chips picked in the review sheet.
    tags: List[str] = []

    created_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "reviews"
        indexes = [
            [("consumer_id", 1), ("created_at", -1)],
            [("restaurant_id", 1), ("created_at", -1)],
            [("driver_id", 1), ("created_at", -1)],
        ]
