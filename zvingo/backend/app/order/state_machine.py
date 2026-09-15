"""The order lifecycle state machine.

Every state change an order can ever make is described here. Nothing else in
the codebase is allowed to invent a transition: ``OrderService.transition_state``
validates against :data:`TRANSITIONS` and then applies the change with a
conditional (compare-and-set) database update, so an illegal or racing
transition is rejected rather than silently corrupting the order.

Lifecycle
---------
``CREATED`` → ``OFFERED`` → ``ACCEPTED`` → ``ARRIVED_AT_MERCHANT`` →
``PICKED_UP`` → ``ARRIVED_AT_CUSTOMER`` → ``DELIVERED``

``READY_FOR_PICKUP`` is a merchant-driven signal ("the food is bagged") that can
arrive at any point before the driver leaves the restaurant, so several states
lead into it. ``CANCELLED`` is reachable from every state up to and including
``ARRIVED_AT_CUSTOMER``.

``DELIVERED`` and ``CANCELLED`` are terminal: their outgoing sets are empty, so
no transition out of them can ever validate.

Un-assignment
-------------
A driver who abandons an order before collecting the food does *not* travel
backwards through this table. ``OrderService.release_driver`` is a separate,
narrowly guarded operation (see :data:`RELEASABLE_STATES`) that clears the
driver and returns the order to ``CREATED`` so dispatch can re-offer it. Keeping
it out of :data:`TRANSITIONS` means the generic ``PUT /orders/{id}/state``
endpoint can never be used to walk an order backwards.
"""

from enum import Enum
from typing import FrozenSet, Set


class OrderState(str, Enum):
    CREATED = "CREATED"
    OFFERED = "OFFERED"
    ACCEPTED = "ACCEPTED"
    ARRIVED_AT_MERCHANT = "ARRIVED_AT_MERCHANT"
    READY_FOR_PICKUP = "READY_FOR_PICKUP"
    PICKED_UP = "PICKED_UP"
    ARRIVED_AT_CUSTOMER = "ARRIVED_AT_CUSTOMER"
    DELIVERED = "DELIVERED"
    CANCELLED = "CANCELLED"


# Define valid transitions
TRANSITIONS: dict[OrderState, Set[OrderState]] = {
    OrderState.CREATED: {OrderState.OFFERED, OrderState.ACCEPTED, OrderState.READY_FOR_PICKUP, OrderState.CANCELLED},
    OrderState.OFFERED: {OrderState.ACCEPTED, OrderState.READY_FOR_PICKUP, OrderState.CREATED, OrderState.CANCELLED},
    OrderState.ACCEPTED: {OrderState.ARRIVED_AT_MERCHANT, OrderState.READY_FOR_PICKUP, OrderState.CANCELLED},
    OrderState.ARRIVED_AT_MERCHANT: {OrderState.PICKED_UP, OrderState.READY_FOR_PICKUP, OrderState.CANCELLED},
    OrderState.READY_FOR_PICKUP: {OrderState.PICKED_UP, OrderState.ARRIVED_AT_MERCHANT, OrderState.CANCELLED},
    OrderState.PICKED_UP: {OrderState.ARRIVED_AT_CUSTOMER, OrderState.DELIVERED, OrderState.CANCELLED},  # Allow consumer confirm
    OrderState.ARRIVED_AT_CUSTOMER: {OrderState.DELIVERED, OrderState.CANCELLED},
    OrderState.DELIVERED: set(),
    OrderState.CANCELLED: set(),
}

#: Once an order reaches one of these it never changes again.
TERMINAL_STATES: FrozenSet[OrderState] = frozenset(
    state for state, outgoing in TRANSITIONS.items() if not outgoing
)

#: States in which a driver is on the job. Used for "what am I doing right
#: now", driver load scoring, and the stuck-order sweep.
ACTIVE_DRIVER_STATES: FrozenSet[OrderState] = frozenset(
    {
        OrderState.ACCEPTED,
        OrderState.ARRIVED_AT_MERCHANT,
        OrderState.READY_FOR_PICKUP,
        OrderState.PICKED_UP,
        OrderState.ARRIVED_AT_CUSTOMER,
    }
)

#: States from which dispatch may (re-)offer an order to drivers.
#: ``ACCEPTED`` is included because a merchant confirming an order also lands it
#: in ``ACCEPTED`` — see :func:`is_dispatchable`, which is what dispatch actually
#: checks, since such an order still has no driver.
DISPATCHABLE_STATES: FrozenSet[OrderState] = frozenset(
    {OrderState.CREATED, OrderState.OFFERED, OrderState.ACCEPTED}
)

