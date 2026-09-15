"""Canonical time helpers.

``datetime.utcnow()`` is deprecated (and was always a trap: it returns a naive
datetime that *claims* nothing about its zone). Nothing in this codebase calls
it any more — every module goes through the helpers here.

Two representations exist on purpose:

* :func:`utc_now` returns **naive** UTC. This is the storage representation.
  Every datetime already persisted in MongoDB is naive, and comparing a naive
  datetime with an aware one raises ``TypeError``, so documents, Beanie
  queries and anything derived from them must keep using it.
* :func:`utc_now_aware` returns **timezone-aware** UTC. Use it for anything
  that leaves the process — JWT claims, API responses, log fields, signed
  payloads — where an explicit offset is what makes the value unambiguous.

:func:`ensure_utc` and :func:`as_naive_utc` convert between the two so a value
crossing the boundary never has to be guessed about.
"""

from datetime import UTC, datetime, timedelta
from typing import Optional


def utc_now() -> datetime:
    """Naive UTC — the storage representation used by every Mongo document."""
    return datetime.now(UTC).replace(tzinfo=None)


def utc_now_aware() -> datetime:
    """Timezone-aware UTC — the wire representation.

    Prefer this for tokens, API payloads and logs: it serialises with an
    explicit ``+00:00`` so no consumer has to assume a zone.
    """
    return datetime.now(UTC)


def utc_from_timestamp(timestamp: float) -> datetime:
    """Convert a Unix timestamp to naive UTC."""
    return datetime.fromtimestamp(timestamp, UTC).replace(tzinfo=None)


def utc_from_timestamp_aware(timestamp: float) -> datetime:
    """Convert a Unix timestamp to timezone-aware UTC."""
    return datetime.fromtimestamp(timestamp, UTC)


def ensure_utc(value: Optional[datetime]) -> Optional[datetime]:
    """Return ``value`` as aware UTC, treating a naive input as UTC.

    Naive inputs are exactly what comes back out of MongoDB, so this is the
    safe way to compare a stored timestamp against :func:`utc_now_aware`.
    """
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def as_naive_utc(value: Optional[datetime]) -> Optional[datetime]:
    """Return ``value`` as naive UTC, ready to be stored on a document."""
    aware = ensure_utc(value)
    return None if aware is None else aware.replace(tzinfo=None)


def epoch_seconds(value: Optional[datetime] = None) -> int:
    """Whole seconds since the epoch for ``value`` (default: now).

    Naive values are interpreted as UTC, which is the invariant every stored
    datetime in this system satisfies.
    """
    aware = ensure_utc(value) if value is not None else utc_now_aware()
    return int(aware.timestamp())


def seconds_until(value: datetime) -> float:
    """Seconds from now until ``value`` (negative once it is in the past)."""
    return (ensure_utc(value) - utc_now_aware()).total_seconds()


def utc_in(**delta: float) -> datetime:
    """Aware UTC a ``timedelta`` from now, e.g. ``utc_in(minutes=15)``."""
    return utc_now_aware() + timedelta(**delta)
