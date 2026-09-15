"""Payment orchestration: charge, confirm, settle, refund.

Four invariants this module exists to hold:

1. **Amounts are integer minor units end to end.** The only float is the one
   handed to Paynow's API at the very last step, because their API takes one.
2. **State changes are guarded.** Every status write goes through
   :mod:`app.payment.state_machine`, so an illegal or repeated transition is
   refused rather than silently applied.
3. **Provider notifications are idempotent.** Paynow retries its result-URL
   callback until it gets a 2xx. Each notification is logged with a dedupe key
   and, independently, the state machine refuses the repeat — two layers, so a
   retry cannot double-credit or re-dispatch even if the log write fails.
4. **Nothing is marked settled that did not settle.** Refunds in particular are
   never marked complete on Zvingo's side until a human records proof that
   Paynow returned the money.
"""

import asyncio
import hashlib
import json
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, Optional, Tuple

import structlog

from app.config import settings
from app.finance import exchange
from app.finance.fee_calculator import FeeBreakdown
from app.finance.ledger import LedgerService
from app.finance.money import (
    DEFAULT_CURRENCY,
    format_money,
    is_supported_currency,
    minor_to_decimal,
    to_minor,
)
from app.finance.postings import build_charge_posting, build_refund_posting
from app.observability import metrics
from app.payment.models import (
    NotificationSource,
    Payment,
    PaymentMethod,
    PaymentNotification,
    PaymentStatus,
    RefundRequest,
    RefundStatus,
)
from app.payment.paynow_client import PaynowState, classify_status, paynow_client
from app.payment.state_machine import (
    SETTLED_STATES,
    InvalidPaymentTransition,
    TransitionKind,
    classify_transition,
)
from app.payment.webhook_security import is_trusted_poll_url
from app.time_utils import utc_now

logger = structlog.get_logger()

# Method to Paynow provider mapping
METHOD_PROVIDER_MAP = {
    PaymentMethod.ECOCASH: "ecocash",
    PaymentMethod.ONEMONEY: "onemoney",
    PaymentMethod.INNBUCKS: "innbucks",
}

# How long a payment may sit un-settled before reconciliation calls it stuck.
STUCK_PAYMENT_MINUTES = 30

# Paynow status strings that mean a state we handle distinctly.
_TERMINAL_FAILURE_STATES = {
    PaynowState.CANCELLED: PaymentStatus.CANCELLED,
    PaynowState.FAILED: PaymentStatus.FAILED,
    PaynowState.EXPIRED: PaymentStatus.EXPIRED,
}


