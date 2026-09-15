"""Payment state machine.

Payments are guarded the same way orders are: a transition either appears in
:data:`ALLOWED_TRANSITIONS` or it does not happen. Two properties fall out of
this that matter for money:

* **Idempotency.** ``PAID -> PAID`` is not an allowed transition, so a retried
  Paynow webhook cannot re-run the post-payment side effects (dispatching the
  order, posting ledger entries). :func:`classify_transition` reports a repeat
  as ``NOOP`` rather than as an error, because a retry is normal traffic.
* **No resurrection.** ``FAILED -> PAID`` is refused. A late success on a
  transaction we already wrote off is an anomaly a human must look at, not
  something to apply silently; :mod:`app.payment.service` records it for
  reconciliation instead.
"""

from __future__ import annotations

from enum import Enum
from typing import Dict, Set

from app.payment.models import PaymentStatus

__all__ = [
    "TransitionKind",
    "ALLOWED_TRANSITIONS",
    "TERMINAL_STATES",
    "SETTLED_STATES",
    "InvalidPaymentTransition",
    "classify_transition",
    "validate_transition",
    "is_terminal",
]


class TransitionKind(str, Enum):
    APPLY = "APPLY"      # a real, allowed change
    NOOP = "NOOP"        # already in this state — a duplicate notification
    INVALID = "INVALID"  # refused


ALLOWED_TRANSITIONS: Dict[PaymentStatus, Set[PaymentStatus]] = {
    PaymentStatus.PENDING: {
        PaymentStatus.AWAITING_DELIVERY,
        PaymentStatus.PAID,
        PaymentStatus.FAILED,
        PaymentStatus.CANCELLED,
        PaymentStatus.EXPIRED,
    },
    PaymentStatus.AWAITING_DELIVERY: {
        PaymentStatus.PAID,
        PaymentStatus.FAILED,
        PaymentStatus.CANCELLED,
        PaymentStatus.EXPIRED,
    },
    PaymentStatus.PAID: {
        PaymentStatus.REFUND_PENDING,
        PaymentStatus.REFUNDED,
    },
    # A refund can be completed, or rejected — in which case the payment goes
    # back to PAID because the customer's money never moved.
    PaymentStatus.REFUND_PENDING: {
        PaymentStatus.REFUNDED,
        PaymentStatus.PAID,
        PaymentStatus.FAILED,
    },
    PaymentStatus.REFUNDED: set(),
    PaymentStatus.FAILED: set(),
    PaymentStatus.CANCELLED: set(),
    PaymentStatus.EXPIRED: set(),
}

TERMINAL_STATES = {
    PaymentStatus.REFUNDED,
    PaymentStatus.FAILED,
    PaymentStatus.CANCELLED,
    PaymentStatus.EXPIRED,
}

# States in which the customer's money has actually been taken.
SETTLED_STATES = {
    PaymentStatus.PAID,
    PaymentStatus.REFUND_PENDING,
    PaymentStatus.REFUNDED,
}


class InvalidPaymentTransition(ValueError):
    def __init__(self, current: PaymentStatus, target: PaymentStatus):
        self.current = current
        self.target = target
        super().__init__(
            f"Illegal payment transition {current.value} -> {target.value}"
        )


def classify_transition(
    current: PaymentStatus, target: PaymentStatus
) -> TransitionKind:
    if current == target:
        return TransitionKind.NOOP
    if target in ALLOWED_TRANSITIONS.get(current, set()):
        return TransitionKind.APPLY
    return TransitionKind.INVALID


def validate_transition(current: PaymentStatus, target: PaymentStatus) -> TransitionKind:
    kind = classify_transition(current, target)
    if kind is TransitionKind.INVALID:
        raise InvalidPaymentTransition(current, target)
    return kind


def is_terminal(status: PaymentStatus) -> bool:
    return status in TERMINAL_STATES
