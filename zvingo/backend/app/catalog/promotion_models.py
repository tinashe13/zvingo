from typing import Optional, List
from beanie import Document, Indexed
from pydantic import BaseModel, Field
from datetime import datetime
from app.time_utils import utc_now
import uuid


class Promotion(Document):
    """A promotional offer created by a merchant, shown to consumers."""

    promo_id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    merchant_id: Indexed(str)  # type: ignore  # The merchant who created this promo
    restaurant_id: Optional[str] = None  # Optionally scope to a specific restaurant

    title: str  # e.g. "$0 Delivery Fee"
    subtitle: str  # e.g. "On your first 3 orders"
    description: Optional[str] = None  # Longer description (optional)
    icon: str = "local_offer"  # Icon hint for mobile clients (delivery_dining, percent, card_giftcard, local_offer)

    # Promo type & value
    promo_type: str = "percentage"  # percentage | flat | free_delivery | free_item
    discount_value: float = 0.0  # e.g. 20 for 20%, or 5.00 for $5 off
    min_order_usd: float = 0.0  # Minimum order amount to qualify
    max_discount_usd: Optional[float] = None  # Cap on discount amount

    # Scheduling
    starts_at: datetime = Field(default_factory=utc_now)
    ends_at: Optional[datetime] = None  # None = no expiry
    is_active: bool = True

    # Usage limits
    max_uses: Optional[int] = None  # Total uses across all consumers
    max_uses_per_user: int = 1  # Per-consumer usage limit
    current_uses: int = 0

    # Promo code (optional — for code-based promos)
    code: Optional[str] = None

    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "promotions"
        indexes = [
            [("merchant_id", 1)],
            [("is_active", 1), ("ends_at", 1)],
            [("code", 1)],
        ]
