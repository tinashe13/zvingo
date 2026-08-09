"""
DriverEarning — ledger of completed deliveries for driver reconciliation.

Each record represents one completed delivery and stores the earnings
breakdown, masked addresses, and metadata needed for the earnings screen.
"""

import re
from typing import Optional
from datetime import datetime, date
from app.time_utils import utc_now
from beanie import Document, Indexed
from pydantic import Field


def mask_address(address: str) -> str:
    """
    Remove street numbers from an address for privacy.
    '14 Selous Ave, Harare' → '** Selous Ave, Harare'
    '123B Main Road' → '** Main Road'
    """
    if not address:
        return ""
    return re.sub(r"^\d+[A-Za-z]?\s+", "** ", address.strip())


class DriverEarning(Document):
    driver_id: Indexed(str)  # type: ignore
    order_id: Indexed(str)  # type: ignore

    # Merchant / route info
    merchant_name: str = ""
    pickup_area: str = ""      # masked address
    dropoff_area: str = ""     # masked address

    # Earnings breakdown (all in cents)
    delivery_fee_cents: int = 0        # gross delivery fee
    driver_earning_cents: int = 0      # 85% of gross fee
    tip_cents: int = 0
    total_earning_cents: int = 0       # driver_earning + tip

    # Metadata
    payment_method: str = "cash"       # cash / ecocash
    distance_km: float = 0.0
    completed_at: Indexed(datetime) = Field(default_factory=utc_now)  # type: ignore
    created_date: str = Field(default_factory=lambda: date.today().isoformat())

    class Settings:
        name = "driver_earnings"
        indexes = [
            [("driver_id", 1), ("completed_at", -1)],
            [("driver_id", 1), ("created_date", 1)],
        ]
