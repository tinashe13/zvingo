"""Restaurant opening hours, timezone handling, and computed availability.

A restaurant's availability is decided by four inputs, in priority order:

1. ``is_active``      — the platform listing switch (admin/merchant delisting).
2. ``pause_until``    — a temporary "stop taking orders for N minutes" snooze.
3. ``is_open_override`` — the merchant dashboard's manual open/closed toggle.
   ``None`` follows the schedule, ``True`` forces open, ``False`` forces closed.
4. ``hours``          — the structured weekly schedule, in the restaurant's own
   timezone (Africa/Harare by default).

Everything in ``hours`` is **local wall-clock time**; everything persisted
(``pause_until``) is naive UTC, matching :func:`app.time_utils.utc_now`.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone as dt_timezone
from functools import lru_cache
from typing import List, Optional, Sequence, Tuple

from pydantic import BaseModel, Field, field_validator, model_validator
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.time_utils import utc_now

#: Zvingo operates in Zimbabwe; every restaurant defaults to Harare time.
DEFAULT_TIMEZONE = "Africa/Harare"

#: Fallback offset used when the platform image ships without tz data.
_FALLBACK_OFFSET = dt_timezone(timedelta(hours=2), "CAT")

DAY_LABELS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

MINUTES_PER_DAY = 24 * 60

# How far ahead `next_open_at` will look before giving up. A restaurant with an
# empty schedule for the whole week genuinely has no next opening.
_LOOKAHEAD_DAYS = 8


class InvalidHours(ValueError):
    """Raised when a submitted weekly schedule cannot be interpreted."""


def parse_hhmm(value: str) -> int:
    """Parse ``"HH:MM"`` into minutes past local midnight.

    ``"24:00"`` is accepted and means end-of-day, which is how a merchant
    expresses "open until midnight".
    """
    if not isinstance(value, str):
        raise InvalidHours(f"Time must be a 'HH:MM' string, got {value!r}")
    parts = value.strip().split(":")
    if len(parts) != 2:
        raise InvalidHours(f"Time must be 'HH:MM', got {value!r}")
    try:
        hour, minute = int(parts[0]), int(parts[1])
    except ValueError:
        raise InvalidHours(f"Time must be 'HH:MM', got {value!r}") from None
    if not (0 <= minute < 60) or not (0 <= hour <= 24) or (hour == 24 and minute):
        raise InvalidHours(f"Time out of range: {value!r}")
    return hour * 60 + minute


def format_hhmm(minutes: int) -> str:
    """Inverse of :func:`parse_hhmm`, normalising past-midnight overflow."""
    minutes %= MINUTES_PER_DAY
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


class HoursInterval(BaseModel):
    """A single open window on one weekday, in local wall-clock time.

    ``close`` <= ``open`` means the window runs past midnight into the next
    day (e.g. ``18:00``–``02:00`` for a late-night kitchen).
    """

    open: str = Field(description="Local opening time, 'HH:MM'")
    close: str = Field(description="Local closing time, 'HH:MM'; <= open spans midnight")

    @field_validator("open", "close")
    @classmethod
    def _valid_time(cls, value: str) -> str:
        return format_hhmm(parse_hhmm(value)) if value != "24:00" else "24:00"

    @property
    def start_minute(self) -> int:
        return parse_hhmm(self.open)

    @property
    def end_minute(self) -> int:
        """End of the window in minutes, > 1440 when it spans midnight."""
        start, end = parse_hhmm(self.open), parse_hhmm(self.close)
        if end <= start:
            end += MINUTES_PER_DAY
        return end


class DayHours(BaseModel):
    """One weekday's opening windows. An empty ``intervals`` list means closed."""

    day: int = Field(ge=0, le=6, description="0=Monday … 6=Sunday")
    intervals: List[HoursInterval] = []

    @model_validator(mode="after")
    def _no_overlaps(self) -> "DayHours":
        spans = sorted(
            (i.start_minute, i.end_minute) for i in self.intervals
        )
        for (a_start, a_end), (b_start, _) in zip(spans, spans[1:]):
            if b_start < a_end:
                raise InvalidHours(
                    f"Overlapping opening windows on {DAY_LABELS[self.day]}"
                )
        return self

    @property
    def is_closed(self) -> bool:
        return not self.intervals


