import asyncio
from datetime import datetime
from app.time_utils import utc_now
from typing import Optional
import structlog
import redis.asyncio as aioredis

from app.config import settings
from app.payment.models import Payment, PaymentMethod, PaymentStatus
from app.payment.paynow_client import paynow_client
from app.observability import metrics

logger = structlog.get_logger()

# Method to Paynow provider mapping
METHOD_PROVIDER_MAP = {
    PaymentMethod.ECOCASH: "ecocash",
    PaymentMethod.ONEMONEY: "onemoney",
    PaymentMethod.INNBUCKS: "innbucks",
}


class PaymentService:
    @staticmethod
    async def _set_status(payment: Payment, status: PaymentStatus) -> Payment:
        """Persist a payment status change and record it for metrics."""
        payment.status = status
        payment.updated_at = utc_now()
        await payment.save()
        metrics.payments_total.inc(status=status.value)
        return payment

    @staticmethod
    async def get_exchange_rate(currency: str) -> float:
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        try:
            rate = await r.get(f"exchange_rate:{currency.upper()}")
            if rate:
                return float(rate)
            # Defaults
            defaults = {"ZIG": 13.50, "ZAR": 18.50, "USD": 1.0}
            return defaults.get(currency.upper(), 1.0)
        finally:
            await r.close()

    @staticmethod
    async def initiate_payment(
        order_id: str,
        consumer_id: str,
        amount_usd: float,
        method: PaymentMethod,
        phone: str,
        currency: str = "USD",
    ) -> Payment:
        # Convert amount if non-USD
        rate = await PaymentService.get_exchange_rate(currency)
        amount_local = round(amount_usd * rate, 2) if currency != "USD" else amount_usd

        payment = Payment(
            order_id=order_id,
            consumer_id=consumer_id,
            amount_usd=amount_usd,
            amount_local=amount_local,
            currency=currency,
            method=method,
            phone=phone,
            status=PaymentStatus.PENDING,
        )
        await payment.insert()

        # Send to Paynow
        provider = METHOD_PROVIDER_MAP.get(method, "ecocash")
        charge_amount = amount_local if currency != "USD" else amount_usd

        response = await paynow_client.send_mobile(
            phone=phone,
            email=f"order-{order_id}@zvingo.co.zw",
            reference=f"ZVINGO-{str(payment.id)[-8:]}",
            amount=charge_amount,
            method=provider,
        )

        if response.success:
            payment.poll_url = response.poll_url
            payment.paynow_reference = response.reference
            await PaymentService._set_status(payment, PaymentStatus.AWAITING_DELIVERY)

            # Start background auto-complete — ONLY when mock mode is explicitly on
            if settings.PAYMENT_MOCK_MODE and response.poll_url.startswith("mock://"):
                asyncio.create_task(PaymentService._mock_auto_complete(str(payment.id)))
        else:
            await PaymentService._set_status(payment, PaymentStatus.FAILED)
            logger.error("Payment initiation failed", order_id=order_id, error=response.error)

        return payment

    @staticmethod
    async def _mock_auto_complete(payment_id: str):
        """In mock mode, auto-complete payment after 3 seconds to simulate EcoCash confirmation."""
        await asyncio.sleep(3)
        payment = await Payment.get(payment_id)
        if payment and payment.status == PaymentStatus.AWAITING_DELIVERY:
            await PaymentService._set_status(payment, PaymentStatus.PAID)
            logger.info("Mock payment auto-completed", payment_id=payment_id)

            # Trigger order dispatch
            await PaymentService._on_payment_success(payment)

    @staticmethod
    async def check_payment_status(payment_id: str) -> Optional[Payment]:
        payment = await Payment.get(payment_id)
        if not payment or not payment.poll_url:
            return payment

        if payment.status in (PaymentStatus.PAID, PaymentStatus.FAILED, PaymentStatus.REFUNDED):
            return payment

        # Poll Paynow
        status = await paynow_client.check_status(payment.poll_url)
        if status.paid:
            await PaymentService._set_status(payment, PaymentStatus.PAID)
            await PaymentService._on_payment_success(payment)
        elif status.status.lower() in ("cancelled", "failed", "disputed"):
            await PaymentService._set_status(payment, PaymentStatus.FAILED)

        return payment

    @staticmethod
    async def _on_payment_success(payment: Payment):
        """After payment confirmed, transition order to OFFERED and dispatch drivers."""
        from app.order.service import OrderService
        from app.order.state_machine import OrderState

        order = await OrderService.transition_state(
            payment.order_id, OrderState.OFFERED, actor_id="system"
        )
        if order:
            logger.info("Order dispatched after payment", order_id=payment.order_id)

    @staticmethod
    async def handle_webhook(reference: str, status: str, poll_url: str) -> Optional[Payment]:
        """Handle Paynow webhook callback."""
        payment = await Payment.find_one(Payment.paynow_reference == reference)
        if not payment:
            logger.warn("Webhook for unknown payment", reference=reference)
            return None

        status_lower = status.lower()
        if status_lower in ("paid", "delivered"):
            await PaymentService._set_status(payment, PaymentStatus.PAID)
            await PaymentService._on_payment_success(payment)
        elif status_lower in ("cancelled", "failed", "disputed"):
            await PaymentService._set_status(payment, PaymentStatus.FAILED)

        return payment

    @staticmethod
    async def get_payment_for_order(order_id: str) -> Optional[Payment]:
        return await Payment.find_one(Payment.order_id == order_id)

    @staticmethod
    async def refund_payment(payment_id: str) -> Optional[Payment]:
        payment = await Payment.get(payment_id)
        if not payment:
            return None
        if payment.status != PaymentStatus.PAID:
            return payment

        # Ask the provider to actually move the money back before marking refunded.
        response = await paynow_client.refund(
            payment.paynow_reference or payment_id, payment.amount_usd
        )
        if not response.success:
            logger.error(
                "Refund failed at provider",
                payment_id=payment_id,
                error=response.error,
            )
            return payment  # leave status unchanged; caller sees it is still PAID

        await PaymentService._set_status(payment, PaymentStatus.REFUNDED)
        logger.info("Payment refunded", payment_id=payment_id, order_id=payment.order_id)
        return payment
