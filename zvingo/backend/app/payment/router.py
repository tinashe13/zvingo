from fastapi import APIRouter, HTTPException, Depends, Request
from app.payment.schemas import PaymentInitiate, PaymentResponse, PaymentWebhook
from app.payment.service import PaymentService
from app.payment.models import Payment
from app.order.models import Order
from app.auth.router import get_current_user
from app.auth.models import User

router = APIRouter()


def _payment_to_response(p: Payment) -> PaymentResponse:
    return PaymentResponse(
        id=str(p.id),
        order_id=p.order_id,
        amount_usd=p.amount_usd,
        amount_local=p.amount_local,
        currency=p.currency,
        method=p.method,
        status=p.status,
        paynow_reference=p.paynow_reference,
        created_at=p.created_at,
    )


@router.post("/initiate", response_model=PaymentResponse)
async def initiate_payment(req: PaymentInitiate, current_user: User = Depends(get_current_user)):
    order = await Order.get(req.order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if order.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not your order")

    existing = await PaymentService.get_payment_for_order(req.order_id)
    if existing and existing.status.value in ("PAID", "AWAITING_DELIVERY"):
        raise HTTPException(status_code=400, detail="Payment already exists for this order")

    payment = await PaymentService.initiate_payment(
        order_id=req.order_id,
        consumer_id=str(current_user.id),
        amount_usd=order.total_amount,
        method=req.method,
        phone=req.phone,
        currency=req.currency,
    )
    return _payment_to_response(payment)


@router.post("/webhook")
async def payment_webhook(request: Request):
    """Paynow sends form-encoded data to this endpoint."""
    form = await request.form()
    reference = form.get("reference", "")
    status = form.get("status", "")
    poll_url = form.get("pollurl", "")

    payment = await PaymentService.handle_webhook(
        reference=str(reference),
        status=str(status),
        poll_url=str(poll_url),
    )
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")

    return {"status": "ok"}


@router.get("/status/{payment_id}", response_model=PaymentResponse)
async def check_payment_status(payment_id: str, current_user: User = Depends(get_current_user)):
    payment = await PaymentService.check_payment_status(payment_id)
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    # Ownership check: only the paying consumer may poll their payment
    if payment.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not your payment")
    return _payment_to_response(payment)


@router.get("/order/{order_id}", response_model=PaymentResponse)
async def get_payment_for_order(order_id: str, current_user: User = Depends(get_current_user)):
    payment = await PaymentService.get_payment_for_order(order_id)
    if not payment:
        raise HTTPException(status_code=404, detail="No payment for this order")
    # Ownership check: only the paying consumer may view the payment
    if payment.consumer_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not your payment")
    return _payment_to_response(payment)


@router.post("/refund/{payment_id}", response_model=PaymentResponse)
async def refund_payment(
    payment_id: str, current_user: User = Depends(get_current_user)
):
    """Refund a paid payment.

    Only an admin or the paying consumer may refund. The actual money movement
    is delegated to the payment provider (see PaymentService.refund_payment).
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
