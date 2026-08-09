from typing import Optional
from datetime import datetime
from app.time_utils import utc_now
from enum import Enum
from beanie import Document, Indexed
from pydantic import Field


class PaymentMethod(str, Enum):
    ECOCASH = "ECOCASH"
    ONEMONEY = "ONEMONEY"
    INNBUCKS = "INNBUCKS"
    CARD = "CARD"


class PaymentStatus(str, Enum):
    PENDING = "PENDING"
    AWAITING_DELIVERY = "AWAITING_DELIVERY"
    PAID = "PAID"
    FAILED = "FAILED"
    REFUNDED = "REFUNDED"
    CANCELLED = "CANCELLED"


class Payment(Document):
    order_id: str = Indexed()
    consumer_id: str = Indexed()
    amount_usd: float
    amount_local: float = 0.0
    currency: str = "USD"
    method: PaymentMethod
    status: PaymentStatus = PaymentStatus.PENDING
    paynow_reference: Optional[str] = None
    poll_url: Optional[str] = None
    phone: Optional[str] = None
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "payments"
