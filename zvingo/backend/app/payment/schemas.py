from pydantic import BaseModel, Field, field_validator
from typing import Any, Dict, Optional
from datetime import datetime

from app.finance.money import DEFAULT_CURRENCY, is_supported_currency
from app.payment.models import PaymentMethod, PaymentStatus, RefundStatus


class PaymentInitiate(BaseModel):
    order_id: str
    method: PaymentMethod
    phone: str
    currency: str = DEFAULT_CURRENCY

    @field_validator("currency")
    @classmethod
    def _known_currency(cls, value: str) -> str:
        """Reject a currency Zvingo cannot settle in, before any money moves."""
        code = (value or DEFAULT_CURRENCY).strip().upper()
        if not is_supported_currency(code):
            raise ValueError(f"Unsupported currency {code!r}")
        return code


class PaymentResponse(BaseModel):
    """Payment as shown to a client.

    ``*_minor`` fields are the contract — integer minor units, exact. The
    ``amount_usd`` / ``amount_local`` floats are the presentation view kept for
    existing clients and should not be used for arithmetic.
    """

    id: str
    order_id: str
    amount_usd: float
    amount_local: float
    amount_usd_minor: int = 0
    amount_local_minor: int = 0
    currency: str
    method: PaymentMethod
    status: PaymentStatus
    paynow_reference: Optional[str] = None
    created_at: datetime
    display_amount: Optional[str] = None
    refund_status: Optional[RefundStatus] = None
    breakdown: Optional[Dict[str, Any]] = None


class PaymentWebhook(BaseModel):
    reference: Optional[str] = None
    paynowreference: Optional[str] = None
    amount: Optional[str] = None
    status: Optional[str] = None
    pollurl: Optional[str] = None
    hash: Optional[str] = None


class RefundRequestCreate(BaseModel):
    reason: str = ""
    amount_minor: Optional[int] = Field(
        default=None, description="Partial refund in minor units; omit for a full refund"
    )


class RefundResolve(BaseModel):
    """Payload used by an operator to close out a manual refund."""

    external_reference: str = Field(
        description="Paynow portal reference proving the money was returned"
    )
    note: str = ""


class RefundReject(BaseModel):
    """Payload used to close a refund request without moving money."""

    note: str = ""


class RefundResponse(BaseModel):
    id: str
    payment_id: str
    order_id: str
    amount_minor: int
    currency: str
    status: RefundStatus
    reason: str = ""
    requested_by: str = ""
    requested_at: datetime
    external_reference: Optional[str] = None
    resolved_by: Optional[str] = None
    resolved_at: Optional[datetime] = None
    resolution_note: str = ""
    ledger_posted: bool = False
    display_amount: Optional[str] = None
