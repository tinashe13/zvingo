"""Reading and applying notification preferences.

Every push goes through :func:`should_notify`. When the preferences collection
is unavailable — the document model not registered, MongoDB unreachable — the
answer is "yes, notify": losing an order update is worse than honouring a
setting we could not read, and the failure is logged rather than swallowed.
"""

from datetime import timedelta
from typing import Optional

import structlog

from app.catalog.hours import DEFAULT_TIMEZONE, InvalidHours, parse_hhmm, to_local
from app.notification.models import (
    CATEGORIES,
    URGENT_CATEGORIES,
    NotificationPreference,
)
from app.time_utils import utc_now

logger = structlog.get_logger()

DEFAULTS = {
    "push_enabled": True,
    "sms_enabled": True,
    "order_updates": True,
    "chat_messages": True,
    "driver_offers": True,
    "promotions": True,
    "quiet_hours_start": None,
    "quiet_hours_end": None,
    "timezone": DEFAULT_TIMEZONE,
}


def defaults(user_id: str) -> dict:
    return {"user_id": user_id, **DEFAULTS}


def to_dict(preference: NotificationPreference) -> dict:
    return {
        "user_id": preference.user_id,
        "push_enabled": preference.push_enabled,
        "sms_enabled": preference.sms_enabled,
        "order_updates": preference.order_updates,
        "chat_messages": preference.chat_messages,
        "driver_offers": preference.driver_offers,
        "promotions": preference.promotions,
        "quiet_hours_start": preference.quiet_hours_start,
        "quiet_hours_end": preference.quiet_hours_end,
        "timezone": preference.timezone,
    }


async def get_preferences(user_id: str) -> dict:
    """This user's preferences, or the permissive defaults."""
    try:
        preference = await NotificationPreference.find_one({"user_id": user_id})
    except Exception as e:
        logger.warning(
            "Notification preferences unavailable", user_id=user_id, error=str(e)
        )
        return defaults(user_id)
    return to_dict(preference) if preference else defaults(user_id)


async def set_preferences(user_id: str, changes: dict) -> dict:
    """Upsert a user's preferences and return the stored result."""
    preference = await NotificationPreference.find_one({"user_id": user_id})
    if preference is None:
        preference = NotificationPreference(user_id=user_id)
    for field, value in changes.items():
        if field in DEFAULTS:
            setattr(preference, field, value)
    preference.updated_at = utc_now()
    await preference.save()
    return to_dict(preference)


def in_quiet_hours(preference: dict, now=None) -> bool:
    """True when the caller's local time falls inside their quiet window."""
    start, end = preference.get("quiet_hours_start"), preference.get("quiet_hours_end")
    if not start or not end:
        return False
    try:
        start_minute, end_minute = parse_hhmm(start), parse_hhmm(end)
    except InvalidHours:
        return False
    local = to_local(now or utc_now(), preference.get("timezone") or DEFAULT_TIMEZONE)
    minute = local.hour * 60 + local.minute
    if end_minute <= start_minute:  # window spans midnight
        return minute >= start_minute or minute < end_minute
    return start_minute <= minute < end_minute


async def should_notify(user_id: str, category: str, channel: str = "push") -> bool:
    """Whether a notification of `category` may be delivered to `user_id`.

    `channel` is "push" or "sms". Unknown categories are always allowed, so a
    new notification type is never silently dropped before anyone adds a
    preference for it.
    """
    if category not in CATEGORIES:
        return True
    preference = await get_preferences(user_id)
    if channel == "push" and not preference["push_enabled"]:
        return False
    if channel == "sms" and not preference["sms_enabled"]:
        return False
    if not preference.get(category, True):
        return False
    if category not in URGENT_CATEGORIES and in_quiet_hours(preference):
        return False
    return True
