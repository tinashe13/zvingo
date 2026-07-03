from typing import List, Optional
from beanie import Document, Indexed
from pydantic import BaseModel, Field
import uuid


class Location(BaseModel):
    type: str = "Point"
    coordinates: List[float]  # [longitude, latitude]


class MenuItem(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    name: str
    description: Optional[str] = None
    price_usd: float
    category: str
    is_available: bool = True
    image_url: Optional[str] = None
    images: List[str] = []
    approval_percent: Optional[int] = None   # e.g. 74 for "74% liked"
    approval_count: Optional[int] = None     # e.g. 131 ratings
    is_great_price: bool = False


class Restaurant(Document):
    merchant_id: Optional[Indexed(str)] = None
    name: str
    description: Optional[str] = None
    location: Location
    rating: float = 4.5
    delivery_time_min: int = 30
    delivery_time_max: int = 45
    delivery_fee_usd: float = 2.00
    is_active: bool = True
    categories: List[str] = []
    dietary_tags: List[str] = []  # e.g. ["Vegetarian", "Vegan", "Gluten-Free"]
    operating_hours: Optional[str] = None  # e.g. "Mon-Fri 9am-10pm"
    image_url: Optional[str] = None
    banner_url: Optional[str] = None
    address: str = ""
    promotions: List[str] = []
    menu: List[MenuItem] = []
    review_count: Optional[int] = None           # e.g. 4000
    neighbors_liked: Optional[int] = None        # e.g. 4
    customer_photos_count: Optional[int] = None  # e.g. 12
    free_delivery_threshold: Optional[float] = None  # min order for free delivery, e.g. 12.00
    is_zvingo_plus: bool = False                 # whether restaurant is in Zvingo+ program

    class Settings:
        name = "restaurants"
        indexes = [
            [("location", "2dsphere")]
        ]
