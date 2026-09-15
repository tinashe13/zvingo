"""Restaurant availability: structured hours, timezone, override, and pause."""

from datetime import datetime, timedelta, timezone as dt_timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.catalog.hours import (
    DEFAULT_TIMEZONE,
    DayHours,
    HoursInterval,
    InvalidHours,
    availability_of,
    compute_availability,
    describe_week,
    format_hhmm,
    next_opening,
    normalise_week,
    parse_hhmm,
    parse_legacy_hours,
    to_local,
)


def utc(year, month, day, hour, minute=0):
    """A naive-UTC instant, matching what the platform persists."""
    return datetime(year, month, day, hour, minute)


def week(**days):
    """Build a week from {weekday_index: "HH:MM-HH:MM"} pairs."""
    entries = []
    for day, text in days.items():
        index = int(day.lstrip("d"))
        open_at, close_at = text.split("-")
        entries.append(
            DayHours(day=index, intervals=[HoursInterval(open=open_at, close=close_at)])
        )
    return entries


# ── Time parsing ────────────────────────────────────────────────────


def test_parse_and_format_round_trip():
    assert parse_hhmm("08:30") == 8 * 60 + 30
    assert parse_hhmm("00:00") == 0
    assert parse_hhmm("24:00") == 24 * 60
    assert format_hhmm(parse_hhmm("23:59")) == "23:59"
    # Past-midnight overflow wraps rather than producing "26:00".
    assert format_hhmm(26 * 60) == "02:00"


@pytest.mark.parametrize("bad", ["", "8:30pm", "25:00", "08:70", "0830", None, 815])
def test_parse_rejects_nonsense(bad):
    with pytest.raises(InvalidHours):
        parse_hhmm(bad)


def test_overlapping_windows_on_one_day_are_rejected():
    with pytest.raises(Exception):
        DayHours(
            day=0,
            intervals=[
                HoursInterval(open="08:00", close="14:00"),
                HoursInterval(open="13:00", close="20:00"),
            ],
        )


def test_normalise_week_merges_duplicate_days_and_orders_them():
    merged = normalise_week(
        [
            DayHours(day=2, intervals=[HoursInterval(open="18:00", close="22:00")]),
            DayHours(day=0, intervals=[HoursInterval(open="08:00", close="11:00")]),
            DayHours(day=0, intervals=[HoursInterval(open="12:00", close="15:00")]),
        ]
    )
    assert [d.day for d in merged] == [0, 2]
    assert [i.open for i in merged[0].intervals] == ["08:00", "12:00"]


# ── Timezone ────────────────────────────────────────────────────────


def test_local_time_is_harare_not_utc():
    """Africa/Harare is UTC+02:00 year round — no DST to get wrong."""
    local = to_local(utc(2026, 6, 15, 6, 0), DEFAULT_TIMEZONE)
    assert (local.hour, local.minute) == (8, 0)
    # Mid-winter and mid-summer resolve identically.
    assert to_local(utc(2026, 12, 15, 6, 0), DEFAULT_TIMEZONE).hour == 8


def test_unknown_timezone_falls_back_instead_of_crashing():
    local = to_local(utc(2026, 6, 15, 6, 0), "Mars/Olympus_Mons")
    assert local.hour == 8


def test_schedule_is_evaluated_in_local_time():
    """08:00–17:00 Harare is 06:00–15:00 UTC, and the boundary must hold."""
    hours = week(d0="08:00-17:00")
    # 05:59 UTC == 07:59 local — still closed.
    assert not compute_availability(hours=hours, now=utc(2026, 9, 14, 5, 59))["is_open"]
    # 06:01 UTC == 08:01 local — open.
    assert compute_availability(hours=hours, now=utc(2026, 9, 14, 6, 1))["is_open"]
    # 15:01 UTC == 17:01 local — closed again.
    assert not compute_availability(hours=hours, now=utc(2026, 9, 14, 15, 1))["is_open"]


