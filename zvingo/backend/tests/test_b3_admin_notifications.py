"""Admin authorization audit, notification preferences, and the SMS gateway split."""

import inspect
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException
from fastapi.routing import APIRoute
from pydantic import ValidationError

from app.auth.router import get_current_admin, get_current_user
from app.time_utils import utc_now


def user(id="user-1", role="consumer"):
    return SimpleNamespace(id=id, role=role, save=AsyncMock())


def stored_preference(**overrides):
    """A preferences document double — Beanie is not initialised in tests."""
    import app.notification.preferences as preferences

    values = {**preferences.DEFAULTS, "user_id": "user-1"}
    values.update(overrides)
    return SimpleNamespace(**values)


def dependency_names(route: APIRoute) -> set:
    """Every dependency callable in a route's resolved dependency tree."""
    found = set()
    stack = list(route.dependant.dependencies)
    while stack:
        dependant = stack.pop()
        if dependant.call is not None:
            found.add(dependant.call)
        stack.extend(dependant.dependencies)
    return found


def admin_routes():
    from app.admin import router as admin_router

    return [r for r in admin_router.router.routes if isinstance(r, APIRoute)]


# ── Admin authorization ─────────────────────────────────────────────


def test_every_admin_route_requires_the_admin_role():
    """An admin endpoint reachable by a normal user is a total compromise."""
    routes = admin_routes()
    assert routes, "admin router exposed no routes — the audit would be vacuous"

    unguarded = [
        f"{sorted(r.methods)} {r.path}"
        for r in routes
        if get_current_admin not in dependency_names(r)
    ]
    assert unguarded == []


def test_no_admin_route_settles_for_plain_authentication():
    """`get_current_user` alone would let any signed-in consumer through."""
    weak = [
        f"{sorted(r.methods)} {r.path}"
        for r in admin_routes()
        if get_current_user in dependency_names(r)
        and get_current_admin not in dependency_names(r)
    ]
    assert weak == []


@pytest.mark.asyncio
async def test_get_current_admin_rejects_every_non_admin_role():
    for role in ("consumer", "driver", "merchant", "", None):
        with pytest.raises(HTTPException) as exc:
            await get_current_admin(SimpleNamespace(id="u", role=role))
        assert exc.value.status_code == 403

    admin = SimpleNamespace(id="a", role="admin")
    assert await get_current_admin(admin) is admin


def test_the_catalog_location_reset_endpoint_requires_an_admin():
    """It rewrites every restaurant's coordinates — a flag is not a guard."""
    from app.catalog import router as catalog_router

    route = next(
        r
        for r in catalog_router.router.routes
        if isinstance(r, APIRoute) and r.path.endswith("/admin/reset-locations")
    )
    assert get_current_admin in dependency_names(route)


@pytest.mark.asyncio
async def test_reset_locations_still_honours_the_dev_flag(monkeypatch):
    import app.catalog.router as module

    admin = user(id="admin-1", role="admin")
    monkeypatch.setattr(module, "backfill_restaurant_locations", AsyncMock())

    monkeypatch.setattr(module.settings, "DEV_ALLOW_ADMIN_ENDPOINTS", False)
    with pytest.raises(HTTPException) as exc:
        await module.reset_restaurant_locations(True, admin)
    assert exc.value.status_code == 403

    monkeypatch.setattr(module.settings, "DEV_ALLOW_ADMIN_ENDPOINTS", True)
    assert await module.reset_restaurant_locations(False, admin) == {
        "status": "ok",
        "force_all": False,
    }


def test_admin_listings_are_all_paginated():
    """Every admin listing must take page/page_size — no unbounded scans."""
    from app.admin import router as admin_router

    for name in ("list_users", "list_orders", "list_payments", "list_restaurants"):
        signature = inspect.signature(getattr(admin_router, name))
        assert "page" in signature.parameters, name
        assert "page_size" in signature.parameters, name


# ── SMS ─────────────────────────────────────────────────────────────


def test_sms_send_is_admin_only():
    """An authenticated consumer must not be able to bill the company for SMS."""
    from app.sms import router as sms_router

    route = next(
        r for r in sms_router.router.routes if isinstance(r, APIRoute) and r.path == "/send"
    )
    # get_current_admin resolves through get_current_user, so the admin check
    # being present is what matters.
    assert get_current_admin in dependency_names(route)


def test_sms_router_no_longer_builds_its_own_provider_client():
    import app.sms.router as module

    # The old code did `africastalking.initialize(...)` at import from
    # AT_USERNAME/AT_API_KEY, silently mocking whenever the key was absent.
    assert not hasattr(module, "africastalking")
    assert module.sms_gateway is not None


