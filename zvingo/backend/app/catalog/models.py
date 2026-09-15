from datetime import datetime
from typing import List, Optional
from beanie import Document, Indexed
from pydantic import BaseModel, Field, PrivateAttr, computed_field
import uuid

from app.catalog.hours import DEFAULT_TIMEZONE, DayHours, availability_of
from app.location.models import Location


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

    # ── Availability ────────────────────────────────────────────────
    # `hours` is the authoritative structured weekly schedule in `timezone`
    # local time; `operating_hours` is the human-readable summary derived from
    # it (kept for older clients that render the raw string).
    hours: List[DayHours] = []
    timezone: str = DEFAULT_TIMEZONE
    operating_hours: Optional[str] = None  # e.g. "Mon-Fri 08:00-22:00"
    # Manual merchant override: None follows `hours`, True forces open,
    # False forces closed ("we're slammed, stop the orders").
    is_open_override: Optional[bool] = None
    # Temporary snooze (naive UTC). Beats the schedule until it elapses.
    pause_until: Optional[datetime] = None
    # Whether consumers may still place a scheduled order while closed.
    accepts_scheduled_orders: bool = True

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

    # Per-request discovery metadata (relevance score, distance, matched menu
    # items). A PrivateAttr is deliberately *not* a model field, so Beanie never
    # writes it to MongoDB, while the computed field below still surfaces it in
    # API responses.
    _discovery: Optional[dict] = PrivateAttr(default=None)

    @computed_field  # type: ignore[prop-decorator]
    @property
    def availability(self) -> dict:
        """Live open/closed state — see `app.catalog.hours.compute_availability`."""
        return availability_of(self)

    @computed_field  # type: ignore[prop-decorator]
    @property
    def is_currently_open(self) -> bool:
        """Convenience flag mirroring ``availability.is_open``."""
        return bool(self.availability["is_open"])

    @computed_field  # type: ignore[prop-decorator]
    @property
    def discovery(self) -> Optional[dict]:
        """Ranking metadata, populated only by search / nearby responses."""
        return self._discovery

    class Settings:
        name = "restaurants"
        indexes = [
            [("location", "2dsphere")],
            # Text index powering fuzzy catalog search across the fields a
            # consumer actually types: brand, blurb, cuisine, and dish names.
            [
                ("name", "text"),
                ("description", "text"),
                ("categories", "text"),
                ("menu.name", "text"),
                ("menu.category", "text"),
            ],
            [("is_active", 1), ("rating", -1)],
            [("merchant_id", 1), ("is_active", 1)],
            [("categories", 1)],
        ]
