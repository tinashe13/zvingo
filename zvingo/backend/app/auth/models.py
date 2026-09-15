from typing import Optional, List
from datetime import datetime
from app.time_utils import utc_now
from beanie import Document, Indexed
from pydantic import EmailStr, Field

from app.location.models import Location

class User(Document):
    email: Optional[EmailStr] = Indexed(default=None, unique=True, sparse=True)
    phone: str = Indexed(unique=True)
    hashed_password: str
    full_name: str
    role: str = "driver"
    is_active: bool = True
    created_at: datetime = Field(default_factory=utc_now)

    # Credential cutoff: any access/refresh token issued before this instant
    # is rejected. Set on password reset and on "log out everywhere", which is
    # what stops a stolen session from outliving the password that leaked it.
    # Naive UTC, like every other datetime on this document.
    tokens_valid_from: Optional[datetime] = None


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

    # Driver schedule — list of {"day": int, "slots": [int]} entries.
    # day: 0=Mon … 6=Sun; slots: 0=Morning, 1=Afternoon, 2=Evening.
    schedule: List[dict] = []

    # Driver vehicle — {"make", "model", "color", "plate"}
    vehicle: Optional[dict] = None

    # Driver rating aggregate, maintained when consumers review a delivery.
    # `driver_rating` is None until the driver has been rated at least once.
    driver_rating: Optional[float] = None
    driver_review_count: int = 0

    class Settings:
        name = "users"
        indexes = [
            [("current_location", "2dsphere")]
        ]
