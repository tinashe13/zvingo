"""One WebSocket channel for everything a consumer watches on an order.

Tracking used to need three connections: an SSE stream for order status, a
second SSE stream for driver location, and polling for chat. This endpoint
consolidates all of them onto the WebSocket transport the driver app already
uses, so the consumer app opens a single socket per order.

Protocol (server → client):
    {"type": "snapshot",  "state": ..., "driver_id": ..., "driver_lat": ...}
    {"type": "order",     ...}   # order lifecycle events
    {"type": "location",  "lat": ..., "lng": ...}
    {"type": "chat",      ...}   # chat messages on this order
    {"type": "ping"}

Client → server messages are only keepalives (`{"type": "ping"|"pong"}`); the
consumer acts on the order through the ordinary REST endpoints.
"""

import asyncio
import json
from typing import Optional, Set

import redis.asyncio as aioredis
import structlog
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

from app.auth.models import User
from app.auth.ws import authenticate_ws
from app.config import settings
from app.order.access import can_access_order
from app.order.models import Order

router = APIRouter()
logger = structlog.get_logger()

PING_INTERVAL = 20  # seconds between server-initiated pings

# Redis channel prefix → the `type` tag put on the forwarded message.
CHANNEL_KINDS = (
    ("driver_loc_", "location"),
    ("consumer_", "order"),
    ("chat_", "chat"),
)


def channel_kind(channel: str) -> str:
    for prefix, kind in CHANNEL_KINDS:
        if channel.startswith(prefix):
            return kind
    return "event"


def tag_message(channel: str, data: str) -> str:
    """Wrap a raw Redis payload with the channel's message type."""
    kind = channel_kind(channel)
    try:
        payload = json.loads(data)
        if not isinstance(payload, dict):
            payload = {"data": payload}
    except (json.JSONDecodeError, TypeError):
        payload = {"data": data}
    payload["type"] = kind
    return json.dumps(payload)


async def driver_position(driver_id: str) -> tuple:
    """Last known (lat, lng) for a driver from the Redis geo index."""
    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        positions = await r.geopos("driver_locations", driver_id)
        if positions and positions[0]:
            lng, lat = positions[0]
            return float(lat), float(lng)
        return None, None
    except Exception as e:
        logger.warning("Failed to read driver position", driver_id=driver_id, error=str(e))
        return None, None
    finally:
        await r.close()


async def _snapshot(order: Order) -> str:
    """The initial state payload so a reconnecting client renders immediately."""
    driver_lat = driver_lng = None
    if order.driver_id:
        driver_lat, driver_lng = await driver_position(order.driver_id)
    state = getattr(order.state, "value", order.state)
    return json.dumps(
        {
            "type": "snapshot",
            "order_id": str(order.id),
            "state": str(state),
            "driver_id": order.driver_id,
            "driver_lat": driver_lat,
            "driver_lng": driver_lng,
            "group_id": order.group_id,
        }
    )


async def forward_messages(websocket, pubsub, channels: Set[str], order_id: str) -> None:
    """Forward Redis messages to the socket until it closes.

    When an order event names a driver, the socket starts following that
    driver's location channel too — a consumer connects before dispatch has
    assigned anyone, so the subscription cannot be decided up front.
    """
    try:
        while True:
            if websocket.client_state != WebSocketState.CONNECTED:
                break
            message = await pubsub.get_message(
                ignore_subscribe_messages=True, timeout=1.0
            )
            if message and message["type"] == "message":
                channel = message["channel"]
                data = message["data"]
                await websocket.send_text(tag_message(channel, data))

                driver_id = _driver_id_from(data)
                if driver_id:
                    driver_channel = f"driver_loc_{driver_id}"
                    if driver_channel not in channels:
                        channels.add(driver_channel)
                        await pubsub.subscribe(driver_channel)
                        logger.info(
                            "Tracking WS following driver",
                            order_id=order_id,
                            driver_id=driver_id,
                        )
            await asyncio.sleep(0)  # yield to the event loop
    except Exception as e:
        logger.error("Tracking WS forward error", order_id=order_id, error=str(e))


async def ping_loop(websocket) -> None:
    """Keep the connection alive through idle proxies."""
    try:
        while True:
            await asyncio.sleep(PING_INTERVAL)
            if websocket.client_state != WebSocketState.CONNECTED:
                break
            await websocket.send_text(json.dumps({"type": "ping"}))
    except Exception:
        pass


@router.websocket("/ws/orders/{order_id}/track")
async def track_order(websocket: WebSocket, order_id: str):
    """Live tracking for one order, for any participant in it.

    Requires a valid JWT (`?token=` or an Authorization header) belonging to
    the order's consumer, assigned driver, or owning merchant.
    """
    user_id = authenticate_ws(websocket)
    if user_id is None:
        await websocket.close(code=1008)
        return

    user: Optional[User] = await User.get(user_id)
    if user is None or not user.is_active:
        logger.warning("Tracking WS rejected: unknown or inactive user", user_id=user_id)
        await websocket.close(code=1008)
        return

    try:
        order = await Order.get(order_id)
    except Exception as e:
        # A malformed id must close the socket cleanly rather than raise out of
        # the handler, which would surface as an opaque connection error.
        logger.warning("Tracking WS rejected: unreadable order id", order_id=order_id, error=str(e))
        order = None
    if order is None:
        await websocket.close(code=1008)
        return

    if not await can_access_order(order, user):
        logger.warning(
            "Tracking WS rejected: not a participant",
            user_id=user_id,
            order_id=order_id,
        )
        await websocket.close(code=1008)
        return

    await websocket.accept()
    logger.info("Tracking WS connected", order_id=order_id, user_id=user_id)

    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    pubsub = r.pubsub()

    channels: Set[str] = {f"consumer_{order.consumer_id}", f"chat_{order_id}"}
    if order.driver_id:
        channels.add(f"driver_loc_{order.driver_id}")
    for channel in sorted(channels):
        await pubsub.subscribe(channel)

    await websocket.send_text(await _snapshot(order))

    redis_task = asyncio.create_task(
        forward_messages(websocket, pubsub, channels, order_id)
    )
    ping_task = asyncio.create_task(ping_loop(websocket))

    try:
        while True:
            # The consumer only sends keepalives; everything else is REST.
            await websocket.receive_text()
    except WebSocketDisconnect:
        logger.info("Tracking WS disconnected", order_id=order_id)
    except Exception as e:
        logger.error("Tracking WS error", order_id=order_id, error=str(e))
    finally:
        redis_task.cancel()
        ping_task.cancel()
        for channel in sorted(channels):
            try:
                await pubsub.unsubscribe(channel)
            except Exception:
                pass
        try:
            await r.close()
        except Exception:
            pass
        logger.info("Tracking WS cleaned up", order_id=order_id)


def _driver_id_from(data: str) -> Optional[str]:
    """Extract a driver id from an order event payload, if it carries one."""
    try:
        payload = json.loads(data)
    except (json.JSONDecodeError, TypeError):
        return None
    if not isinstance(payload, dict):
        return None
    driver_id = payload.get("driver_id")
    return driver_id if isinstance(driver_id, str) and driver_id else None
