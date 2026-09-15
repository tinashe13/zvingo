"""Per-user notification preferences.

Consumers, drivers and merchants all get order-lifecycle pushes; only
consumers get marketing. Without a preferences record the platform has exactly
one setting — "everything, always" — which is how an app earns a system-level
notification block.

Defaults are opt-in for anything transactional and opt-in for promotions too
(Zimbabwe has no separate marketing-consent regime here), but *every* channel
is switchable and quiet hours suppress non-urgent pushes overnight.
"""

from datetime import datetime
from typing import Optional

from beanie import Document, Indexed
from pydantic import Field

from app.catalog.hours import DEFAULT_TIMEZONE
from app.time_utils import utc_now

#: Categories a notification can belong to. `order_updates` is transactional
#: and deliberately cannot be silenced by quiet hours — a driver arriving at
#: your door at 23:30 is not spam.
CATEGORIES = ("order_updates", "chat_messages", "driver_offers", "promotions")

URGENT_CATEGORIES = ("order_updates", "driver_offers")


class NotificationPreference(Document):
    user_id: Indexed(str, unique=True)  # type: ignore

    # Channels
    push_enabled: bool = True
    sms_enabled: bool = True

    # Categories
    order_updates: bool = True
    chat_messages: bool = True
    driver_offers: bool = True
    promotions: bool = True

    # Quiet hours, local wall-clock "HH:MM". Both must be set to take effect;
    # a window whose end is <= start spans midnight (e.g. 22:00 → 07:00).
    quiet_hours_start: Optional[str] = None
    quiet_hours_end: Optional[str] = None
    timezone: str = DEFAULT_TIMEZONE

    updated_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "notification_preferences"
        indexes = [
            [("user_id", 1)],
        ]
