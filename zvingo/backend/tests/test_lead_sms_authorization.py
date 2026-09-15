"""SMS driver commands must be scoped to the driver who sent the text.

The SMS channel is a real control surface: a driver on a feature phone, or on
no data, can accept and complete deliveries over it. Every command that writes
must therefore carry the same ownership check the HTTP and WebSocket paths do.

COMPLETE previously did not, so any registered driver could text
``COMPLETE <order id>`` for an order belonging to someone else and mark it
delivered -- crediting themselves the earnings and denying them to the driver
who actually did the work.
"""

from unittest.mock import AsyncMock

import pytest

from app.order.state_machine import OrderState
from app.sms.parser import SMSParser


class _Driver:
    def __init__(self, ident):
        self.id = ident


@pytest.fixture
def texting_driver(monkeypatch):
    """The driver whose phone the SMS arrives from."""
    driver = _Driver("driver-texting")
    monkeypatch.setattr(
        SMSParser,
        "_get_driver_by_phone",
        AsyncMock(return_value=driver),
    )
    return driver


@pytest.mark.asyncio
async def test_complete_scopes_the_transition_to_the_texting_driver(
    texting_driver, monkeypatch
):
    import app.order.service as order_service

    transition = AsyncMock(return_value=None)
    monkeypatch.setattr(order_service.OrderService, "transition_state", transition)

    await SMSParser.handle_command("+263771234567", "COMPLETE order-belonging-to-someone-else")

    transition.assert_awaited_once()
    kwargs = transition.await_args.kwargs

    # The ownership predicate is what makes this safe. Without it the state
    # machine would happily deliver an order this driver never touched.
    assert kwargs.get("driver_id") == "driver-texting", (
        "COMPLETE must pass driver_id so the update is filtered to this "
        "driver's own order; otherwise any driver can complete any order by SMS"
    )

    args = transition.await_args.args
    assert args[0] == "order-belonging-to-someone-else"
    assert args[1] == OrderState.DELIVERED


@pytest.mark.asyncio
async def test_accept_scopes_the_transition_to_the_texting_driver(
    texting_driver, monkeypatch
):
    import app.order.service as order_service

    transition = AsyncMock(return_value=None)
    monkeypatch.setattr(order_service.OrderService, "transition_state", transition)

    await SMSParser.handle_command("+263771234567", "ACCEPT order-1")

    assert transition.await_args.kwargs.get("driver_id") == "driver-texting"


@pytest.mark.asyncio
async def test_decline_actually_tells_dispatch(texting_driver, monkeypatch):
    """DECLINE used to return a friendly string and do nothing at all."""
    import app.dispatch.service as dispatch_module

    decline = AsyncMock()
    monkeypatch.setattr(dispatch_module.dispatch_service, "decline_offer", decline)

    reply = await SMSParser.handle_command("+263771234567", "DECLINE order-9")

    decline.assert_awaited_once_with("driver-texting", "order-9")
    assert "declined" in reply.lower()


@pytest.mark.asyncio
async def test_failures_do_not_leak_internal_detail_over_sms(
    texting_driver, monkeypatch
):
    import app.order.service as order_service

    monkeypatch.setattr(
        order_service.OrderService,
        "transition_state",
        AsyncMock(side_effect=RuntimeError("mongodb://user:pw@cluster/internal blew up")),
    )

    reply = await SMSParser.handle_command("+263771234567", "COMPLETE order-1")

    assert "mongodb" not in reply.lower()
    assert "blew up" not in reply.lower()
    assert "order-1" in reply