def normalise_week(days: Sequence[DayHours]) -> List[DayHours]:
    """Collapse a submitted week to one entry per weekday, ordered Mon→Sun.

    Duplicate entries for the same day are merged rather than rejected — a
    dashboard that posts two rows for Monday means "open twice on Monday".
    """
    by_day: dict[int, List[HoursInterval]] = {}
    for entry in days:
        by_day.setdefault(entry.day, []).extend(entry.intervals)
    week: List[DayHours] = []
    for day in sorted(by_day):
        intervals = sorted(by_day[day], key=lambda i: i.start_minute)
        # Re-validate the merged day so overlaps across duplicate rows are caught.
        week.append(DayHours(day=day, intervals=intervals))
    return week


@lru_cache(maxsize=64)
def resolve_timezone(name: Optional[str]) -> object:
    """Return a tzinfo for ``name``, falling back to Harare then a fixed +02:00."""
    for candidate in (name, DEFAULT_TIMEZONE):
        if not candidate:
            continue
        try:
            return ZoneInfo(candidate)
        except (ZoneInfoNotFoundError, ValueError, KeyError):
            continue
    return _FALLBACK_OFFSET


def to_local(moment: Optional[datetime], tz_name: Optional[str]) -> datetime:
    """Convert a naive-UTC (or aware) instant into the restaurant's local time."""
    moment = moment or utc_now()
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=dt_timezone.utc)
    return moment.astimezone(resolve_timezone(tz_name))


def _windows_covering(week: Sequence[DayHours], local: datetime) -> List[Tuple[datetime, datetime]]:
    """Open windows (as local datetimes) that could contain ``local``.

    Includes the previous day's windows so a window spanning midnight is still
    recognised at 01:00.
    """
    by_day = {entry.day: entry for entry in week}
    midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
    windows: List[Tuple[datetime, datetime]] = []
    for offset in (-1, 0):
        day_start = midnight + timedelta(days=offset)
        entry = by_day.get(day_start.weekday())
        if not entry:
            continue
        for interval in entry.intervals:
            windows.append(
                (
                    day_start + timedelta(minutes=interval.start_minute),
                    day_start + timedelta(minutes=interval.end_minute),
                )
            )
    return windows


def current_window(
    week: Sequence[DayHours], local: datetime
) -> Optional[Tuple[datetime, datetime]]:
    """The open window containing ``local``, or None when closed."""
    for start, end in _windows_covering(week, local):
        if start <= local < end:
            return start, end
    return None


def next_opening(week: Sequence[DayHours], local: datetime) -> Optional[datetime]:
    """The next local datetime at which the restaurant opens, if any."""
    if not week:
        return None
    by_day = {entry.day: entry for entry in week}
    midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
    for offset in range(_LOOKAHEAD_DAYS):
        day_start = midnight + timedelta(days=offset)
        entry = by_day.get(day_start.weekday())
        if not entry:
            continue
        for interval in sorted(entry.intervals, key=lambda i: i.start_minute):
            opens = day_start + timedelta(minutes=interval.start_minute)
            if opens > local:
                return opens
    return None


def parse_legacy_hours(text: Optional[str]) -> List[DayHours]:
    """Interpret the legacy ``"08:00-22:00"`` string as an every-day schedule.

    The merchant dashboard historically stored a single open/close pair as free
    text. Bridging it into the structured week means existing restaurants get
    real availability without anyone re-entering their hours.
    Returns ``[]`` when the string is not a simple ``HH:MM-HH:MM`` pair.
    """
    if not text or "-" not in text:
        return []
    open_text, _, close_text = text.strip().partition("-")
    try:
        interval = HoursInterval(open=open_text.strip(), close=close_text.strip())
    except (InvalidHours, ValueError):
        return []
    return [DayHours(day=day, intervals=[interval]) for day in range(7)]


def describe_week(week: Sequence[DayHours]) -> str:
    """Human-readable summary, e.g. ``"Mon-Fri 08:00-22:00, Sat 09:00-23:00"``."""
    if not week:
        return ""
    by_day = {entry.day: entry for entry in week}
    rendered = []
    for day in range(7):
        entry = by_day.get(day)
        if not entry or entry.is_closed:
            rendered.append((day, "Closed"))
        else:
            rendered.append(
                (day, ", ".join(f"{i.open}-{i.close}" for i in entry.intervals))
            )

    # Collapse consecutive days that share the same text into ranges.
    parts: List[str] = []
    run_start = 0
    for index in range(1, 8):
        same = index < 7 and rendered[index][1] == rendered[run_start][1]
        if same:
            continue
        label = DAY_LABELS[run_start]
        if index - 1 > run_start:
            label = f"{DAY_LABELS[run_start]}-{DAY_LABELS[index - 1]}"
        text = rendered[run_start][1]
        parts.append(f"{label} closed" if text == "Closed" else f"{label} {text}")
        run_start = index
    return ", ".join(parts)


