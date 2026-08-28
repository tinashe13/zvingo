import structlog
from typing import Optional
from app.config import settings

logger = structlog.get_logger()


class PaynowResponse:
    def __init__(self, success: bool, poll_url: str = "", reference: str = "", error: str = ""):
        self.success = success
        self.poll_url = poll_url
        self.reference = reference
        self.error = error


class PaynowStatusResponse:
    def __init__(self, paid: bool, status: str = "", amount: float = 0.0):
        self.paid = paid
        self.status = status
        self.amount = amount


class PaynowClient:
    """Wrapper around Paynow Zimbabwe payment gateway.

    Mock mode is controlled explicitly by the PAYMENT_MOCK_MODE setting
    (payments are auto-approved for development). Settings validation
    already refuses to start with mock mode enabled in production; this
    class re-checks as a defense-in-depth guard.
    """

    def __init__(self):
        self.integration_id = settings.PAYNOW_INTEGRATION_ID
        self.integration_key = settings.PAYNOW_INTEGRATION_KEY
        self.return_url = settings.PAYNOW_RETURN_URL
        self.result_url = settings.PAYNOW_RESULT_URL
        self.mock_mode = settings.PAYMENT_MOCK_MODE
        self._paynow = None

        if self.mock_mode:
            if settings.ENVIRONMENT == "production":
                # Defense in depth: Settings already blocks this combination.
                raise RuntimeError(
                    "PAYMENT_MOCK_MODE must not be enabled in production"
                )
            logger.warning(
                "Paynow client initialized in MOCK mode - all payments auto-approve. "
                "Set PAYMENT_MOCK_MODE=false with real Paynow credentials for live payments."
            )
            return

        if not (self.integration_id and self.integration_key):
            raise RuntimeError(
                "PAYMENT_MOCK_MODE is false but PAYNOW_INTEGRATION_ID/"
                "PAYNOW_INTEGRATION_KEY are not configured"
            )
        try:
            from paynow import Paynow
        except ImportError as exc:
            raise RuntimeError(
                "PAYMENT_MOCK_MODE is false but the `paynow` package is not installed"
            ) from exc
        self._paynow = Paynow(
            self.integration_id,
            self.integration_key,
            self.return_url,
            self.result_url,
        )
        logger.info("Paynow client initialized (LIVE mode)")

    async def send_mobile(self, phone: str, email: str, reference: str, amount: float, method: str = "ecocash") -> PaynowResponse:
        if self.mock_mode:
            logger.info("Mock payment initiated", phone=phone, amount=amount, reference=reference)
            return PaynowResponse(
                success=True,
                poll_url=f"mock://poll/{reference}",
                reference=reference,
            )

        try:
            payment = self._paynow.create_payment(reference, email)
            payment.add("Order Payment", amount)

            response = self._paynow.send_mobile(payment, phone, method)

            if response.success:
                logger.info("Paynow mobile payment sent", reference=reference, poll_url=response.poll_url)
                return PaynowResponse(
                    success=True,
                    poll_url=response.poll_url,
                    reference=reference,
                )
            else:
                logger.error("Paynow payment failed", error=response.error)
                return PaynowResponse(success=False, error=str(response.error))
        except Exception as e:
            logger.error("Paynow exception", error=str(e))
            return PaynowResponse(success=False, error=str(e))

    async def check_status(self, poll_url: str) -> PaynowStatusResponse:
        if self.mock_mode and poll_url.startswith("mock://"):
            return PaynowStatusResponse(paid=True, status="Paid", amount=0)

        if not self._paynow:
            # Never auto-approve when the live client is unavailable
            logger.error("Paynow client unavailable; cannot verify payment", poll_url=poll_url)
            return PaynowStatusResponse(paid=False, status="Error")

        try:
            status = self._paynow.check_transaction_status(poll_url)
            return PaynowStatusResponse(
                paid=status.paid,
                status=str(status.status) if hasattr(status, 'status') else "Unknown",
                amount=float(status.amount) if hasattr(status, 'amount') else 0.0,
            )
        except Exception as e:
            logger.error("Paynow status check failed", error=str(e))
            return PaynowStatusResponse(paid=False, status="Error")

    async def refund(self, reference: str, amount: float) -> PaynowResponse:
        """Refund a previously collected payment via Paynow.

        In mock mode the refund is simulated as successful. In live mode the
        ``paynow`` SDK does not expose a first-class refund helper, so we
        surface an explicit failure rather than silently pretending to refund
        real money. Wiring a live refund requires Paynow's refund endpoint
        (see docs/TODO.md).
        """
        if self.mock_mode:
            logger.info("Mock refund issued", reference=reference, amount=amount)
            return PaynowResponse(success=True, reference=reference)

        if not self._paynow:
            return PaynowResponse(
                success=False,
                reference=reference,
                error="Paynow client unavailable for refund",
            )

        # The `paynow` package currently has no public refund method; this
        # returns an explicit error so the DB state is never falsely marked
        # REFUNDED when real money has not moved.
        logger.error(
            "Live Paynow refund not implemented", reference=reference, amount=amount
        )
        return PaynowResponse(
            success=False,
            reference=reference,
            error="Live refund requires Paynow refund endpoint integration",
        )


paynow_client = PaynowClient()