def test_aware_utc_input_is_handled_like_naive():
    hours = week(d0="08:00-17:00")
    aware = utc(2026, 9, 14, 6, 1).replace(tzinfo=dt_timezone.utc)
    assert compute_availability(hours=hours, now=aware)["is_open"]


# ── Windows that cross midnight ─────────────────────────────────────


def test_window_spanning_midnight_stays_open_after_midnight():
    # Monday 18:00 → 02:00 Tuesday, local time.
    hours = [
        DayHours(day=0, intervals=[HoursInterval(open="18:00", close="02:00")])
    ]
    # Tuesday 00:30 local == Monday 22:30 UTC.
    state = compute_availability(hours=hours, now=utc(2026, 9, 14, 22, 30))
    assert state["is_open"]
    # Tuesday 03:00 local == Tuesday 01:00 UTC — shut.
    assert not compute_availability(hours=hours, now=utc(2026, 9, 15, 1, 0))["is_open"]


# ── Availability precedence ─────────────────────────────────────────


def test_delisted_restaurant_is_unlisted_whatever_the_schedule_says():
    state = compute_availability(
        is_active=False, hours=week(d0="00:00-24:00"), is_open_override=True
    )
    assert state["status"] == "unlisted"
    assert state["is_open"] is False
    assert state["accepts_scheduled"] is False


def test_pause_beats_override_and_reports_when_it_lifts():
    now = utc(2026, 9, 14, 9, 0)
    state = compute_availability(
        hours=week(d0="08:00-22:00"),
        is_open_override=True,
        pause_until=now + timedelta(minutes=30),
        now=now,
    )
    assert state["status"] == "paused"
    assert state["is_open"] is False
    assert state["opens_at"].startswith("2026-09-14T11:30")  # 09:30 UTC → 11:30 local


def test_expired_pause_is_ignored():
    now = utc(2026, 9, 14, 9, 0)
    state = compute_availability(
        hours=week(d0="08:00-22:00"), pause_until=now - timedelta(minutes=1), now=now
    )
    assert state["is_open"] is True


def test_manual_close_overrides_an_open_schedule():
    now = utc(2026, 9, 14, 9, 0)  # 11:00 local, Monday
    state = compute_availability(
        hours=week(d0="08:00-22:00"), is_open_override=False, now=now
    )
    assert state["status"] == "closed_by_merchant"
    assert state["is_open"] is False
    # It still tells the consumer when the restaurant is next scheduled to open.
    assert state["opens_at"] is not None


def test_manual_open_overrides_a_closed_schedule():
    now = utc(2026, 9, 14, 3, 0)  # 05:00 local, before opening
    state = compute_availability(
        hours=week(d0="08:00-22:00"), is_open_override=True, now=now
    )
    assert state["is_open"] is True
    assert state["status"] == "open"


def test_override_none_follows_the_schedule():
    hours = week(d0="08:00-22:00")
    assert compute_availability(
        hours=hours, is_open_override=None, now=utc(2026, 9, 14, 9, 0)
    )["is_open"]


def test_restaurant_with_no_schedule_stays_orderable():
    """Legacy documents have no hours; they must not vanish from the market."""
    state = compute_availability(hours=[], now=utc(2026, 9, 14, 3, 0))
    assert state["is_open"] is True


def test_closed_restaurant_reports_the_next_opening_and_accepts_preorders():
    # Sunday 20:00 UTC == Sunday 22:00 local; open again Monday 08:00 local.
    hours = week(d0="08:00-22:00")
    state = compute_availability(hours=hours, now=utc(2026, 9, 13, 20, 0))
    assert state["status"] == "closed"
    assert state["is_open"] is False
    assert state["accepts_scheduled"] is True
    assert state["opens_at"].startswith("2026-09-14T08:00")
    assert "Opens" in state["reason"]