def test_sms_destination_must_be_e164():
    import app.sms.router as module

    assert module.SMSRequest(to=" +263 771234567 ", message="hi").to == "+263771234567"
    for bad in ("0771234567", "+263abc", "263771234567"):
        with pytest.raises(ValidationError):
            module.SMSRequest(to=bad, message="hi")


def test_sms_gateway_refuses_mock_mode_in_production(monkeypatch):
    import app.sms.gateway as module

    monkeypatch.setattr(module.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(module.settings, "SMS_MOCK_MODE", True)
    with pytest.raises(RuntimeError, match="must not be enabled in production"):
        module.SMSGateway()


def test_sms_gateway_refuses_live_mode_without_credentials(monkeypatch):
    import app.sms.gateway as module

    monkeypatch.setattr(module.settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(module.settings, "SMS_MOCK_MODE", False)
    monkeypatch.setattr(module.settings, "AFRICASTALKING_API_KEY", None)
    with pytest.raises(RuntimeError, match="AFRICASTALKING_API_KEY"):
        module.SMSGateway()


# ── FCM degradation ─────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_push_degrades_loudly_when_firebase_is_unconfigured(monkeypatch):
    import app.notification.fcm as module

    monkeypatch.setattr(module, "_fcm_initialized", False)
    monkeypatch.setattr(module, "_fcm_status", "uninitialised")
    monkeypatch.setattr(module.settings, "FIREBASE_CREDENTIALS_PATH", None)

    assert module.init_firebase() is False
    status = module.fcm_status()
    assert status["available"] is False
    assert "FIREBASE_CREDENTIALS_PATH" in status["reason"]

    before = module.fcm_status()["skipped"]
    assert await module.send_push_notification("token", "T", "B") is False
    # The skip is counted, so "no notifications arrive" is visible, not silent.
    assert module.fcm_status()["skipped"] == before + 1


@pytest.mark.asyncio
async def test_push_handles_a_missing_token_without_crashing(monkeypatch):
    import app.notification.fcm as module

    assert await module.send_push_notification(None, "T", "B") is False
    assert await module.send_push_notification("", "T", "B") is False


# ── Notification preferences ────────────────────────────────────────


@pytest.mark.asyncio
async def test_preferences_default_to_permissive_when_none_are_stored(monkeypatch):
    import app.notification.preferences as module

    monkeypatch.setattr(
        module.NotificationPreference, "find_one", AsyncMock(return_value=None)
    )
    prefs = await module.get_preferences("user-1")
    assert prefs["push_enabled"] is True
    assert prefs["order_updates"] is True
    assert prefs["timezone"] == "Africa/Harare"


@pytest.mark.asyncio
async def test_an_unreadable_preference_store_still_delivers_order_updates(monkeypatch):
    """Losing an order update is worse than ignoring a setting we can't read."""
    import app.notification.preferences as module

    monkeypatch.setattr(
        module.NotificationPreference,
        "find_one",
        AsyncMock(side_effect=RuntimeError("no collection")),
    )
    assert await module.should_notify("user-1", "order_updates") is True


@pytest.mark.asyncio
async def test_a_disabled_category_suppresses_only_that_category(monkeypatch):
    import app.notification.preferences as module

    stored = stored_preference(promotions=False)
    monkeypatch.setattr(
        module.NotificationPreference, "find_one", AsyncMock(return_value=stored)
    )
    assert await module.should_notify("user-1", "promotions") is False
    assert await module.should_notify("user-1", "order_updates") is True


@pytest.mark.asyncio
async def test_disabling_push_silences_every_push_category(monkeypatch):
    import app.notification.preferences as module

    stored = stored_preference(push_enabled=False)
    monkeypatch.setattr(
        module.NotificationPreference, "find_one", AsyncMock(return_value=stored)
    )
    assert await module.should_notify("user-1", "order_updates") is False
    # …but SMS is a separate channel with its own switch.
    assert await module.should_notify("user-1", "order_updates", channel="sms") is True


@pytest.mark.asyncio
async def test_an_unknown_category_is_never_silently_dropped(monkeypatch):
    import app.notification.preferences as module

    assert await module.should_notify("user-1", "brand_new_thing") is True


def test_quiet_hours_are_evaluated_in_local_time():
    from datetime import datetime

    import app.notification.preferences as module

    prefs = {
        **module.DEFAULTS,
        "quiet_hours_start": "22:00",
        "quiet_hours_end": "07:00",
    }
    # 21:00 UTC == 23:00 Harare — inside the window.
    assert module.in_quiet_hours(prefs, now=datetime(2026, 9, 14, 21, 0))
    # 06:00 UTC == 08:00 Harare — outside it.
    assert not module.in_quiet_hours(prefs, now=datetime(2026, 9, 14, 6, 0))
    # 03:00 UTC == 05:00 Harare — still inside, the window spans midnight.
    assert module.in_quiet_hours(prefs, now=datetime(2026, 9, 14, 3, 0))


def test_quiet_hours_need_both_ends_and_survive_junk():
    import app.notification.preferences as module

    assert not module.in_quiet_hours({**module.DEFAULTS, "quiet_hours_start": "22:00"})
    assert not module.in_quiet_hours(
        {**module.DEFAULTS, "quiet_hours_start": "late", "quiet_hours_end": "early"}
    )


@pytest.mark.asyncio
async def test_quiet_hours_never_silence_a_live_delivery(monkeypatch):
    """Order updates and driver offers are urgent — quiet hours do not apply."""
    from datetime import datetime

    import app.notification.preferences as module

    stored = stored_preference(quiet_hours_start="00:00", quiet_hours_end="23:59")
    monkeypatch.setattr(
        module.NotificationPreference, "find_one", AsyncMock(return_value=stored)
    )
    assert await module.should_notify("user-1", "order_updates") is True
    assert await module.should_notify("user-1", "driver_offers") is True
    assert await module.should_notify("user-1", "promotions") is False


@pytest.mark.asyncio
async def test_preference_endpoint_applies_only_the_fields_sent(monkeypatch):
    import app.notification.router as module

    captured = {}

    async def fake_set(user_id, changes):
        captured.update(changes)
        return {"user_id": user_id, **changes}

    monkeypatch.setattr(module, "set_preferences", fake_set)
    await module.update_preferences(
        module.NotificationPreferenceUpdate(promotions=False), user()
    )
    assert captured == {"promotions": False}


@pytest.mark.asyncio
async def test_preference_endpoint_validates_quiet_hours_and_reports_outages(monkeypatch):
    import app.notification.router as module

    with pytest.raises(ValidationError):
        module.NotificationPreferenceUpdate(quiet_hours_start="bedtime")
    assert (
        module.NotificationPreferenceUpdate(quiet_hours_start="9:5").quiet_hours_start
        == "09:05"
    )

    monkeypatch.setattr(
        module, "set_preferences", AsyncMock(side_effect=RuntimeError("no collection"))
    )
    with pytest.raises(HTTPException) as exc:
        await module.update_preferences(
            module.NotificationPreferenceUpdate(promotions=False), user()
        )
    assert exc.value.status_code == 503


@pytest.mark.asyncio
async def test_empty_preference_update_is_a_read(monkeypatch):
    import app.notification.router as module

    monkeypatch.setattr(
        module, "get_preferences", AsyncMock(return_value={"user_id": "user-1"})
    )
    setter = AsyncMock()
    monkeypatch.setattr(module, "set_preferences", setter)
    await module.update_preferences(module.NotificationPreferenceUpdate(), user())
    setter.assert_not_awaited()


# ── Offer counters (acceptance rate) ────────────────────────────────


@pytest.mark.asyncio
async def test_offer_stats_read_the_dispatchers_own_counters(monkeypatch):
    """Acceptance rate reuses dispatch's counters instead of a second tally."""
    import app.notification.offer_metrics as module

    client = SimpleNamespace(
        hmget=AsyncMock(return_value=["12", "9", "2", "1"]), close=AsyncMock()
    )
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: client)

    stats = await module.offer_stats("driver-1")
    assert stats == {
        "offers_sent": 12,
        "offers_accepted": 9,
        "offers_declined": 2,
        "offers_timed_out": 1,
    }
    key, fields = client.hmget.await_args.args
    assert key == "driver:driver-1"
    assert fields == list(module.OFFER_FIELDS)


@pytest.mark.asyncio
async def test_offer_stats_degrade_to_zero_on_redis_failure(monkeypatch):
    import app.notification.offer_metrics as module

    client = SimpleNamespace(
        hmget=AsyncMock(side_effect=RuntimeError("redis down")), close=AsyncMock()
    )
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: client)

    assert await module.offer_stats("driver-1") == {
        field: 0 for field in module.OFFER_FIELDS
    }
    assert await module.offer_stats("") == {field: 0 for field in module.OFFER_FIELDS}


@pytest.mark.asyncio
async def test_missing_counters_read_as_zero_not_as_a_crash(monkeypatch):
    import app.notification.offer_metrics as module

    client = SimpleNamespace(
        hmget=AsyncMock(return_value=[None, "not-a-number", None, None]),
        close=AsyncMock(),
    )
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: client)
    stats = await module.offer_stats("driver-1")
    assert stats["offers_sent"] == 0
    assert stats["offers_accepted"] == 0