def build_dedupe_key(
    payment_id: str, reported_status: str, amount_minor: Optional[int], extra: str = ""
) -> str:
    """Stable key for one logical provider notification.

    Deliberately excludes timestamps and the poll URL: Paynow's retries are
    byte-identical in the fields that matter, and keying on those fields is what
    makes the retry collapse onto the original.
    """
    raw = "|".join(
        [
            str(payment_id),
            str(reported_status or "").strip().lower(),
            "" if amount_minor is None else str(int(amount_minor)),
            str(extra or ""),
        ]
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


class PaymentService:
    # ── status transitions ──────────────────────────────────────────

    @staticmethod
    async def _set_status(
        payment: Payment,
        status: PaymentStatus,
        *,
        reason: str = "",
        strict: bool = False,
    ) -> bool:
        """Apply a guarded status change. Returns True only if it actually moved.

        A repeat of the current state returns ``False`` without writing, which
        is how a retried webhook stops short of re-running side effects. An
        illegal transition is logged and refused; with ``strict=True`` it raises
        so an API caller gets a clear error instead of a silent no-op.
        """
        current = payment.status
        kind = classify_transition(current, status)

        if kind is TransitionKind.NOOP:
            logger.info(
                "Payment already in target state; ignoring duplicate",
                payment_id=str(getattr(payment, "id", "")),
                status=status.value,
                reason=reason,
            )
            return False

        if kind is TransitionKind.INVALID:
            logger.error(
                "Refused illegal payment transition",
                payment_id=str(getattr(payment, "id", "")),
                current=current.value,
                target=status.value,
                reason=reason,
            )
            if strict:
                raise InvalidPaymentTransition(current, status)
            return False

        payment.status = status
        payment.updated_at = utc_now()
        await payment.save()
        metrics.payments_total.inc(status=status.value)
        logger.info(
            "Payment status changed",
            payment_id=str(getattr(payment, "id", "")),
            previous=current.value,
            status=status.value,
            reason=reason,
        )
        return True

    # ── exchange rates ──────────────────────────────────────────────

    @staticmethod
    async def get_exchange_rate(
        currency: str, order_id: Optional[str] = None
    ) -> Decimal:
        """Rate used to convert this order's USD price into ``currency``.

        When ``order_id`` is given the rate is **pinned to the order** on first
        use and reused thereafter, so a mid-order rate move cannot change what
        the customer owes. A stale or undated rate raises in production rather
        than being used silently (see :mod:`app.finance.exchange`).

        Returns a :class:`~decimal.Decimal`; never a float.
        """
        quote = await exchange.resolve_rate_for_order(currency, order_id)
        return quote.rate

    @staticmethod
    async def _quote_for(currency: str, order_id: Optional[str]) -> Tuple[Decimal, Optional[Any]]:
        """Rate plus its provenance, tolerating a monkeypatched rate seam."""
        try:
            quote = await exchange.resolve_rate_for_order(currency, order_id)
        except (exchange.StaleExchangeRateError, exchange.UnsupportedCurrencyError):
            raise
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("Rate provenance unavailable", error=str(exc))
            return await PaymentService.get_exchange_rate(currency, order_id), None
        return quote.rate, quote

    # ── initiation ──────────────────────────────────────────────────

    @staticmethod
    async def initiate_payment(
        order_id: str,
        consumer_id: str,
        amount_usd: float,
        method: PaymentMethod,
        phone: str,
        currency: str = DEFAULT_CURRENCY,
        *,
        breakdown: Optional[FeeBreakdown] = None,
    ) -> Payment:
        """Create a payment and push it to Paynow.

        ``breakdown`` is the authoritative amount when supplied — the router
        derives it from the order so the customer is charged subtotal + delivery
        + service + tax + tip - discount, not just the subtotal. ``amount_usd``
        remains the fallback for callers that already know the final figure.
        """
        currency = (currency or DEFAULT_CURRENCY).upper()

        if breakdown is not None:
            amount_usd_cents = breakdown.customer_total_minor
        else:
            amount_usd_cents = to_minor(amount_usd, DEFAULT_CURRENCY)

        rate = await PaymentService.get_exchange_rate(currency, order_id)
        rate = Decimal(str(rate))
        if currency == DEFAULT_CURRENCY:
            amount_local_cents = amount_usd_cents
        else:
            amount_local_cents = exchange.convert_minor(
                amount_usd_cents,
                rate,
                currency if is_supported_currency(currency) else DEFAULT_CURRENCY,
            )

        payment = Payment(
            order_id=order_id,
            consumer_id=consumer_id,
            amount_usd_cents=amount_usd_cents,
            amount_local_cents=amount_local_cents,
            currency=currency,
            fx_rate_micros=exchange.to_micros(rate),
            fx_pinned_at=utc_now(),
            breakdown=breakdown.as_dict() if breakdown is not None else None,
            method=method,
            phone=phone,
            status=PaymentStatus.PENDING,
        )
        await payment.insert()

        # Send to Paynow. Paynow's API takes major units, so convert exactly
        # once, here, at the boundary.
        provider = METHOD_PROVIDER_MAP.get(method, "ecocash")
        charge_currency = currency if is_supported_currency(currency) else DEFAULT_CURRENCY
        charge_amount = float(minor_to_decimal(amount_local_cents, charge_currency))

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
            await PaymentService._set_status(
                payment, PaymentStatus.AWAITING_DELIVERY, reason="provider accepted"
            )

            # Start background auto-complete — ONLY when mock mode is explicitly
            # on. Settings refuses to boot with mock mode in production, and the
            # Paynow client refuses to construct one, so this branch cannot
            # exist in a production process.
            if settings.PAYMENT_MOCK_MODE and response.poll_url.startswith("mock://"):
                asyncio.create_task(PaymentService._mock_auto_complete(str(payment.id)))
        else:
            await PaymentService._set_status(
                payment, PaymentStatus.FAILED, reason=response.error or "provider rejected"
            )
            logger.error("Payment initiation failed", order_id=order_id, error=response.error)

        return payment

    @staticmethod
    async def _mock_auto_complete(payment_id: str):
        """Development only: simulate the customer confirming on their handset.

        Reachable only when ``PAYMENT_MOCK_MODE`` is true, which production
        configuration forbids.
        """
        await asyncio.sleep(3)
        payment = await Payment.get(payment_id)
        if payment and payment.status == PaymentStatus.AWAITING_DELIVERY:
            await PaymentService._settle_paid(
                payment, source=NotificationSource.MOCK, reason="mock auto-complete"
            )
            logger.info("Mock payment auto-completed", payment_id=payment_id)

    # ── settlement ──────────────────────────────────────────────────

    @staticmethod
    async def _settle_paid(
        payment: Payment,
        *,
        source: NotificationSource = NotificationSource.WEBHOOK,
        reason: str = "",
    ) -> bool:
        """Mark a payment paid, post the ledger, and release the order.

        Returns ``False`` when the payment was already settled — the caller can
        then answer the provider 200 OK without doing anything twice.
        """
        moved = await PaymentService._set_status(
            payment, PaymentStatus.PAID, reason=reason or source.value
        )
        if not moved:
            return False

        await PaymentService._record_settlement_ledger(payment)
        await PaymentService._on_payment_success(payment)
        return True

    @staticmethod
    async def _record_settlement_ledger(payment: Payment) -> None:
        """Post the immutable charge entries for a settled payment.

        Wrapped so a ledger outage cannot strand a customer who has already
        paid: the order still dispatches, the failure is logged loudly, and
        ``finance/reconciliation`` reports the payment as missing its ledger
        entries until it is repaired.
        """
        try:
            order = None
            try:
                from app.order.models import Order

                order = await Order.get(payment.order_id)
            except Exception as exc:
                logger.warning(
                    "Order unavailable while posting ledger",
                    order_id=getattr(payment, "order_id", None),
                    error=str(exc),
                )

            breakdown = PaymentService.breakdown_from_payment(payment)
            rate = None
            if getattr(payment, "fx_rate_micros", None):
                rate = Decimal(payment.fx_rate_micros) / exchange.RATE_SCALE

            posting = build_charge_posting(
                payment_id=str(payment.id),
                order_id=payment.order_id,
                consumer_id=payment.consumer_id,
                merchant_id=getattr(order, "merchant_id", "") or "",
                total_minor=payment.charge_amount_minor,
                currency=payment.charge_currency,
                breakdown=breakdown,
                fx_rate=rate,
            )
            await LedgerService.post(posting)
        except Exception as exc:
            logger.error(
                "Ledger posting failed for settled payment",
                payment_id=str(getattr(payment, "id", "")),
                order_id=getattr(payment, "order_id", None),
                error=str(exc),
            )

    @staticmethod
    def breakdown_from_payment(payment: Payment) -> Optional[FeeBreakdown]:
        """Rebuild the frozen :class:`FeeBreakdown` stored on a payment."""
        raw = getattr(payment, "breakdown", None)
        if not raw:
            return None
        try:
            return FeeBreakdown(
                currency=raw.get("currency", DEFAULT_CURRENCY),
                subtotal_minor=int(raw.get("subtotal_minor", 0)),
                delivery_fee_minor=int(raw.get("delivery_fee_minor", 0)),
                service_fee_minor=int(raw.get("service_fee_minor", 0)),
                tax_minor=int(raw.get("tax_minor", 0)),
                tip_minor=int(raw.get("tip_minor", 0)),
                discount_minor=int(raw.get("discount_minor", 0)),
                driver_share_minor=int(raw.get("driver_share_minor", 0)),
                platform_commission_minor=int(raw.get("platform_commission_minor", 0)),
                promo_funded_by=raw.get("promo_funded_by", "platform"),
            )
        except Exception as exc:
            logger.error(
                "Stored fee breakdown is unusable",
                payment_id=str(getattr(payment, "id", "")),
                error=str(exc),
            )
            return None

    @staticmethod
    async def check_payment_status(payment_id: str) -> Optional[Payment]:
        """Poll Paynow for a payment and apply whatever it reports.

        The poll URL used is the one Paynow gave us at initiation and that we
        stored — never one supplied by an inbound request — and it must be on a
        Paynow host. That closes the door on a forged webhook pointing the
        server at an endpoint that always answers "Paid".
        """
        payment = await Payment.get(payment_id)
        if not payment or not payment.poll_url:
            return payment

        if payment.status in (
            PaymentStatus.PAID,
            PaymentStatus.FAILED,
            PaymentStatus.REFUNDED,
            PaymentStatus.REFUND_PENDING,
            PaymentStatus.CANCELLED,
            PaymentStatus.EXPIRED,
        ):
            return payment

        poll_url = payment.poll_url
        mock_poll = bool(poll_url) and poll_url.startswith("mock://")
        if not mock_poll and not is_trusted_poll_url(poll_url):
            logger.error(
                "Refusing to poll an untrusted poll URL",
                payment_id=payment_id,
                poll_url=poll_url,
            )
            return payment

        status = await paynow_client.check_status(poll_url)
        await PaymentService._apply_provider_state(
            payment,
            state=getattr(status, "state", None) or classify_status(getattr(status, "status", "")),
            raw_status=str(getattr(status, "status", "")),
            amount_minor=getattr(status, "amount_minor", None),
            source=NotificationSource.POLL,
        )
        return payment

    @staticmethod
    async def _apply_provider_state(
        payment: Payment,
        *,
        state: PaynowState,
        raw_status: str,
        amount_minor: Optional[int] = None,
        source: NotificationSource = NotificationSource.WEBHOOK,
    ) -> str:
        """Translate a provider state into a guarded payment transition.

        Returns a short description of what was done, for the notification log.
        """
        if state is PaynowState.PAID:
            anomaly = PaymentService._amount_anomaly(payment, amount_minor)
            if anomaly:
                logger.error(
                    "Provider reported a different amount than we charged",
                    payment_id=str(getattr(payment, "id", "")),
                    detail=anomaly,
                )
                return f"rejected:{anomaly}"
            settled = await PaymentService._settle_paid(
                payment, source=source, reason=raw_status or "paid"
            )
            return "settled" if settled else "duplicate"

        target = _TERMINAL_FAILURE_STATES.get(state)
        if target is not None:
            if payment.status in SETTLED_STATES:
                logger.error(
                    "Provider reported failure for an already-settled payment",
                    payment_id=str(getattr(payment, "id", "")),
                    status=payment.status.value,
                    reported=raw_status,
                )
                return "anomaly:failure-after-settlement"
            moved = await PaymentService._set_status(
                payment, target, reason=raw_status or state.value
            )
            return "failed" if moved else "duplicate"

        if state is PaynowState.DISPUTED:
            # A dispute is not a state change we can safely apply on our own —
            # the money may or may not come back. Flag it for an operator.
            logger.error(
                "Paynow reported a disputed transaction",
                payment_id=str(getattr(payment, "id", "")),
                status=payment.status.value,
            )
            return "anomaly:disputed"

        if state is PaynowState.REFUNDED:
            logger.warning(
                "Provider reported a refund we did not initiate",
                payment_id=str(getattr(payment, "id", "")),
            )
            return "anomaly:provider-refund"

        return "no-op"

    @staticmethod
    def _amount_anomaly(payment: Payment, amount_minor: Optional[int]) -> Optional[str]:
        """Reject a 'paid' notification whose amount is not what we charged."""
        if not amount_minor:
            return None
        expected = getattr(payment, "charge_amount_minor", None)
        if not expected:
            return None
        if int(amount_minor) != int(expected):
            return (
                f"amount mismatch: provider reported "
                f"{format_money(int(amount_minor), payment.charge_currency)}, "
                f"expected {format_money(int(expected), payment.charge_currency)}"
            )
        return None

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

    # ── webhooks ────────────────────────────────────────────────────

    @staticmethod
    async def handle_webhook(
        reference: str,
        status: str,
        poll_url: str,
        *,
        payload: Optional[Dict[str, Any]] = None,
        signature_verified: bool = False,
        source: NotificationSource = NotificationSource.WEBHOOK,
        amount: Optional[str] = None,
        paynow_reference: Optional[str] = None,
    ) -> Optional[Payment]:
        """Handle a Paynow status update.

        Authentication happens in the router before this is called; this method
        owns *idempotency* and *state safety*. The ``poll_url`` the caller sends
        is recorded for audit but deliberately never used: only the poll URL
        Paynow gave us at initiation is ever polled.
        """
        payment = await Payment.find_one(Payment.paynow_reference == reference)
        if not payment:
            logger.warn("Webhook for unknown payment", reference=reference)
            await PaymentService._log_notification(
                payment=None,
                reference=reference,
                reported_status=status,
                payload=payload,
                signature_verified=signature_verified,
                source=source,
                accepted=False,
                action="unknown-payment",
                paynow_reference=paynow_reference,
            )
            return None

        amount_minor = None
        if amount:
            try:
                amount_minor = to_minor(amount, payment.charge_currency)
            except Exception:
                amount_minor = None

        dedupe_key = build_dedupe_key(
            str(payment.id), status, amount_minor, extra=str(paynow_reference or "")
        )
        if await PaymentService._notification_seen(dedupe_key):
            logger.info(
                "Duplicate payment notification ignored",
                payment_id=str(payment.id),
                reference=reference,
                status=status,
            )
            return payment

        state = classify_status(status)
        action = await PaymentService._apply_provider_state(
            payment,
            state=state,
            raw_status=status,
            amount_minor=amount_minor,
            source=source,
        )

        await PaymentService._log_notification(
            payment=payment,
            reference=reference,
            reported_status=status,
            payload=payload,
            signature_verified=signature_verified,
            source=source,
            accepted=True,
            action=action,
            amount_minor=amount_minor,
            dedupe_key=dedupe_key,
            paynow_reference=paynow_reference,
        )
        return payment

    @staticmethod
    async def _notification_seen(dedupe_key: str) -> bool:
        """True when this exact notification has already been processed.

        A failure here is not fatal: the state machine independently refuses to
        re-apply a transition, so the worst case of a log outage is an extra
        audit gap, not a double credit.
        """
        try:
            existing = await PaymentNotification.find_one(
                PaymentNotification.dedupe_key == dedupe_key
            )
            return existing is not None
        except Exception as exc:
            logger.warning("Notification dedupe log unavailable", error=str(exc))
            return False

    @staticmethod
    async def _log_notification(
        *,
        payment: Optional[Payment],
        reference: str,
        reported_status: str,
        payload: Optional[Dict[str, Any]],
        signature_verified: bool,
        source: NotificationSource,
        accepted: bool,
        action: str,
        amount_minor: Optional[int] = None,
        dedupe_key: Optional[str] = None,
        paynow_reference: Optional[str] = None,
    ) -> None:
        key = dedupe_key or build_dedupe_key(
            str(getattr(payment, "id", reference)), reported_status, amount_minor
        )
        try:
            record = PaymentNotification(
                dedupe_key=key,
                payment_id=str(payment.id) if payment is not None else None,
                order_id=getattr(payment, "order_id", None),
                reference=reference,
                paynow_reference=paynow_reference,
                source=source,
                reported_status=reported_status,
                reported_amount_minor=amount_minor,
                currency=getattr(payment, "charge_currency", DEFAULT_CURRENCY),
                signature_verified=signature_verified,
                accepted=accepted,
                action=action,
                anomaly=action if action.startswith("anomaly") or action.startswith("rejected") else None,
                payload=_safe_payload(payload),
            )
            await record.insert()
        except Exception as exc:
            logger.warning(
                "Could not write payment notification log",
                reference=reference,
                error=str(exc),
            )

    @staticmethod
    async def get_payment_for_order(order_id: str) -> Optional[Payment]:
        return await Payment.find_one(Payment.order_id == order_id)

    # ── refunds ─────────────────────────────────────────────────────

    @staticmethod
    async def request_refund(
        payment_id: str,
        *,
        requested_by: str,
        reason: str = "",
        amount_minor: Optional[int] = None,
    ) -> Tuple[Optional[Payment], Optional[RefundRequest]]:
        """Open a refund against a paid payment.

        Paynow Zimbabwe has no refund API (see
        :meth:`app.payment.paynow_client.PaynowClient.refund`). So this:

        * creates an auditable :class:`RefundRequest` recording who asked, for
          how much, and why;
        * attempts the provider refund — which succeeds only in mock mode;
        * on failure, parks the request in ``PENDING_MANUAL`` and the payment in
          ``REFUND_PENDING``, which is an explicit "we owe this customer money
          and it has not moved yet" state, visible to reconciliation and to the
          admin console.

        The payment is **never** marked ``REFUNDED`` until money has actually
        moved and someone has recorded the provider reference proving it.
        """
        payment = await Payment.get(payment_id)
        if not payment:
            return None, None
        if payment.status != PaymentStatus.PAID:
            # Already refunding, already refunded, or never paid.
            return payment, await PaymentService.get_refund_request(payment_id)

        amount = int(amount_minor) if amount_minor else payment.charge_amount_minor
        if amount <= 0 or amount > payment.charge_amount_minor:
            raise ValueError(
                f"Refund amount must be between 1 and {payment.charge_amount_minor} minor units"
            )

        refund = RefundRequest(
            payment_id=str(payment.id),
            order_id=payment.order_id,
            consumer_id=payment.consumer_id,
            amount_minor=amount,
            currency=payment.charge_currency,
            reason=reason,
            requested_by=requested_by,
            provider_reference=payment.paynow_reference,
            status=RefundStatus.REQUESTED,
        )
        await refund.insert()

        response = await paynow_client.refund(
            payment.paynow_reference or payment_id,
            float(minor_to_decimal(amount, payment.charge_currency)),
        )

        if response.success:
            await PaymentService._complete_refund(
                payment,
                refund,
                external_reference=response.reference,
                resolved_by=requested_by,
                note="settled by provider",
            )
            return payment, refund

        # No programmatic refund: hold an explicit, visible liability.
        refund.status = RefundStatus.PENDING_MANUAL
        refund.resolution_note = response.error or "provider refund unavailable"
        refund.updated_at = utc_now()
        await refund.save()

        await PaymentService._set_status(
            payment, PaymentStatus.REFUND_PENDING, reason="manual refund pending"
        )
        payment.refund_request_id = str(refund.id)
        await payment.save()

        logger.error(
            "Refund requires manual settlement in the Paynow portal",
            payment_id=payment_id,
            refund_id=str(refund.id),
            amount=format_money(refund.amount_minor, refund.currency),
            reason=refund.resolution_note,
        )
        return payment, refund

    @staticmethod
    async def complete_manual_refund(
        refund_id: str,
        *,
        external_reference: str,
        resolved_by: str,
        note: str = "",
    ) -> Tuple[Optional[Payment], Optional[RefundRequest]]:
        """Record that a human actually returned the money in the Paynow portal.

        ``external_reference`` is mandatory: it is the evidence that ties this
        ledger entry to a real movement at the provider.
        """
        if not external_reference or not external_reference.strip():
            raise ValueError("external_reference is required to complete a refund")

        refund = await RefundRequest.get(refund_id)
        if not refund:
            return None, None
        if refund.status == RefundStatus.COMPLETED:
            return await Payment.get(refund.payment_id), refund
        if refund.status not in (RefundStatus.PENDING_MANUAL, RefundStatus.REQUESTED):
            raise ValueError(f"Refund {refund_id} is {refund.status.value}; cannot complete")

        payment = await Payment.get(refund.payment_id)
        if not payment:
            return None, refund

        await PaymentService._complete_refund(
            payment,
            refund,
            external_reference=external_reference.strip(),
            resolved_by=resolved_by,
            note=note,
        )
        return payment, refund

    @staticmethod
    async def reject_refund(
        refund_id: str, *, resolved_by: str, note: str = ""
    ) -> Tuple[Optional[Payment], Optional[RefundRequest]]:
        """Close a refund request without moving money; the payment stays PAID."""
        refund = await RefundRequest.get(refund_id)
        if not refund:
            return None, None
        if refund.status == RefundStatus.COMPLETED:
            raise ValueError("A completed refund cannot be rejected")

        refund.status = RefundStatus.REJECTED
        refund.resolved_by = resolved_by
        refund.resolved_at = utc_now()
        refund.resolution_note = note
        refund.updated_at = utc_now()
        await refund.save()

        payment = await Payment.get(refund.payment_id)
        if payment and payment.status == PaymentStatus.REFUND_PENDING:
            await PaymentService._set_status(
                payment, PaymentStatus.PAID, reason="refund rejected"
            )
        return payment, refund

    @staticmethod
    async def _complete_refund(
        payment: Payment,
        refund: RefundRequest,
        *,
        external_reference: str,
        resolved_by: str,
        note: str = "",
    ) -> None:
        """Post the refund to the ledger and move both records to settled."""
        try:
            posting = build_refund_posting(
                refund_id=str(refund.id),
                payment_id=str(payment.id),
                order_id=payment.order_id,
                consumer_id=payment.consumer_id,
                amount_minor=refund.amount_minor,
                currency=refund.currency,
            )
            await LedgerService.post(posting)
            refund.ledger_posted = True
        except Exception as exc:
            logger.error(
                "Refund ledger posting failed",
                refund_id=str(refund.id),
                error=str(exc),
            )

        refund.status = RefundStatus.COMPLETED
        refund.external_reference = external_reference
        refund.resolved_by = resolved_by
        refund.resolved_at = utc_now()
        refund.resolution_note = note or refund.resolution_note
        refund.updated_at = utc_now()
        await refund.save()

        await PaymentService._set_status(
            payment, PaymentStatus.REFUNDED, reason="refund settled"
        )
        payment.refund_request_id = str(refund.id)
        await payment.save()
        logger.info(
            "Payment refunded",
            payment_id=str(payment.id),
            order_id=payment.order_id,
            refund_id=str(refund.id),
            external_reference=external_reference,
        )

    @staticmethod
    async def get_refund_request(payment_id: str) -> Optional[RefundRequest]:
        try:
            return await RefundRequest.find_one(RefundRequest.payment_id == payment_id)
        except Exception:
            return None

    @staticmethod
    async def refund_payment(payment_id: str) -> Optional[Payment]:
        """Backwards-compatible refund entry point.

        Kept so existing callers keep working. It now opens the auditable
        workflow above instead of flipping a status field, so a refund can no
        longer *look* done while the customer has had nothing back.
        """
        payment, _refund = await PaymentService.request_refund(
            payment_id, requested_by="system", reason="legacy refund call"
        )
        return payment

    # ── reconciliation support ──────────────────────────────────────

    @staticmethod
    async def find_stuck_payments(minutes: int = STUCK_PAYMENT_MINUTES):
        """Payments still un-settled well past the point they should have been."""
        cutoff = utc_now() - timedelta(minutes=minutes)
        return await Payment.find(
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

    @staticmethod
    async def find_pending_refunds():
        return await RefundRequest.find(
            RefundRequest.status == RefundStatus.PENDING_MANUAL
        ).to_list()


def _safe_payload(payload: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Store the raw notification, minus its signature, as JSON-safe values."""
    if not payload:
        return {}
    cleaned = {}
    for key, value in payload.items():
        if str(key).lower() == "hash":
            cleaned[key] = "<redacted>"
            continue
        try:
            json.dumps(value)
            cleaned[key] = value
        except (TypeError, ValueError):
            cleaned[key] = str(value)
    return cleaned