def test_scheduled_orders_can_be_switched_off():
    state = compute_availability(
        hours=week(d0="08:00-22:00"),
        accepts_scheduled_orders=False,
        now=utc(2026, 9, 13, 20, 0),
    )
    assert state["accepts_scheduled"] is False


def test_next_opening_gives_up_on_a_permanently_closed_week():
    assert next_opening([], to_local(utc(2026, 9, 14, 9, 0), DEFAULT_TIMEZONE)) is None
    always_shut = [DayHours(day=d, intervals=[]) for d in range(7)]
    assert (
        next_opening(always_shut, to_local(utc(2026, 9, 14, 9, 0), DEFAULT_TIMEZONE))
        is None
    )


# ── Display + legacy bridge ─────────────────────────────────────────


def test_describe_week_collapses_consecutive_identical_days():
    hours = normalise_week(
        [
            DayHours(day=d, intervals=[HoursInterval(open="08:00", close="22:00")])
            for d in range(5)
        ]
        + [DayHours(day=5, intervals=[HoursInterval(open="09:00", close="23:00")])]
        + [DayHours(day=6, intervals=[])]
    )
    summary = describe_week(hours)
    assert "Mon-Fri 08:00-22:00" in summary
    assert "Sat 09:00-23:00" in summary
    assert "Sun closed" in summary


def test_legacy_hours_string_is_bridged_into_a_real_week():
    bridged = parse_legacy_hours("08:00-22:00")
    assert len(bridged) == 7
    assert bridged[0].intervals[0].open == "08:00"
    # Junk is ignored rather than producing a nonsense schedule.
    assert parse_legacy_hours("whenever we feel like it") == []
    assert parse_legacy_hours(None) == []


def test_availability_of_tolerates_a_legacy_document():
    """A restaurant saved before these fields existed must not explode."""
    legacy = SimpleNamespace(name="Old Place")
    state = availability_of(legacy)
    assert state["is_open"] is True
    assert state["timezone"] == DEFAULT_TIMEZONE


# ── The merchant-facing status endpoint ─────────────────────────────


def restaurant_double(**overrides):
    values = {
        "id": "restaurant-1",
        "merchant_id": "merchant-1",
        "is_active": True,
        "hours": [],
        "timezone": DEFAULT_TIMEZONE,
        "is_open_override": None,
        "pause_until": None,
        "accepts_scheduled_orders": True,
        "operating_hours": None,
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def merchant(id="merchant-1"):
    return SimpleNamespace(id=id, role="merchant")


@pytest.mark.asyncio
async def test_status_endpoint_persists_hours_and_derives_the_display_string(monkeypatch):
    import app.catalog.router as module

    current = restaurant_double()
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=current))

    payload = module.RestaurantStatusUpdate(
        hours=[
            module.DayHours(
                day=d, intervals=[{"open": "08:00", "close": "22:00"}]
            )
            for d in range(7)
        ]
    )
    result = await module.update_restaurant_status("restaurant-1", payload, merchant())

    current.save.assert_awaited_once()
    assert len(current.hours) == 7
    assert current.operating_hours == "Mon-Sun 08:00-22:00"
    assert result["availability"]["timezone"] == DEFAULT_TIMEZONE


@pytest.mark.asyncio
async def test_status_endpoint_toggles_and_clears_the_override(monkeypatch):
    import app.catalog.router as module

    current = restaurant_double(hours=week(d0="08:00-22:00"))
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=current))

    await module.update_restaurant_status(
        "restaurant-1", module.RestaurantStatusUpdate(is_open_override=False), merchant()
    )
    assert current.is_open_override is False

    # Explicitly sending null hands control back to the schedule.
    await module.update_restaurant_status(
        "restaurant-1",
        module.RestaurantStatusUpdate.model_validate({"is_open_override": None}),
        merchant(),
    )
    assert current.is_open_override is None


