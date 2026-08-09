from datetime import UTC, datetime


def utc_now() -> datetime:
    """Return naive UTC for compatibility with existing MongoDB documents."""
    return datetime.now(UTC).replace(tzinfo=None)


def utc_from_timestamp(timestamp: float) -> datetime:
    """Convert a Unix timestamp to naive UTC."""
    return datetime.fromtimestamp(timestamp, UTC).replace(tzinfo=None)
