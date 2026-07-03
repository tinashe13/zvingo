from typing import Optional
from beanie import Document
from datetime import datetime

class Dispatch(Document):
    order_id: str
    driver_id: Optional[str] = None
    status: str = "PENDING" # PENDING, ASSIGNED, COMPLETED
    created_at: datetime = datetime.utcnow()
    updated_at: datetime = datetime.utcnow()

    class Settings:
        name = "dispatches"
