from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime


class ReviewCreate(BaseModel):
    """A consumer's review of one delivered order.

    Star bounds are enforced here as well as on the stored document, so a bad
    payload is a 422 from FastAPI rather than a 500 from the model constructor.
    """

    restaurant_rating: int = Field(ge=1, le=5)
    driver_rating: Optional[int] = Field(default=None, ge=1, le=5)
    comment: Optional[str] = Field(default=None, max_length=2000)
    #: Optional structured feedback, e.g. ["Hot food", "Great packaging"].
    tags: List[str] = Field(default_factory=list, max_length=10)


class ReviewResponse(BaseModel):
    id: str
    order_id: str
    consumer_id: str
    restaurant_id: str
    driver_id: Optional[str] = None
    restaurant_rating: int
    driver_rating: Optional[int] = None
    comment: Optional[str] = None
    tags: List[str] = []
    created_at: datetime
