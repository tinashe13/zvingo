"""Payment documents.

**Money on these documents is stored as integer minor units.** ``amount_usd``
and ``amount_local`` still exist and still read as floats, but they are now
read-only *derived* views of ``amount_usd_cents`` / ``amount_local_cents``,
computed at the presentation boundary (see :mod:`app.finance.money`). Nothing
writes a float amount any more.

Documents written before this change stored floats under ``amount_usd`` /
``amount_local`` and have no ``*_cents`` fields. A ``before`` validator folds
those legacy values into minor units on load, going through ``str`` so
``10.1`` becomes ``1010`` and not ``1009``. Old rows therefore keep reading
correctly and are rewritten in minor units the next time they are saved — there
is no half-migrated state where some code reads cents and some reads a float
that has drifted away from it.
"""

from typing import Any, Dict, Optional
from datetime import datetime
from app.time_utils import utc_now
from enum import Enum
from beanie import Document, Indexed
from pydantic import Field, model_validator

from app.finance.money import (
    DEFAULT_CURRENCY,
    is_supported_currency,
    format_money,
    minor_to_decimal,
    minor_to_float,
    to_minor,
)


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
    REFUND_PENDING = "REFUND_PENDING"
    REFUNDED = "REFUNDED"
    CANCELLED = "CANCELLED"
    EXPIRED = "EXPIRED"


class Payment(Document):
    order_id: str = Indexed()
    consumer_id: str = Indexed()

    # ── Money: integer minor units are canonical ────────────────────
    amount_usd_cents: int = 0     # priced amount, always USD cents
    amount_local_cents: int = 0   # amount actually charged, in `currency`
    currency: str = DEFAULT_CURRENCY

    # Exchange rate pinned to this charge (micro-units, 1e-6), so the payment
    # record itself carries the rate it was converted at — auditable forever.
    fx_rate_micros: Optional[int] = None
    fx_source: Optional[str] = None
    fx_effective_at: Optional[datetime] = None
    fx_pinned_at: Optional[datetime] = None

    # Full fee breakdown captured at initiation (minor units). Frozen evidence
    # of what the customer was told they were paying for.
    breakdown: Optional[Dict[str, Any]] = None

    method: PaymentMethod
    status: PaymentStatus = PaymentStatus.PENDING
    paynow_reference: Optional[str] = None
    poll_url: Optional[str] = None
    phone: Optional[str] = None

    # Set when a refund workflow is opened against this payment.
    refund_request_id: Optional[str] = None

    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "payments"
        indexes = [
            [("paynow_reference", 1)],
            [("status", 1), ("updated_at", -1)],
        ]

    @model_validator(mode="before")
    @classmethod
    def _fold_legacy_float_amounts(cls, data):
        """Accept legacy float ``amount_usd``/``amount_local`` and store cents.

        Applies both to documents loaded from MongoDB and to keyword
        construction, so callers that have not been updated still produce a
        correct record rather than a silent zero.
        """
        if not isinstance(data, dict):
            return data
        data = dict(data)
        currency = str(data.get("currency") or DEFAULT_CURRENCY).upper()
        conversion_currency = currency if is_supported_currency(currency) else DEFAULT_CURRENCY

        legacy_usd = data.pop("amount_usd", None)
        if data.get("amount_usd_cents") is None and legacy_usd is not None:
            data["amount_usd_cents"] = to_minor(legacy_usd, DEFAULT_CURRENCY)

        legacy_local = data.pop("amount_local", None)
        if data.get("amount_local_cents") is None and legacy_local is not None:
            data["amount_local_cents"] = to_minor(legacy_local, conversion_currency)

        # A legacy record with only a USD amount charged in USD.
        if data.get("amount_local_cents") is None and data.get("amount_usd_cents") is not None:
            if conversion_currency == DEFAULT_CURRENCY:
                data["amount_local_cents"] = data["amount_usd_cents"]
        return data

    # ── Presentation boundary ───────────────────────────────────────
    # Read-only float views for API responses and the admin console. Assigning
    # to them raises, which is deliberate: writes go to the cents fields.

    @property
    def amount_usd(self) -> float:
        return minor_to_float(self.amount_usd_cents, DEFAULT_CURRENCY)

    @property
    def amount_local(self) -> float:
        currency = self.currency if is_supported_currency(self.currency) else DEFAULT_CURRENCY
        return minor_to_float(self.amount_local_cents, currency)

    @property
    def amount_usd_decimal(self):
        return minor_to_decimal(self.amount_usd_cents, DEFAULT_CURRENCY)

    @property
    def charge_amount_minor(self) -> int:
        """What the provider is actually asked to collect, in ``currency``."""
        return self.amount_local_cents or self.amount_usd_cents

    @property
    def charge_currency(self) -> str:
        return self.currency if is_supported_currency(self.currency) else DEFAULT_CURRENCY

    def display_amount(self) -> str:
        return format_money(self.charge_amount_minor, self.charge_currency)


