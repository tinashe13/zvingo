from enum import Enum
from typing import Set

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

class InvalidStateTransition(Exception):
    pass

def validate_transition(current: OrderState, next_state: OrderState):
    if next_state not in TRANSITIONS[current]:
        raise InvalidStateTransition(f"Cannot transition from {current} to {next_state}")