# ── Availability ────────────────────────────────────────────────────

STATUS_OPEN = "open"
STATUS_CLOSED = "closed"
STATUS_CLOSED_BY_MERCHANT = "closed_by_merchant"
STATUS_PAUSED = "paused"
STATUS_UNLISTED = "unlisted"


def compute_availability(
    *,
    is_active: bool = True,
    hours: Optional[Sequence[DayHours]] = None,
    tz_name: Optional[str] = DEFAULT_TIMEZONE,
    is_open_override: Optional[bool] = None,
    pause_until: Optional[datetime] = None,
    accepts_scheduled_orders: bool = True,
    now: Optional[datetime] = None,
) -> dict:
    """Resolve whether a restaurant is open right now, and why.

    Returns a JSON-safe dict that every restaurant payload carries, so clients
    never have to re-implement the rules:

    ``is_open``            can this restaurant take an order right now
    ``status``             open | closed | closed_by_merchant | paused | unlisted
    ``reason``             short human sentence for the UI badge
    ``timezone``           IANA zone the schedule is expressed in
    ``local_time``         the restaurant's current wall-clock time, "HH:MM"
    ``opens_at``           ISO-8601 local datetime of the next opening, or null
    ``closes_at``          ISO-8601 local datetime the current window ends, or null
    ``accepts_scheduled``  whether a pre-order may still be placed while closed
    """
    week = list(hours or [])
    local = to_local(now, tz_name)
    resolved_tz = tz_name or DEFAULT_TIMEZONE

    def result(status: str, reason: str, *, opens_at=None, closes_at=None) -> dict:
        is_open = status == STATUS_OPEN
        return {
            "is_open": is_open,
            "status": status,
            "reason": reason,
            "timezone": resolved_tz,
            "local_time": local.strftime("%H:%M"),
            "opens_at": opens_at.isoformat() if opens_at else None,
            "closes_at": closes_at.isoformat() if closes_at else None,
            "accepts_scheduled": bool(
                accepts_scheduled_orders and not is_open and status != STATUS_UNLISTED
            ),
        }

    if not is_active:
        return result(STATUS_UNLISTED, "This restaurant is not currently on Zvingo")

    if pause_until is not None:
        resume = pause_until
        if resume.tzinfo is None:
            resume = resume.replace(tzinfo=dt_timezone.utc)
        if resume > local:
            resume_local = resume.astimezone(resolve_timezone(tz_name))
            return result(
                STATUS_PAUSED,
                f"Paused until {resume_local.strftime('%H:%M')}",
                opens_at=resume_local,
            )

    if is_open_override is False:
        return result(
            STATUS_CLOSED_BY_MERCHANT,
            "Temporarily closed",
            opens_at=next_opening(week, local),
        )

    if is_open_override is True:
        window = current_window(week, local)
        return result(
            STATUS_OPEN, "Open now", closes_at=window[1] if window else None
        )

    if not week:
        # No schedule configured: legacy restaurants stay orderable rather than
        # silently disappearing from the marketplace.
        return result(STATUS_OPEN, "Open now")

    window = current_window(week, local)
    if window:
        return result(STATUS_OPEN, "Open now", closes_at=window[1])

    opens_at = next_opening(week, local)
    if opens_at is None:
        return result(STATUS_CLOSED, "Closed")
    same_day = opens_at.date() == local.date()
    when = (
        f"Opens {opens_at.strftime('%H:%M')}"
        if same_day
        else f"Opens {DAY_LABELS[opens_at.weekday()]} {opens_at.strftime('%H:%M')}"
    )
    return result(STATUS_CLOSED, when, opens_at=opens_at)


def availability_of(restaurant, now: Optional[datetime] = None) -> dict:
    """Availability for a restaurant document, tolerant of legacy documents."""
    return compute_availability(
        is_active=getattr(restaurant, "is_active", True),
        hours=getattr(restaurant, "hours", None),
        tz_name=getattr(restaurant, "timezone", DEFAULT_TIMEZONE),
        is_open_override=getattr(restaurant, "is_open_override", None),
        pause_until=getattr(restaurant, "pause_until", None),
        accepts_scheduled_orders=getattr(restaurant, "accepts_scheduled_orders", True),
        now=now,
    )