class RefundStatus(str, Enum):
    """Lifecycle of a refund request.

    ``PENDING_MANUAL`` is the important one: it means Zvingo has accepted that
    it owes the customer money but the money has **not** moved yet, because
    Paynow Zimbabwe exposes no programmatic refund. A refund never reads as
    complete until a human records the provider reference that proves it.
    """

    REQUESTED = "REQUESTED"
    PENDING_MANUAL = "PENDING_MANUAL"
    COMPLETED = "COMPLETED"
    REJECTED = "REJECTED"
    FAILED = "FAILED"


class RefundRequest(Document):
    """Auditable record of a refund from request to settlement."""

    payment_id: Indexed(str)  # type: ignore
    order_id: Indexed(str)  # type: ignore
    consumer_id: str = ""

    amount_minor: int = 0
    currency: str = DEFAULT_CURRENCY

    status: RefundStatus = RefundStatus.REQUESTED
    reason: str = ""

    requested_by: str = ""
    requested_at: datetime = Field(default_factory=utc_now)

    provider: str = "paynow"
    provider_reference: Optional[str] = None   # original Paynow transaction ref
    external_reference: Optional[str] = None   # proof the money was returned

    resolved_by: Optional[str] = None
    resolved_at: Optional[datetime] = None
    resolution_note: str = ""

    ledger_posted: bool = False
    updated_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "refund_requests"
        indexes = [
            [("payment_id", 1)],
            [("status", 1), ("requested_at", -1)],
        ]

    def display_amount(self) -> str:
        return format_money(self.amount_minor, self.currency)


class NotificationSource(str, Enum):
    WEBHOOK = "WEBHOOK"
    POLL = "POLL"
    MANUAL = "MANUAL"
    MOCK = "MOCK"


class PaymentNotification(Document):
    """Every provider notification we have ever acted on — the idempotency log.

    ``dedupe_key`` is a hash of the payment, the reported status and the
    reported amount. Paynow retries its result-URL callback until it gets a
    2xx, so the same notification arrives repeatedly; inserting the key first
    and letting the unique index reject a duplicate is what stops a retry from
    double-crediting, double-refunding or re-triggering dispatch.
    """

    dedupe_key: Indexed(str, unique=True)  # type: ignore

    payment_id: Optional[Indexed(str)] = None  # type: ignore
    order_id: Optional[str] = None
    reference: str = ""
    paynow_reference: Optional[str] = None

    source: NotificationSource = NotificationSource.WEBHOOK
    reported_status: str = ""
    reported_amount_minor: Optional[int] = None
    currency: str = DEFAULT_CURRENCY

    signature_verified: bool = False
    accepted: bool = False
    action: str = ""          # what the notification caused, for audit
    anomaly: Optional[str] = None  # set when the notification looked wrong

    payload: Dict[str, Any] = Field(default_factory=dict)
    created_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "payment_notifications"
        indexes = [
            [("payment_id", 1), ("created_at", -1)],
            [("created_at", -1)],
        ]
