import pytest
from app.order.state_machine import OrderState, validate_transition, InvalidStateTransition

def test_valid_transitions():
    # CREATED -> OFFERED
    validate_transition(OrderState.CREATED, OrderState.OFFERED)
    
    # OFFERED -> ACCEPTED
    validate_transition(OrderState.OFFERED, OrderState.ACCEPTED)
    
    # ACCEPTED -> ARRIVED_AT_MERCHANT
    validate_transition(OrderState.ACCEPTED, OrderState.ARRIVED_AT_MERCHANT)

    # ACCEPTED -> READY_FOR_PICKUP
    validate_transition(OrderState.ACCEPTED, OrderState.READY_FOR_PICKUP)

    # READY_FOR_PICKUP -> PICKED_UP
    validate_transition(OrderState.READY_FOR_PICKUP, OrderState.PICKED_UP)

    # READY_FOR_PICKUP -> ARRIVED_AT_MERCHANT
    validate_transition(OrderState.READY_FOR_PICKUP, OrderState.ARRIVED_AT_MERCHANT)

def test_invalid_transitions():
    # CREATED -> DELIVERED (skip steps)
    with pytest.raises(InvalidStateTransition):
        validate_transition(OrderState.CREATED, OrderState.DELIVERED)
        
    # DELIVERED -> CREATED (backward)
    with pytest.raises(InvalidStateTransition):
        validate_transition(OrderState.DELIVERED, OrderState.CREATED)

def test_cancellation():
    # Can cancel from most states
    validate_transition(OrderState.CREATED, OrderState.CANCELLED)
    validate_transition(OrderState.OFFERED, OrderState.CANCELLED)
    validate_transition(OrderState.ACCEPTED, OrderState.CANCELLED)