@pytest.mark.asyncio
async def test_status_endpoint_snoozes_and_resumes(monkeypatch):
    import app.catalog.router as module

    current = restaurant_double()
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=current))

    await module.update_restaurant_status(
        "restaurant-1", module.RestaurantStatusUpdate(pause_minutes=45), merchant()
    )
    assert current.pause_until is not None
    assert current.pause_until > module.utc_now()

    await module.update_restaurant_status(
        "restaurant-1", module.RestaurantStatusUpdate(resume=True), merchant()
    )
    assert current.pause_until is None


@pytest.mark.asyncio
async def test_status_endpoint_rejects_conflicting_pause_inputs(monkeypatch):
    import app.catalog.router as module

    current = restaurant_double()
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=current))

    with pytest.raises(HTTPException) as exc:
        await module.update_restaurant_status(
            "restaurant-1",
            module.RestaurantStatusUpdate(
                pause_minutes=10, pause_until=module.utc_now()
            ),
            merchant(),
        )
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_status_endpoint_is_owner_scoped(monkeypatch):
    import app.catalog.router as module

    current = restaurant_double()
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=current))

    with pytest.raises(HTTPException) as exc:
        await module.update_restaurant_status(
            "restaurant-1",
            module.RestaurantStatusUpdate(is_open_override=False),
            merchant(id="someone-else"),
        )
    assert exc.value.status_code == 403
    current.save.assert_not_awaited()

    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.get_restaurant_status("missing")
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_legacy_put_bridges_the_hours_string(monkeypatch):
    """The old dashboard PUTs "08:00-22:00"; that must become a real schedule."""
    import app.catalog.router as module

    current = restaurant_double()
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=current))

    await module.update_restaurant(
        "restaurant-1",
        module.RestaurantUpdate(operating_hours="08:00-22:00"),
        merchant(),
    )
    assert len(current.hours) == 7
    assert current.operating_hours == "08:00-22:00"


# ── The computed fields must never reach MongoDB ────────────────────


def test_availability_is_computed_for_responses_but_never_persisted():
    """`availability`/`is_currently_open`/`discovery` are derived, not stored.

    Beanie serialises a document by iterating its *model fields*, so a
    `computed_field` is visible to API consumers and invisible to the database.
    If any of these ever became a real field, every save would write a stale
    snapshot of "are we open right now" into MongoDB.
    """
    from app.catalog.models import Restaurant

    derived = {"availability", "is_currently_open", "discovery"}
    assert derived <= set(Restaurant.model_computed_fields)
    assert derived.isdisjoint(Restaurant.model_fields)
    # The discovery payload rides on a private attribute, also not a field.
    assert "_discovery" in Restaurant.__private_attributes__


def test_the_structured_hours_fields_are_persisted():
    from app.catalog.models import Restaurant

    for field in (
        "hours",
        "timezone",
        "is_open_override",
        "pause_until",
        "accepts_scheduled_orders",
        "operating_hours",
    ):
        assert field in Restaurant.model_fields, field


def test_the_availability_block_a_client_receives_has_a_stable_shape():
    """This exact dict rides on every restaurant payload — clients depend on it."""
    availability = compute_availability(
        hours=[
            DayHours(day=d, intervals=[HoursInterval(open="08:00", close="22:00")])
            for d in range(7)
        ],
        is_open_override=False,
        now=utc(2026, 9, 14, 9, 0),
    )
    assert set(availability) == {
        "is_open",
        "status",
        "reason",
        "timezone",
        "local_time",
        "opens_at",
        "closes_at",
        "accepts_scheduled",
    }
    assert availability["is_open"] is False
    assert availability["status"] == "closed_by_merchant"
    assert availability["timezone"] == DEFAULT_TIMEZONE
    assert availability["local_time"] == "11:00"

    # The stored schedule serialises to the shape the dashboard posts back.
    assert DayHours(
        day=0, intervals=[HoursInterval(open="08:00", close="22:00")]
    ).model_dump() == {"day": 0, "intervals": [{"open": "08:00", "close": "22:00"}]}
