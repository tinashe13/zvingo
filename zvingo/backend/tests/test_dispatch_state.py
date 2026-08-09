from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest


@pytest.mark.asyncio
@pytest.mark.parametrize("active_order", [None, SimpleNamespace(
    id="abcdef", state="ACCEPTED", pickup_location={"lat": 1},
    dropoff_location={"lat": 2},
)])
async def test_get_driver_state_with_and_without_active_order(monkeypatch, active_order):
    import app.dispatch.router as module

    monkeypatch.setattr(
        module.dispatch_service,
        "get_driver_state",
        AsyncMock(return_value={"status": "ONLINE", "active_order": active_order}),
    )
    result = await module.get_driver_state(SimpleNamespace(id="driver-1"))
    assert result["status"] == "ONLINE"
    if active_order is None:
        assert result["active_order"] is None
    else:
        assert result["active_order"]["short_id"] == "ZVCDEF"
