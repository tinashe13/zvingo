"""Payment HTTP surface.

The webhook is the security-critical endpoint here. Paynow's result-URL POST is
the only thing that tells Zvingo a customer has paid, and until this change it
was trusted unconditionally: anyone who could guess a reference could POST
``status=Paid`` and have an order dispatched for free. Every delivery now
verifies Paynow's SHA-512 hash before a single field is believed.
"""

from typing import List, Optional

import structlog
from fastapi import APIRouter, Depends, HTTPException, Request, status as http_status

from app.finance import exchange
from app.finance.fee_calculator import breakdown_for_order
from app.finance.money import minor_to_decimal
from app.payment.models import (
    NotificationSource,
    Payment,
    RefundRequest,
    RefundStatus,
)
from app.payment.schemas import (
    PaymentInitiate,
    PaymentResponse,
    RefundReject,
    RefundRequestCreate,
    RefundResolve,
    RefundResponse,
)
from app.payment.service import PaymentService
from app.payment.webhook_security import verify_webhook_fields
from app.order.models import Order
from app.auth.router import get_current_user, get_current_admin
from app.auth.models import User

logger = structlog.get_logger()

router = APIRouter()


def _payment_to_response(p: Payment) -> PaymentResponse:
    return PaymentResponse(
        id=str(p.id),
        order_id=p.order_id,
        amount_usd=p.amount_usd,
        amount_local=p.amount_local,
        amount_usd_minor=getattr(p, "amount_usd_cents", 0) or 0,
        amount_local_minor=getattr(p, "amount_local_cents", 0) or 0,
        currency=p.currency,
        method=p.method,
        status=p.status,
        paynow_reference=p.paynow_reference,
        created_at=p.created_at,
        display_amount=p.display_amount() if hasattr(p, "display_amount") else None,
        breakdown=getattr(p, "breakdown", None),
    )


def _refund_to_response(r: RefundRequest) -> RefundResponse:
    return RefundResponse(
        id=str(r.id),
        payment_id=r.payment_id,
        order_id=r.order_id,
        amount_minor=r.amount_minor,
        currency=r.currency,
        status=r.status,
        reason=r.reason,
        requested_by=r.requested_by,
        requested_at=r.requested_at,
        external_reference=r.external_reference,
        resolved_by=r.resolved_by,
        resolved_at=r.resolved_at,
        resolution_note=r.resolution_note,
        ledger_posted=r.ledger_posted,
        display_amount=r.display_amount(),
    )


