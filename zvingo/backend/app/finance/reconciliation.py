"""Financial reconciliation checks.

Every one of these answers a question an operator (or an auditor) will
eventually ask, and each is designed to surface a *specific* failure mode
rather than a vague "something looks off":

* :func:`stuck_payments` — a customer's money is in limbo: Paynow was asked to
  collect but never told us the outcome, and the order is frozen.
* :func:`orders_paid_without_payment` — an order is being fulfilled past the
  point that requires payment, with no settled payment record behind it. This
  is the free-food signature.
* :func:`payments_missing_ledger` — a settled payment with no ledger entries,
  so driver earnings and merchant payouts derived from the ledger will be
  short.
* :func:`unbalanced_postings` — a posting whose signed amounts do not sum to
  zero. Should be impossible (``LedgerPosting.validate_balanced`` blocks it at
  write time); if it ever appears, the ledger has been written around.
* :func:`pending_manual_refunds` — money Zvingo has promised back and not yet
  returned.

They are read-only. Nothing here repairs anything automatically: a money
discrepancy is for a human to understand first.
"""

from __future__ import annotations

from datetime import timedelta
from typing import Any, Dict, List

import structlog

from app.finance.ledger import LedgerEntry
from app.finance.money import format_money
from app.payment.models import Payment, PaymentStatus, RefundRequest, RefundStatus
from app.time_utils import utc_now

logger = structlog.get_logger()

__all__ = [
    "DEFAULT_STUCK_MINUTES",
    "stuck_payments",
    "orders_paid_without_payment",
    "payments_missing_ledger",
    "unbalanced_postings",
    "pending_manual_refunds",
    "run_reconciliation",
]

DEFAULT_STUCK_MINUTES = 30

# Order states that can only be reached after the customer has paid. An order
# sitting in one of these without a settled payment is the thing to catch.
_POST_PAYMENT_ORDER_STATES = (
    "OFFERED",
    "ACCEPTED",
    "ARRIVED_AT_MERCHANT",
    "READY_FOR_PICKUP",
    "PICKED_UP",
    "ARRIVED_AT_CUSTOMER",
    "DELIVERED",
)

_SETTLED_PAYMENT_STATES = (
    PaymentStatus.PAID.value,
    PaymentStatus.REFUND_PENDING.value,
    PaymentStatus.REFUNDED.value,
)


async def stuck_payments(minutes: int = DEFAULT_STUCK_MINUTES) -> List[Dict[str, Any]]:
    """Payments left un-settled for longer than ``minutes``."""
    cutoff = utc_now() - timedelta(minutes=minutes)
    rows = await Payment.find(
        {
            "status": {
                "$in": [
                    PaymentStatus.PENDING.value,
                    PaymentStatus.AWAITING_DELIVERY.value,
                ]
            },
            "updated_at": {"$lt": cutoff},
        }
    ).to_list()
    return [
        {
            "payment_id": str(p.id),
            "order_id": p.order_id,
            "consumer_id": p.consumer_id,
            "status": p.status.value,
            "amount": p.display_amount(),
            "amount_minor": p.charge_amount_minor,
            "currency": p.charge_currency,
            "stuck_since": p.updated_at.isoformat(),
            "paynow_reference": p.paynow_reference,
        }
        for p in rows
    ]


async def orders_paid_without_payment() -> List[Dict[str, Any]]:
    """Orders past the payment gate with no settled payment record.

    Self-pickup and cash orders legitimately have no Paynow payment, so the
    result flags them separately rather than treating every hit as fraud.
    """
    from app.order.models import Order

    orders = await Order.find(
        {"state": {"$in": list(_POST_PAYMENT_ORDER_STATES)}}
    ).to_list()
    if not orders:
        return []

    order_ids = [str(o.id) for o in orders]
    payments = await Payment.find({"order_id": {"$in": order_ids}}).to_list()
    settled = {
        p.order_id for p in payments if p.status.value in _SETTLED_PAYMENT_STATES
    }
    seen = {p.order_id for p in payments}

    findings = []
    for order in orders:
        oid = str(order.id)
        if oid in settled:
            continue
        findings.append(
            {
                "order_id": oid,
                "state": getattr(order.state, "value", str(order.state)),
                "consumer_id": order.consumer_id,
                "merchant_id": order.merchant_id,
                "has_payment_record": oid in seen,
                "is_pickup": bool(getattr(order, "is_pickup", False)),
                "created_at": order.created_at.isoformat(),
            }
        )
    return findings


