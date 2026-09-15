"""Paynow Zimbabwe gateway client.

Covers the whole documented Paynow API surface: initiate an express (mobile
money) transaction, poll a transaction's status, and classify every state
Paynow can report. Paynow's own API has no refund operation — see
:meth:`PaynowClient.refund` for what happens instead.

Two things this wrapper adds over the raw ``paynow`` SDK:

* **It never blocks the event loop.** The SDK is built on ``requests``, which
  is synchronous and, as shipped, passes no timeout — one unresponsive Paynow
  node would otherwise stall every request the API server is serving. Calls run
  in a worker thread under an explicit :data:`REQUEST_TIMEOUT_SECONDS`.
* **It never guesses.** Any error, timeout or unavailable client resolves to
  "not paid", never to "paid". The only code path that reports a payment as
  successful without talking to Paynow is the mock path, which cannot exist in
  production (see :func:`PaynowClient.__init__`).
"""

from __future__ import annotations

import asyncio
from enum import Enum
from typing import Optional

import structlog

from app.config import settings
from app.finance.money import DEFAULT_CURRENCY, minor_to_decimal, to_minor

logger = structlog.get_logger()

# Paynow occasionally takes several seconds to answer; beyond this we treat the
# call as unresolved rather than holding a worker.
REQUEST_TIMEOUT_SECONDS = 20.0

MOCK_POLL_PREFIX = "mock://"


class PaynowState(str, Enum):
    """Normalised view of every status string Paynow can report.

    Paynow's documented transaction statuses are Created, Sent, Paid, Awaiting
    Delivery, Delivered, Cancelled, Failed, Disputed and Refunded. Anything
    unrecognised maps to :attr:`UNKNOWN`, which is treated as "keep polling",
    never as success.
    """

    PENDING = "PENDING"      # created / sent — the customer has not acted yet
    PAID = "PAID"            # paid / awaiting delivery / delivered
    CANCELLED = "CANCELLED"
    FAILED = "FAILED"
    DISPUTED = "DISPUTED"
    REFUNDED = "REFUNDED"
    EXPIRED = "EXPIRED"
    ERROR = "ERROR"          # we could not determine the state
    UNKNOWN = "UNKNOWN"


_STATE_BY_STRING = {
    "created": PaynowState.PENDING,
    "sent": PaynowState.PENDING,
    "pending": PaynowState.PENDING,
    "awaiting delivery": PaynowState.PAID,
    "awaiting_delivery": PaynowState.PAID,
    "delivered": PaynowState.PAID,
    "paid": PaynowState.PAID,
    "cancelled": PaynowState.CANCELLED,
    "canceled": PaynowState.CANCELLED,
    "failed": PaynowState.FAILED,
    "error": PaynowState.ERROR,
    "disputed": PaynowState.DISPUTED,
    "refunded": PaynowState.REFUNDED,
    "expired": PaynowState.EXPIRED,
    "timeout": PaynowState.EXPIRED,
}


def classify_status(raw: Optional[str]) -> PaynowState:
    """Map a Paynow status string onto a :class:`PaynowState`."""
    if not raw:
        return PaynowState.UNKNOWN
    return _STATE_BY_STRING.get(str(raw).strip().lower(), PaynowState.UNKNOWN)


class PaynowResponse:
    def __init__(
        self,
        success: bool,
        poll_url: str = "",
        reference: str = "",
        error: str = "",
        instructions: str = "",
    ):
        self.success = success
        self.poll_url = poll_url
        self.reference = reference
        self.error = error
        self.instructions = instructions


class PaynowStatusResponse:
    """Result of a status poll.

    ``paid`` stays for callers that only need the boolean; ``state`` carries
    the full classification so cancellation, dispute and timeout can be handled
    distinctly from an ordinary failure.
    """

    def __init__(
        self,
        paid: bool,
        status: str = "",
        amount: float = 0.0,
        *,
        state: Optional[PaynowState] = None,
        reference: str = "",
        paynow_reference: str = "",
        error: str = "",
        amount_minor: Optional[int] = None,
        currency: str = DEFAULT_CURRENCY,
    ):
        self.paid = paid
        self.status = status
        self.amount = amount
        self.state = state if state is not None else classify_status(status)
        self.reference = reference
        self.paynow_reference = paynow_reference
        self.error = error
        self.currency = currency
        if amount_minor is None:
            try:
                amount_minor = to_minor(amount, currency) if amount else 0
            except Exception:
                amount_minor = 0
        self.amount_minor = amount_minor

    @property
    def is_terminal_failure(self) -> bool:
        return self.state in (
            PaynowState.CANCELLED,
            PaynowState.FAILED,
            PaynowState.DISPUTED,
            PaynowState.EXPIRED,
        )

    @property
    def amount_decimal(self):
        return minor_to_decimal(self.amount_minor, self.currency)


class PaynowRefundUnsupported(RuntimeError):
    """Paynow exposes no programmatic refund; a manual workflow is required."""