@router.post("/initiate", response_model=PaymentResponse)
async def initiate_payment(req: PaymentInitiate, current_user: User = Depends(get_current_user)):
    order = await Order.get(req.order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if order.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not your order")

    existing = await PaymentService.get_payment_for_order(req.order_id)
    if existing and existing.status.value in ("PAID", "AWAITING_DELIVERY", "REFUND_PENDING"):
        raise HTTPException(status_code=400, detail="Payment already exists for this order")

    # The amount to charge is the *whole* order: subtotal plus delivery fee,
    # service fee, tax and tip, less any promo discount. `order.total_amount` is
    # the basket subtotal only — charging it directly would hand the customer
    # the delivery fee for free.
    breakdown = breakdown_for_order(order)

    try:
        payment = await PaymentService.initiate_payment(
            order_id=req.order_id,
            consumer_id=str(current_user.id),
            amount_usd=minor_to_decimal(breakdown.customer_total_minor),
            method=req.method,
            phone=req.phone,
            currency=req.currency,
            breakdown=breakdown,
        )
    except exchange.StaleExchangeRateError as exc:
        # Better to refuse than to charge at a rate nobody can vouch for.
        raise HTTPException(status_code=503, detail=str(exc))
    except exchange.UnsupportedCurrencyError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return _payment_to_response(payment)


@router.post("/webhook")
async def payment_webhook(request: Request):
    """Paynow result URL. Form-encoded, authenticated by a SHA-512 hash.

    The hash covers the field values in the order they were sent, salted with
    the merchant integration key, so a forged notification cannot be produced
    without the key. Verification is mandatory whenever the service is not in
    mock mode, and production configuration forbids mock mode — so there is no
    deployment in which an unsigned webhook is believed.
    """
    form = await request.form()

    # Order matters to the hash, so read the fields in arrival order.
    if hasattr(form, "multi_items"):
        fields = [(str(k), str(v)) for k, v in form.multi_items()]
    else:
        fields = [(str(k), str(v)) for k, v in form.items()]

    lookup = {k.lower(): v for k, v in fields}
    supplied_hash = lookup.get("hash")

    verification = verify_webhook_fields(fields, supplied_hash)
    if not verification.accepted:
        logger.error(
            "Rejected unauthenticated Paynow webhook",
            reason=verification.reason,
            reference=lookup.get("reference", ""),
        )
        raise HTTPException(
            status_code=http_status.HTTP_401_UNAUTHORIZED,
            detail="Webhook signature verification failed",
        )
    if not verification.verified:
        logger.warning(
            "Accepting unverified webhook (mock mode only)", reason=verification.reason
        )

    payment = await PaymentService.handle_webhook(
        reference=str(lookup.get("reference", "")),
        status=str(lookup.get("status", "")),
        poll_url=str(lookup.get("pollurl", "")),
        payload=dict(fields),
        signature_verified=verification.verified,
        source=NotificationSource.WEBHOOK,
        amount=lookup.get("amount"),
        paynow_reference=lookup.get("paynowreference"),
    )
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")

    return {"status": "ok"}


@router.get("/status/{payment_id}", response_model=PaymentResponse)
async def check_payment_status(payment_id: str, current_user: User = Depends(get_current_user)):
    payment = await PaymentService.check_payment_status(payment_id)
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    # Ownership check: only the paying consumer (or an admin) may poll a payment
    if payment.consumer_id != str(current_user.id) and getattr(current_user, "role", "") != "admin":
        raise HTTPException(status_code=403, detail="Not your payment")
    return _payment_to_response(payment)


@router.get("/order/{order_id}", response_model=PaymentResponse)
async def get_payment_for_order(order_id: str, current_user: User = Depends(get_current_user)):
    payment = await PaymentService.get_payment_for_order(order_id)
    if not payment:
        raise HTTPException(status_code=404, detail="No payment for this order")
    # Ownership check: only the paying consumer (or an admin) may view a payment
    if payment.consumer_id != str(current_user.id) and getattr(current_user, "role", "") != "admin":
        raise HTTPException(status_code=403, detail="Not your payment")
    return _payment_to_response(payment)


@router.get("/order/{order_id}/breakdown")
async def get_order_fee_breakdown(
    order_id: str, current_user: User = Depends(get_current_user)
):
    """Itemised, reconciling fee breakdown for an order.

    Every component the customer is charged and every party's share of it, in
    minor units, summing exactly. Visible to the consumer who placed the order,
    the merchant fulfilling it, and admins.
    """
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    viewer = str(current_user.id)
    role = getattr(current_user, "role", "")
    permitted = viewer in (
        getattr(order, "consumer_id", None),
        getattr(order, "merchant_id", None),
        getattr(order, "driver_id", None),
    )
    if not permitted and role != "admin":
        raise HTTPException(status_code=403, detail="Not authorized to view this breakdown")

    breakdown = breakdown_for_order(order)
    return {"order_id": order_id, **breakdown.as_dict()}


@router.post("/refund/{payment_id}", response_model=PaymentResponse)
async def refund_payment(
    payment_id: str, current_user: User = Depends(get_current_user)
):
    """Request a refund for a paid payment.

    Only an admin or the paying consumer may request one. Paynow Zimbabwe has
    no refund API, so this opens an auditable refund request and moves the
    payment to ``REFUND_PENDING`` — an explicit "money still owed" state. An
    operator settles it in the Paynow portal and closes it out through
    ``POST /payment/refunds/{refund_id}/complete``.
    """
    payment = await Payment.get(payment_id)
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    if current_user.role != "admin" and payment.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to refund this payment")

    refunded = await PaymentService.refund_payment(payment_id)
    if not refunded:
        raise HTTPException(status_code=404, detail="Payment not found")
    return _payment_to_response(refunded)


@router.post("/{payment_id}/refund-request", response_model=RefundResponse)
async def open_refund_request(
    payment_id: str,
    body: RefundRequestCreate,
    current_user: User = Depends(get_current_user),
):
    """Open a refund with a reason and an optional partial amount."""
    payment = await Payment.get(payment_id)
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    if current_user.role != "admin" and payment.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to refund this payment")

    try:
        _payment, refund = await PaymentService.request_refund(
            payment_id,
            requested_by=str(current_user.id),
            reason=body.reason,
            amount_minor=body.amount_minor,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    if not refund:
        raise HTTPException(
            status_code=409, detail="Payment is not in a refundable state"
        )
    return _refund_to_response(refund)


@router.get("/refunds", response_model=List[RefundResponse])
async def list_refunds(
    status_filter: Optional[RefundStatus] = None,
    current_user: User = Depends(get_current_admin),
):
    """Admin view of refunds — the manual-settlement work queue."""
    if status_filter is not None:
        refunds = await RefundRequest.find(RefundRequest.status == status_filter).to_list()
    else:
        refunds = await RefundRequest.find_all().to_list()
    return [_refund_to_response(r) for r in refunds]


@router.post("/refunds/{refund_id}/complete", response_model=RefundResponse)
async def complete_refund(
    refund_id: str,
    body: RefundResolve,
    current_user: User = Depends(get_current_admin),
):
    """Record that the refund was actually paid out in the Paynow portal.

    This is the only path that marks a payment ``REFUNDED``, and it demands the
    provider reference that proves the money moved.
    """
    try:
        _payment, refund = await PaymentService.complete_manual_refund(
            refund_id,
            external_reference=body.external_reference,
            resolved_by=str(current_user.id),
            note=body.note,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    if not refund:
        raise HTTPException(status_code=404, detail="Refund request not found")
    return _refund_to_response(refund)


@router.post("/refunds/{refund_id}/reject", response_model=RefundResponse)
async def reject_refund(
    refund_id: str,
    body: RefundReject,
    current_user: User = Depends(get_current_admin),
):
    """Close a refund request without moving money; the payment returns to PAID."""
    try:
        _payment, refund = await PaymentService.reject_refund(
            refund_id, resolved_by=str(current_user.id), note=body.note
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    if not refund:
        raise HTTPException(status_code=404, detail="Refund request not found")
    return _refund_to_response(refund)
