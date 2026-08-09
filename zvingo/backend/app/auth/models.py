from typing import Optional, List
from datetime import datetime
from app.time_utils import utc_now
from beanie import Document, Indexed
from pydantic import EmailStr, Field, BaseModel

class Location(BaseModel):
    type: str = "Point"
    coordinates: List[float]  # [longitude, latitude]

class User(Document):
    email: Optional[EmailStr] = Indexed(default=None, unique=True, sparse=True)
    phone: str = Indexed(unique=True)
    hashed_password: str
    full_name: str
    role: str = "driver"
    is_active: bool = True
    created_at: datetime = Field(default_factory=utc_now)
    
    # Favourites
    favourite_restaurant_ids: List[str] = []
    
    # BinProto Session
    binproto_session_key: Optional[str] = None

    # Push notifications
    fcm_token: Optional[str] = None

    # Dashing Status
    is_dashing: bool = False
    current_location: Optional[Location] = None
    dash_radius: int = 10 # miles

    class Settings:
        name = "users"
        indexes = [
            [("current_location", "2dsphere")]
        ]