class PaynowClient:
    """Wrapper around the Paynow Zimbabwe payment gateway.

    Mock mode is controlled explicitly by ``PAYMENT_MOCK_MODE``. ``Settings``
    refuses to start with mock mode enabled and ``ENVIRONMENT=production``; this
    constructor re-checks, so even a settings object built by hand cannot
    produce a production client that auto-approves payments.
    """

    # Paynow's documented API is: initiate transaction, initiate express
    # (mobile) transaction, poll transaction status, and the merchant's result
    # URL callback. There is no refund endpoint, and no official SDK (PHP,
    # Python, Java, Node, .NET) exposes one.
    supports_programmatic_refund = False

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

    # ── internals ───────────────────────────────────────────────────

    @staticmethod
    async def _call(func, *args):
        """Run a blocking SDK call off the event loop, under a hard timeout."""
        return await asyncio.wait_for(
            asyncio.to_thread(func, *args), timeout=REQUEST_TIMEOUT_SECONDS
        )

    # ── initiate ────────────────────────────────────────────────────

    async def send_mobile(
        self,
        phone: str,
        email: str,
        reference: str,
        amount: float,
        method: str = "ecocash",
    ) -> PaynowResponse:
        """Initiate an express (mobile money) transaction.

        ``amount`` is in major units because that is what Paynow's API takes;
        callers hold minor units and convert once, at this boundary.
        """
        if self.mock_mode:
            logger.info(
                "Mock payment initiated", phone=phone, amount=amount, reference=reference
            )
            return PaynowResponse(
                success=True,
                poll_url=f"{MOCK_POLL_PREFIX}poll/{reference}",
                reference=reference,
            )

        if amount is None or float(amount) <= 0:
            return PaynowResponse(
                success=False, reference=reference, error="Amount must be positive"
            )

        try:
            payment = self._paynow.create_payment(reference, email)
            payment.add("Order Payment", amount)

            response = await self._call(self._paynow.send_mobile, payment, phone, method)

            if response.success:
                logger.info(
                    "Paynow mobile payment sent",
                    reference=reference,
                    poll_url=response.poll_url,
                )
                return PaynowResponse(
                    success=True,
                    poll_url=response.poll_url,
                    reference=reference,
                    instructions=getattr(response, "instruction", "") or "",
                )
            error = getattr(response, "error", None) or getattr(response, "status", "unknown")
            logger.error("Paynow payment failed", reference=reference, error=str(error))
            return PaynowResponse(success=False, reference=reference, error=str(error))
        except asyncio.TimeoutError:
            logger.error("Paynow initiation timed out", reference=reference)
            return PaynowResponse(
                success=False,
                reference=reference,
                error=f"Paynow did not respond within {REQUEST_TIMEOUT_SECONDS:.0f}s",
            )
        except Exception as e:
            logger.error("Paynow exception", reference=reference, error=str(e))
            return PaynowResponse(success=False, reference=reference, error=str(e))

    # ── poll ────────────────────────────────────────────────────────

    async def check_status(self, poll_url: str) -> PaynowStatusResponse:
        """Poll a transaction and classify the result.

        Every failure mode — no client, network error, timeout, unparseable
        response — returns a non-paid response. Nothing here can approve a
        payment by accident.
        """
        if self.mock_mode and poll_url and poll_url.startswith(MOCK_POLL_PREFIX):
            return PaynowStatusResponse(
                paid=True, status="Paid", amount=0, state=PaynowState.PAID
            )

        if not self._paynow:
            # Never auto-approve when the live client is unavailable
            logger.error("Paynow client unavailable; cannot verify payment", poll_url=poll_url)
            return PaynowStatusResponse(
                paid=False,
                status="Error",
                state=PaynowState.ERROR,
                error="Paynow client unavailable",
            )

        try:
            status = await self._call(self._paynow.check_transaction_status, poll_url)
            raw_status = str(getattr(status, "status", "") or "Unknown")
            state = classify_status(raw_status)
            amount = 0.0
            try:
                amount = float(getattr(status, "amount", 0.0) or 0.0)
            except (TypeError, ValueError):
                amount = 0.0
            paid = bool(getattr(status, "paid", False)) or state is PaynowState.PAID
            return PaynowStatusResponse(
                paid=paid,
                status=raw_status,
                amount=amount,
                state=state,
                reference=str(getattr(status, "reference", "") or ""),
                paynow_reference=str(getattr(status, "paynow_reference", "") or ""),
            )
        except asyncio.TimeoutError:
            logger.error("Paynow status check timed out", poll_url=poll_url)
            return PaynowStatusResponse(
                paid=False,
                status="Timeout",
                state=PaynowState.ERROR,
                error=f"Paynow did not respond within {REQUEST_TIMEOUT_SECONDS:.0f}s",
            )
        except Exception as e:
            logger.error("Paynow status check failed", poll_url=poll_url, error=str(e))
            return PaynowStatusResponse(
                paid=False, status="Error", state=PaynowState.ERROR, error=str(e)
            )

    # ── refund ──────────────────────────────────────────────────────

    async def refund(self, reference: str, amount: float) -> PaynowResponse:
        """Attempt a provider-side refund.

        **Paynow Zimbabwe does not expose a refund API.** Its documented
        interface is limited to initiating a transaction, initiating an express
        (mobile) transaction, polling a transaction's status and receiving
        status updates at the merchant's result URL; none of the official SDKs
        (PHP, Python, Java, Node, .NET) implement a refund. Refunds are raised
        from the Paynow merchant portal or with Paynow support, and settle back
        to the payer's wallet out of band.

        So this method deliberately reports failure in live mode rather than
        pretending. :class:`app.payment.service.PaymentService` catches that and
        opens an auditable manual-refund workflow
        (:class:`app.payment.models.RefundRequest`) which holds the payment in
        ``REFUND_PENDING`` until an operator records the provider reference that
        proves the money actually moved.
        """
        if self.mock_mode:
            logger.info("Mock refund issued", reference=reference, amount=amount)
            return PaynowResponse(success=True, reference=reference)

        logger.warning(
            "Paynow has no programmatic refund; escalating to manual workflow",
            reference=reference,
            amount=amount,
        )
        return PaynowResponse(
            success=False,
            reference=reference,
            error=(
                "Paynow Zimbabwe exposes no refund API; refund must be completed "
                "in the Paynow merchant portal and recorded against the refund request"
            ),
        )


paynow_client = PaynowClient()
