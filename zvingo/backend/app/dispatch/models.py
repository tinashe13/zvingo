from typing import Optional
from beanie import Document
from datetime import datetime
from pydantic import Field
from app.time_utils import utc_now

class Dispatch(Document):
    order_id: str
    driver_id: Optional[str] = None
    status: str = "PENDING" # PENDING, ASSIGNED, COMPLETED
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "dispatches"
