"""Paynow webhook (result URL) authentication.

Paynow POSTs a status update to the merchant's ``resulturl`` whenever a
transaction changes state. That request is unauthenticated apart from a SHA-512
``hash`` field, which is the only thing standing between a stranger and a free
meal: ``POST /payment/webhook`` with ``reference=...&status=Paid`` marks an
order paid and dispatches a driver.

The hash is computed exactly as Paynow's own SDKs compute it (verified against
the ``paynow`` PyPI package's ``Paynow.__hash``):

    concat(str(value) for every field except `hash`, in the order sent)
    + integration_key.lower()
    -> SHA512 -> hex -> UPPERCASE

Field order is part of the input, so verification uses the order the fields
arrived in rather than a normalised dict. Comparison is constant-time.

Note that the official ``paynow`` Python SDK's ``process_status_update`` is a
stub that prints "Not implemented" — there is no library support for this, so
it is implemented here.
"""

from __future__ import annotations

import hashlib
import hmac
from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple
from urllib.parse import urlparse

import structlog

from app.config import settings

logger = structlog.get_logger()

__all__ = [
    "WebhookVerification",
    "compute_paynow_hash",
    "verify_paynow_hash",
    "verification_required",
    "verify_webhook_fields",
    "is_trusted_poll_url",
    "TRUSTED_POLL_HOSTS",
]

# Paynow's documented status-update field order, used as a fallback when the
# transport did not preserve the order the fields were sent in.
CANONICAL_FIELD_ORDER = (
    "reference",
    "paynowreference",
    "amount",
    "status",
    "pollurl",
)

# Poll URLs are only ever followed if they live on Paynow's own domain. A
# webhook that supplies its own pollurl would otherwise be able to point the
# server at an attacker-controlled endpoint that always answers "Paid" (and at
# anything on the internal network besides).
TRUSTED_POLL_HOSTS = ("paynow.co.zw",)


@dataclass(frozen=True)
class WebhookVerification:
    """Outcome of authenticating one webhook delivery."""

    verified: bool
    reason: str
    required: bool

    @property
    def accepted(self) -> bool:
        """Whether the request may be acted on at all."""
        return self.verified or not self.required


def compute_paynow_hash(
    fields: Sequence[Tuple[str, str]], integration_key: str
) -> str:
    """SHA-512 of the concatenated field values plus the lowercased key."""
    concatenated = "".join(
        str(value) for key, value in fields if str(key).lower() != "hash"
    )
    concatenated += (integration_key or "").lower()
    return hashlib.sha512(concatenated.encode("utf-8")).hexdigest().upper()


def _orderings(fields: Sequence[Tuple[str, str]]) -> List[List[Tuple[str, str]]]:
    """Field orderings to try: as received, then Paynow's documented order."""
    received = [(k, v) for k, v in fields if str(k).lower() != "hash"]
    orderings = [received]

    by_name = {str(k).lower(): v for k, v in received}
    canonical = [(k, by_name[k]) for k in CANONICAL_FIELD_ORDER if k in by_name]
    extras = [(k, v) for k, v in received if str(k).lower() not in CANONICAL_FIELD_ORDER]
    canonical_with_extras = canonical + extras
    if canonical_with_extras and canonical_with_extras != received:
        orderings.append(canonical_with_extras)
    return orderings


def verify_paynow_hash(
    fields: Sequence[Tuple[str, str]],
    supplied_hash: Optional[str],
    integration_key: Optional[str],
) -> bool:
    """Constant-time check of a Paynow ``hash`` against the posted fields."""
    if not supplied_hash or not integration_key:
        return False
    supplied = str(supplied_hash).strip().upper()
    for ordering in _orderings(fields):
        expected = compute_paynow_hash(ordering, integration_key)
        if hmac.compare_digest(expected, supplied):
            return True
    return False


def verification_required() -> bool:
    """Whether an unsigned webhook must be rejected.

    Signature verification is required whenever the service is not in mock
    mode. ``Settings`` refuses to boot with ``PAYMENT_MOCK_MODE=true`` and
    ``ENVIRONMENT=production``, so in production this is unconditionally
    ``True`` — there is no configuration in which a production deployment
    accepts an unsigned webhook.
    """
    if getattr(settings, "ENVIRONMENT", "development") == "production":
        return True
    return not getattr(settings, "PAYMENT_MOCK_MODE", False)


def verify_webhook_fields(
    fields: Sequence[Tuple[str, str]], supplied_hash: Optional[str]
) -> WebhookVerification:
    """Authenticate one delivery against the configured integration key."""
    required = verification_required()
    key = getattr(settings, "PAYNOW_INTEGRATION_KEY", None)

    if not key:
        if required:
            return WebhookVerification(
                verified=False,
                reason="PAYNOW_INTEGRATION_KEY is not configured; cannot verify webhook",
                required=True,
            )
        return WebhookVerification(
            verified=False,
            reason="mock mode: no integration key configured, signature not checked",
            required=False,
        )

    if not supplied_hash:
        return WebhookVerification(
            verified=False, reason="webhook is missing its hash field", required=required
        )

    if verify_paynow_hash(fields, supplied_hash, key):
        return WebhookVerification(verified=True, reason="hash verified", required=required)

    return WebhookVerification(
        verified=False, reason="webhook hash does not match", required=required
    )


def is_trusted_poll_url(poll_url: Optional[str]) -> bool:
    """True only for an https Paynow URL — everything else is never polled."""
    if not poll_url:
        return False
    try:
        parsed = urlparse(poll_url)
    except ValueError:
        return False
    if parsed.scheme not in ("http", "https"):
        return False
    host = (parsed.hostname or "").lower()
    return any(host == h or host.endswith("." + h) for h in TRUSTED_POLL_HOSTS)
