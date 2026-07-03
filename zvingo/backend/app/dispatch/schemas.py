from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class DriverLocationUpdate(BaseModel):
    driver_id: str
    lat: float
    lng: float
    status: str = "ONLINE" # ONLINE, BUSY, OFFLINE
    battery: Optional[int] = None
    timestamp: datetime = datetime.utcnow()
