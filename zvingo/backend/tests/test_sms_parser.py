from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.order.state_machine import OrderState
from app.sms.parser import SMSParser


class FakeRedis:
    def __init__(self, status="OFFLINE"):
        self.status = status
        self.closed = False

    async def hgetall(self, _key):
        return {"status": self.status}

    async def close(self):
        self.closed = True


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("ACCEPT ORDER_123", ("ACCEPT", ["ORDER_123"])),
        ("  status  ", ("STATUS", [])),
        ("", (None, None)),
        ("   ", (None, None)),
    ],
)
def test_parse_command(text, expected):
    assert SMSParser.parse_command(text) == expected


@pytest.mark.asyncio
async def test_get_driver_by_phone(monkeypatch):
    import app.auth.models as models

    class Field:
        def __eq__(self, other):
            return other

    find = AsyncMock(return_value="driver")

    class FakeUser:
        phone = Field()
        role = Field()
        find_one = find

    monkeypatch.setattr(models, "User", FakeUser)
    assert await SMSParser._get_driver_by_phone("+263") == "driver"
    find.assert_awaited_once()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("command", "message"),
    [
        ("ACCEPT", "Invalid format. Use: ACCEPT <ORDER_ID>"),
        ("DECLINE", "Invalid format. Use: DECLINE <ORDER_ID>"),
        ("COMPLETE", "Invalid format. Use: COMPLETE <ORDER_ID>"),
        ("HELP", "Commands: ACCEPT <id>, DECLINE <id>, COMPLETE <id>, STATUS"),
        ("", "Commands: ACCEPT <id>, DECLINE <id>, COMPLETE <id>, STATUS"),
    ],
)
async def test_simple_command_responses(command, message):
    assert await SMSParser.handle_command("+263", command) == message


@pytest.mark.asyncio
@pytest.mark.parametrize("command", ["ACCEPT 1", "COMPLETE 1"])
async def test_driver_required(command, monkeypatch):
    monkeypatch.setattr(SMSParser, "_get_driver_by_phone", AsyncMock(return_value=None))
    assert "Driver not found" in await SMSParser.handle_command("+263", command)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("command", "state", "success_text", "missing_text", "error_text"),
    [
        (
            "ACCEPT 1",
            OrderState.ACCEPTED,
            "Order 1 accepted. Head to merchant for pickup.",
            "Order 1 not found",
            "Cannot accept order 1. It may already be taken.",
        ),
        (
            "COMPLETE 1",
            OrderState.DELIVERED,
            "Order 1 delivered. Earnings updated.",
            "Order 1 not found",
            "Cannot complete order 1. Contact support.",
        ),
    ],
)
async def test_order_commands(
    command, state, success_text, missing_text, error_text, monkeypatch
):
    import app.order.service as service

    driver = SimpleNamespace(id="driver-1")
    monkeypatch.setattr(SMSParser, "_get_driver_by_phone", AsyncMock(return_value=driver))
    transition = AsyncMock(return_value=SimpleNamespace(id="1"))
    monkeypatch.setattr(service.OrderService, "transition_state", transition)
    assert await SMSParser.handle_command("+263", command) == success_text
    # Both ACCEPT and COMPLETE must scope the write to the texting driver.
    # COMPLETE previously omitted driver_id, which let any driver complete any
    # order by SMS; this assertion is what stops that regressing.
    transition.assert_awaited_with("1", state, "driver-1", driver_id="driver-1")
    transition.return_value = None
    assert await SMSParser.handle_command("+263", command) == missing_text
    transition.side_effect = RuntimeError("boom")
    assert await SMSParser.handle_command("+263", command) == error_text


@pytest.mark.asyncio
async def test_status_command(monkeypatch):
    import app.order.models as models
    import app.sms.parser as module

    monkeypatch.setattr(
        SMSParser,
        "_get_driver_by_phone",
        AsyncMock(return_value=SimpleNamespace(id="driver-1")),
    )
    redis = FakeRedis("ONLINE")
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    class Field:
        def __eq__(self, other):
            return other

    query = SimpleNamespace(count=AsyncMock(return_value=2))

    class FakeOrder:
        driver_id = Field()
        state = Field()
        find = MagicMock(return_value=query)

    monkeypatch.setattr(models, "Order", FakeOrder)
    assert await SMSParser.handle_command("+263", "STATUS") == (
        "Status: ONLINE. Active orders: 2"
    )
    assert redis.closed

    monkeypatch.setattr(SMSParser, "_get_driver_by_phone", AsyncMock(return_value=None))
    assert await SMSParser.handle_command("+263", "STATUS") == "Driver not found"


@pytest.mark.asyncio
async def test_decline_forwards_to_dispatch(monkeypatch):
    """DECLINE used to return a friendly string without telling dispatch, so the
    offer sat until it timed out while the driver believed they had released it."""
    import app.dispatch.service as dispatch_module

    driver = SimpleNamespace(id="driver-1")
    monkeypatch.setattr(SMSParser, "_get_driver_by_phone", AsyncMock(return_value=driver))
    decline = AsyncMock()
    monkeypatch.setattr(dispatch_module.dispatch_service, "decline_offer", decline)

    assert await SMSParser.handle_command("+263", "DECLINE ABC") == "Order ABC declined."
    decline.assert_awaited_once_with("driver-1", "ABC")