async def payments_missing_ledger() -> List[Dict[str, Any]]:
    """Settled payments with no ledger entries behind them."""
    payments = await Payment.find(
        {"status": {"$in": list(_SETTLED_PAYMENT_STATES)}}
    ).to_list()
    if not payments:
        return []

    payment_ids = [str(p.id) for p in payments]
    entries = await LedgerEntry.find({"payment_id": {"$in": payment_ids}}).to_list()
    with_entries = {e.payment_id for e in entries}

    return [
        {
            "payment_id": str(p.id),
            "order_id": p.order_id,
            "status": p.status.value,
            "amount": p.display_amount(),
            "amount_minor": p.charge_amount_minor,
            "currency": p.charge_currency,
            "settled_at": p.updated_at.isoformat(),
        }
        for p in payments
        if str(p.id) not in with_entries
    ]


async def unbalanced_postings() -> List[Dict[str, Any]]:
    """Ledger postings whose signed amounts do not sum to zero."""
    entries = await LedgerEntry.find_all().to_list()
    grouped: Dict[str, List[LedgerEntry]] = {}
    for entry in entries:
        grouped.setdefault(entry.posting_id, []).append(entry)

    findings = []
    for posting_id, group in grouped.items():
        by_currency: Dict[str, int] = {}
        for entry in group:
            by_currency[entry.currency] = by_currency.get(entry.currency, 0) + int(
                entry.amount_minor
            )
        for currency, residual in by_currency.items():
            if residual != 0:
                findings.append(
                    {
                        "posting_id": posting_id,
                        "currency": currency,
                        "residual_minor": residual,
                        "residual": format_money(residual, currency),
                        "order_id": group[0].order_id,
                        "payment_id": group[0].payment_id,
                        "entries": [e.describe() for e in group],
                    }
                )
    return findings


async def pending_manual_refunds() -> List[Dict[str, Any]]:
    """Refunds Zvingo owes that have not been paid out yet."""
    rows = await RefundRequest.find(
        {
            "status": {
                "$in": [RefundStatus.PENDING_MANUAL.value, RefundStatus.REQUESTED.value]
            }
        }
    ).to_list()
    return [
        {
            "refund_id": str(r.id),
            "payment_id": r.payment_id,
            "order_id": r.order_id,
            "consumer_id": r.consumer_id,
            "amount": r.display_amount(),
            "amount_minor": r.amount_minor,
            "currency": r.currency,
            "status": r.status.value,
            "requested_at": r.requested_at.isoformat(),
            "reason": r.reason,
        }
        for r in rows
    ]


async def run_reconciliation(stuck_minutes: int = DEFAULT_STUCK_MINUTES) -> Dict[str, Any]:
    """Run every check and return one report, with a healthy/unhealthy verdict."""
    report: Dict[str, Any] = {
        "generated_at": utc_now().isoformat(),
        "stuck_minutes": stuck_minutes,
    }
    checks = {
        "stuck_payments": lambda: stuck_payments(stuck_minutes),
        "orders_paid_without_payment": orders_paid_without_payment,
        "payments_missing_ledger": payments_missing_ledger,
        "unbalanced_postings": unbalanced_postings,
        "pending_manual_refunds": pending_manual_refunds,
    }

    issues = 0
    for name, check in checks.items():
        try:
            findings = await check()
        except Exception as exc:
            logger.error("Reconciliation check failed", check=name, error=str(exc))
            report[name] = {"error": str(exc), "count": None}
            issues += 1
            continue
        report[name] = {"count": len(findings), "findings": findings}
        issues += len(findings)

    report["healthy"] = issues == 0
    report["issue_count"] = issues
    return report