#: The driver has been assigned but has not collected the food, so the order can
#: safely be taken off them and returned to the dispatch pool. After
#: ``PICKED_UP`` the driver physically holds the order; recovering that needs a
#: human (support cancels or completes it), never an automatic un-assignment.
RELEASABLE_STATES: FrozenSet[OrderState] = frozenset(
    {
        OrderState.ACCEPTED,
        OrderState.ARRIVED_AT_MERCHANT,
        OrderState.READY_FOR_PICKUP,
    }
)

#: Every state that still allows a cancellation, derived from the table above so
#: the two can never drift apart.
CANCELLABLE_STATES: FrozenSet[OrderState] = frozenset(
    state for state, outgoing in TRANSITIONS.items() if OrderState.CANCELLED in outgoing
)


class InvalidStateTransition(Exception):
    """The requested transition is not allowed from the order's current state."""


class OrderConflict(InvalidStateTransition):
    """Another writer changed the order first, so this write was refused.

    Raised when a conditional update loses its race — two drivers accepting the
    same offer, or a merchant cancelling while a driver accepts. It subclasses
    :class:`InvalidStateTransition` so existing handlers still degrade to a 400,
    but callers that care can map it to ``409 Conflict``.
    """


def coerce_state(value) -> OrderState:
    """Normalize a state read from the database or the wire into an OrderState.

    Historic documents were written with the enum's *repr* (``"OrderState.CREATED"``)
    rather than its value, so that spelling is accepted too. Anything
    unrecognisable raises :class:`InvalidStateTransition` instead of leaking a
    ``KeyError``/``ValueError`` out of the domain layer.
    """
    if isinstance(value, OrderState):
        return value
    text = getattr(value, "value", value)
    if not isinstance(text, str):
        raise InvalidStateTransition(f"Unknown order state: {value!r}")
    if text.startswith("OrderState."):
        text = text[len("OrderState.") :]
    try:
        return OrderState(text)
    except ValueError:
        raise InvalidStateTransition(f"Unknown order state: {value!r}") from None


def state_aliases(state: OrderState) -> list:
    """Every spelling of `state` that may appear in a stored document.

    Compare-and-set filters match on these so a legacy document written as
    ``"OrderState.CREATED"`` is still guarded rather than silently skipped.
    """
    return [state.value, f"OrderState.{state.name}"]


def can_transition(current, next_state) -> bool:
    """True when `current` → `next_state` is a legal move."""
    try:
        current_state = coerce_state(current)
        target = coerce_state(next_state)
    except InvalidStateTransition:
        return False
    return target in TRANSITIONS.get(current_state, set())


def validate_transition(current, next_state):
    """Raise :class:`InvalidStateTransition` unless the move is legal."""
    current_state = coerce_state(current)
    target = coerce_state(next_state)
    if target not in TRANSITIONS.get(current_state, set()):
        if current_state in TERMINAL_STATES:
            raise InvalidStateTransition(
                f"Order is already {current_state.value}; {current_state.value} is a "
                "final state and cannot change"
            )
        raise InvalidStateTransition(
            f"Cannot transition from {current_state} to {target}"
        )


def is_dispatchable(state, driver_id=None) -> bool:
    """True when dispatch should still be trying to place this order.

    ``CREATED`` and ``OFFERED`` are the obvious cases. ``ACCEPTED`` counts too
    *as long as no driver is assigned*: the merchant dashboard confirms an order
    by moving it to ``ACCEPTED``, which says the kitchen has the order, not that
    a driver has it. Treating that as "placed" is how orders used to fall out of
    dispatch and strand the consumer.
    """
    try:
        current = coerce_state(state)
    except InvalidStateTransition:
        return False
    if current in (OrderState.CREATED, OrderState.OFFERED):
        return not driver_id
    return current is OrderState.ACCEPTED and not driver_id


def is_driver_claim(current, target, driver_id) -> bool:
    """True for the one self-transition the machine allows: a driver claiming.

    ``ACCEPTED → ACCEPTED`` is otherwise illegal, but a driver taking an order a
    merchant has already confirmed — or retrying their own accept after a
    dropped response — is exactly that move. It is only ever permitted when it
    assigns a driver, and the conditional write still refuses if someone else
    claimed the order first, so it cannot be used to steal a delivery.
    """
    if not driver_id:
        return False
    try:
        return (
            coerce_state(current) is OrderState.ACCEPTED
            and coerce_state(target) is OrderState.ACCEPTED
        )
    except InvalidStateTransition:
        return False


def is_terminal(state) -> bool:
    """True when the order can never change state again."""
    try:
        return coerce_state(state) in TERMINAL_STATES
    except InvalidStateTransition:
        return False
