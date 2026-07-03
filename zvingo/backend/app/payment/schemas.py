from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from app.payment.models import PaymentMethod, PaymentStatus


class PaymentInitiate(BaseModel):
    order_id: str
    method: PaymentMethod
    phone: str
    currency: str = "USD"


class PaymentResponse(BaseModel):
    id: str
    order_id: str
    amount_usd: float
    amount_local: float
    currency: str
    method: PaymentMethod
    status: PaymentStatus
    paynow_reference: Optional[str] = None
    created_at: datetime


class PaymentWebhook(BaseModel):
    reference: Optional[str] = None
    paynowreference: Optional[str] = None
    amount: Optional[str] = None
    status: Optional[str] = None
    pollurl: Optional[str] = None
    hash: Optional[str] = None
