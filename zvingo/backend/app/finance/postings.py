"""Standard ledger postings.

One place that knows what set of balanced entries each money event produces, so
the shape of a charge or a payout cannot drift between the payment service, the
earnings endpoint and the refund workflow.

Money moves in three events, in this order:

1. :func:`build_charge_posting` — the consumer pays. The platform receives the
   whole charge and immediately owes the merchant for the food. It keeps the
   delivery fee, service fee, tax and tip **on hand**, because at the moment of
   payment no driver has been assigned yet.
2. :func:`build_driver_payout_posting` — the delivery completes and a driver is
   known. The platform hands over that driver's share of the delivery fee plus
   100% of the tip.
3. :func:`build_refund_posting` — money goes back to the consumer, posted only
   once a human has confirmed the provider actually returned it.

Every posting balances to zero, and every posting carries a deterministic
idempotency key derived from the payment or order, so replaying an event is a
no-op rather than a double credit.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Optional

from app.finance.exchange import convert_minor
from app.finance.fee_calculator import FeeBreakdown
from app.finance.ledger import (
    PLATFORM_PARTY_ID,
    EntryType,
    LedgerPosting,
    PartyType,
)
from app.finance.money import DEFAULT_CURRENCY

__all__ = [
    "charge_key",
    "driver_payout_key",
    "refund_key",
    "build_charge_posting",
    "build_driver_payout_posting",
    "build_refund_posting",
]


def charge_key(payment_id: str) -> str:
    return f"payment:{payment_id}:charge"


def driver_payout_key(order_id: str, driver_id: str) -> str:
    return f"order:{order_id}:driver-payout:{driver_id}"


def refund_key(refund_id: str) -> str:
    return f"refund:{refund_id}:settled"


def build_charge_posting(
    *,
    payment_id: str,
    order_id: str,
    consumer_id: str,
    merchant_id: str,
    total_minor: int,
    currency: str = DEFAULT_CURRENCY,
    breakdown: Optional[FeeBreakdown] = None,
    fx_rate: Optional[Decimal] = None,
) -> LedgerPosting:
    """Consumer pays ``total_minor``; the platform books what it owes the merchant.

    When ``currency`` is not USD the breakdown's USD splits are converted at the
    rate pinned to this payment. Conversion rounding is absorbed by the platform
    line — it is derived as the remainder, never rounded separately — so the
    posting still balances to the exact cent that was charged.
    """
    posting = LedgerPosting(
        idempotency_key=charge_key(payment_id),
        currency=currency,
        order_id=order_id,
        payment_id=payment_id,
    )

    total = int(total_minor)
    posting.add(
        EntryType.CHARGE,
        PartyType.CONSUMER,
        -total,
        party_id=consumer_id,
        memo=f"Payment for order {order_id}",
    )
    posting.add(
        EntryType.CHARGE,
        PartyType.PLATFORM,
        total,
        party_id=PLATFORM_PARTY_ID,
        memo=f"Collected for order {order_id}",
    )

    merchant_minor = 0
    if breakdown is not None:
        merchant_minor = breakdown.merchant_payout_minor
        if currency != DEFAULT_CURRENCY and fx_rate is not None:
            merchant_minor = convert_minor(merchant_minor, fx_rate, currency)
        # Never book a merchant obligation larger than the money collected.
        merchant_minor = max(0, min(merchant_minor, total))

    if merchant_minor:
        posting.add(
            EntryType.MERCHANT_PAYOUT,
            PartyType.PLATFORM,
            -merchant_minor,
            party_id=PLATFORM_PARTY_ID,
            memo=f"Owed to merchant for order {order_id}",
        )
        posting.add(
            EntryType.MERCHANT_PAYOUT,
            PartyType.MERCHANT,
            merchant_minor,
            party_id=merchant_id,
            memo=f"Food subtotal for order {order_id}",
        )

    return posting


def build_driver_payout_posting(
    *,
    order_id: str,
    driver_id: str,
    driver_share_minor: int,
    tip_minor: int = 0,
    currency: str = DEFAULT_CURRENCY,
    payment_id: Optional[str] = None,
) -> LedgerPosting:
    """The platform hands the driver their fee share and the full tip."""
    posting = LedgerPosting(
        idempotency_key=driver_payout_key(order_id, driver_id),
        currency=currency,
        order_id=order_id,
        payment_id=payment_id,
    )
    share = int(driver_share_minor)
    tip = int(tip_minor)
    total = share + tip
    if total == 0:
        return posting

    posting.add(
        EntryType.DRIVER_PAYOUT,
        PartyType.PLATFORM,
        -total,
        party_id=PLATFORM_PARTY_ID,
        memo=f"Driver payout for order {order_id}",
    )
    if share:
        posting.add(
            EntryType.DRIVER_PAYOUT,
            PartyType.DRIVER,
            share,
            party_id=driver_id,
            memo=f"Delivery fee share for order {order_id}",
        )
    if tip:
        posting.add(
            EntryType.TIP,
            PartyType.DRIVER,
            tip,
            party_id=driver_id,
            memo=f"Tip for order {order_id}",
        )
    return posting


def build_refund_posting(
    *,
    refund_id: str,
    payment_id: str,
    order_id: str,
    consumer_id: str,
    amount_minor: int,
    currency: str = DEFAULT_CURRENCY,
) -> LedgerPosting:
    """Money returned to the consumer — posted only once it has actually moved."""
    posting = LedgerPosting(
        idempotency_key=refund_key(refund_id),
        currency=currency,
        order_id=order_id,
        payment_id=payment_id,
    )
    amount = int(amount_minor)
    if amount <= 0:
        return posting
    posting.add(
        EntryType.REFUND,
        PartyType.PLATFORM,
        -amount,
        party_id=PLATFORM_PARTY_ID,
        memo=f"Refund for order {order_id}",
    )
    posting.add(
        EntryType.REFUND,
        PartyType.CONSUMER,
        amount,
        party_id=consumer_id,
        memo=f"Refund for order {order_id}",
    )
    return posting
