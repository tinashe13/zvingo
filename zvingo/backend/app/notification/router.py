import asyncio
import json
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, field_validator
from sse_starlette.sse import EventSourceResponse
from app.auth.models import User
from app.auth.router import get_current_user
from app.catalog.hours import InvalidHours, format_hhmm, parse_hhmm
from app.config import settings
from app.notification.fcm import fcm_status
from app.notification.preferences import get_preferences, set_preferences
import redis.asyncio as redis
import structlog

router = APIRouter()
logger = structlog.get_logger()

KEEPALIVE_INTERVAL = 15  # seconds between pings


class NotificationPreferenceUpdate(BaseModel):
    """Partial update — only the fields present are changed."""

    push_enabled: Optional[bool] = None
    sms_enabled: Optional[bool] = None
    order_updates: Optional[bool] = None
    chat_messages: Optional[bool] = None
    driver_offers: Optional[bool] = None
    promotions: Optional[bool] = None
    quiet_hours_start: Optional[str] = None
    quiet_hours_end: Optional[str] = None
    timezone: Optional[str] = None

    @field_validator("quiet_hours_start", "quiet_hours_end")
    @classmethod
    def _valid_time(cls, value: Optional[str]) -> Optional[str]:
        if value in (None, ""):
            return None
        try:
            return format_hhmm(parse_hhmm(value))
        except InvalidHours as e:
            raise ValueError(str(e)) from None


@router.get("/preferences")
async def read_preferences(current_user: User = Depends(get_current_user)):
    """The caller's notification settings (defaults when never customised)."""
    return await get_preferences(str(current_user.id))


@router.put("/preferences")
async def update_preferences(
    update: NotificationPreferenceUpdate,
    current_user: User = Depends(get_current_user),
):
    """Change the caller's notification settings. Only sent fields are applied."""
    changes = update.model_dump(exclude_unset=True)
    if not changes:
        return await get_preferences(str(current_user.id))
    try:
        return await set_preferences(str(current_user.id), changes)
    except Exception as e:
        logger.error(
            "Failed to save notification preferences",
            user_id=str(current_user.id),
            error=str(e),
        )
        raise HTTPException(
            status_code=503,
            detail="Notification settings are temporarily unavailable",
        )


@router.get("/push/status")
async def push_status(current_user: User = Depends(get_current_user)):
    """Whether push delivery is actually configured on this deployment.

    Lets a client explain "push is off on the server" instead of leaving the
    user waiting for notifications that will never arrive.
    """
    return fcm_status()


@router.get("/events/{channel_id}")
async def message_stream(request: Request, channel_id: str):
    """
    SSE Endpoint for real-time updates.
    channel_id: usually merchant_id or driver_id
    """
    async def event_generator():
        r = None
        pubsub = None
        try:
            r = redis.from_url(settings.REDIS_URL, decode_responses=True)
            pubsub = r.pubsub()
            await pubsub.subscribe(channel_id)

            logger.info("SSE Connected", channel=channel_id)

            # Send immediate heartbeat to confirm connection
            yield {
                "event": "connected",
                "data": json.dumps({
                    "event": "connected",
                    "data": f"Connected to {channel_id}"
                })
            }

            while True:
                if await request.is_disconnected():
                    logger.info("Client disconnected", channel=channel_id)
                    break

                # Poll for messages with a short timeout so we can send keepalives
                message = await pubsub.get_message(
                    ignore_subscribe_messages=True,
                    timeout=KEEPALIVE_INTERVAL,
                )

                if message is not None and message["type"] == "message":
                    logger.debug("SSE Message", channel=channel_id, data=str(message["data"])[:50])
                    yield {
                        "event": "message",
                        "data": message["data"]
                    }
                else:
                    # No message within timeout — send keepalive ping
                    yield {
                        "event": "ping",
                        "data": "ping"
                    }

        except asyncio.CancelledError:
            logger.info("SSE Cancelled", channel=channel_id)
        except Exception as e:
            logger.error("SSE Error", channel=channel_id, error=str(e), error_type=type(e).__name__)
            yield {
                "event": "error",
                "data": json.dumps({
                    "event": "error",
                    "data": f"Error: {str(e)}"
                })
            }
        finally:
            if pubsub:
                try:
                    await pubsub.unsubscribe(channel_id)
                except Exception as e:
                    logger.warn("Error unsubscribing", error=str(e))
            if r:
                try:
                    await r.close()
                except Exception as e:
                    logger.warn("Error closing Redis", error=str(e))
            logger.info("SSE Disconnected", channel=channel_id)

    return EventSourceResponse(event_generator(), ping=None)
