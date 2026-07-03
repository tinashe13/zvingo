import asyncio
import json
from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from app.config import settings
import redis.asyncio as redis
import structlog

router = APIRouter()
logger = structlog.get_logger()

KEEPALIVE_INTERVAL = 15  # seconds between pings


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
