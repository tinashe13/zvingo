from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class ReviewCreate(BaseModel):
    restaurant_rating: int
    driver_rating: Optional[int] = None
    comment: Optional[str] = None


class ReviewResponse(BaseModel):
    id: str
    order_id: str
    consumer_id: str
    restaurant_id: str
    driver_id: Optional[str] = None
    restaurant_rating: int
    driver_rating: Optional[int] = None
    comment: Optional[str] = None
    created_at: datetime
