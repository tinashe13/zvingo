from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from app.time_utils import utc_now

class DriverLocationUpdate(BaseModel):
    driver_id: str
    lat: float
    lng: float
    status: str = "ONLINE" # ONLINE, BUSY, OFFLINE
    battery: Optional[int] = None
    timestamp: datetime = Field(default_factory=utc_now)
