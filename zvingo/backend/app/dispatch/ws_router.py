"""
WebSocket pub/sub endpoint for the driver app.

The driver acts as BOTH:
  - Subscriber: receives offers and order updates pushed by the backend
  - Publisher:  sends location updates, accept/decline events to the backend

All real-time driver communication is funnelled through a single WS connection
at  /ws/driver/{driver_id}  instead of the old SSE + multiple HTTP calls.

Protocol (JSON messages in both directions):
    Server → Driver  {"type": "offer",         ...offer_payload}
                     {"type": "order_update",   "order_id": ..., "state": ...}
                     {"type": "ping"}
    Driver → Server  {"type": "location_update","lat":..., "lng":..., "status":"ONLINE"}
                     {"type": "accept_offer",   "order_id": ...}
                     {"type": "decline_offer",  "order_id": ...}
                     {"type": "status_change",  "status": "ONLINE"|"OFFLINE"}
"""

import asyncio
import json
from datetime import datetime
from app.time_utils import utc_now

import redis.asyncio as aioredis
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

from app.auth.models import User
from app.auth.ws import authenticate_ws
from app.config import settings
from app.dispatch.schemas import DriverLocationUpdate
from app.dispatch.service import dispatch_service
from app.order.state_machine import InvalidStateTransition, OrderConflict, OrderState
import structlog

router = APIRouter()
logger = structlog.get_logger()

PING_INTERVAL = 20  # seconds between server-initiated pings


def _authenticate_ws(websocket: WebSocket) -> str | None:
    """Extract and verify the JWT from a WS connection.

    Accepts the token either as a `?token=` query parameter or an
    `Authorization: Bearer` header. Returns the authenticated user id,
    or None if the token is missing/invalid.
    """
    return authenticate_ws(websocket)


async def _load_active_driver(user_id: str):
    """The driver's account when it exists and is still active, else None."""
    try:
        user = await User.get(user_id)
    except Exception as e:
        logger.warning("Driver lookup failed on WS handshake", user_id=user_id, error=str(e))
        return None
    if user is None or not getattr(user, "is_active", False):
        return None
    return user


async def _send_error(websocket, code: str, order_id: str, message: str) -> None:
    """Tell the driver an action of theirs was refused, and why."""
    try:
        await websocket.send_text(
            json.dumps(
                {"type": "error", "code": code, "order_id": order_id, "message": message}
            )
        )
    except Exception:
        pass


@router.websocket("/ws/driver/{driver_id}")
async def driver_ws(websocket: WebSocket, driver_id: str):
    """
    Bidirectional WebSocket channel for a single driver.

    Requires a valid JWT (query param `token` or Authorization header)
    whose subject matches the driver_id in the path.

    Subscribes to Redis channel `driver_{driver_id}` and forwards any
    published messages (offers, order updates) to the driver.
    Incoming driver messages are dispatched to the appropriate service.
    """
    # The driver is whoever the JWT says it is. The `driver_id` in the path is
    # only ever a claim by the client: it is compared against the token and the
    # connection is refused on any disagreement, so it can never be used to
    # subscribe to, act on, or impersonate another driver's channel.
    authenticated_user_id = _authenticate_ws(websocket)
    if authenticated_user_id is None or authenticated_user_id != driver_id:
        # 1008 = policy violation (unauthenticated / not the driver's own channel)
        logger.warning(
            "Driver WebSocket rejected: auth failure",
            driver_id=driver_id,
            authenticated_user_id=authenticated_user_id,
        )
        await websocket.close(code=1008)
        return

    # A token stays valid for days, so also confirm the account still exists and
    # is active — a suspended driver must stop receiving offers immediately.
    user = await _load_active_driver(authenticated_user_id)
    if user is None:
        logger.warning(
            "Driver WebSocket rejected: unknown or inactive account",
            driver_id=driver_id,
        )
        await websocket.close(code=1008)
        return

    await websocket.accept()
    logger.info("Driver WebSocket connected", driver_id=driver_id)

    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    pubsub = r.pubsub()
    await pubsub.subscribe(f"driver_{driver_id}")

    # Flush any pending offer that was published during the connection window
    # (i.e., after the driver was marked ONLINE but before the WS subscribed).
    pending_offer = await r.getdel(f"driver_pending_offer_{driver_id}")
    if pending_offer:
        await websocket.send_text(pending_offer)
        logger.info("Flushed pending offer on connect", driver_id=driver_id)

    # Task 1: forward Redis pub/sub messages → WebSocket (driver as subscriber)
    async def redis_to_ws():
        try:
            while True:
                if websocket.client_state != WebSocketState.CONNECTED:
                    break
                message = await pubsub.get_message(
                    ignore_subscribe_messages=True, timeout=1.0
                )
                if message and message["type"] == "message":
                    await websocket.send_text(message["data"])
                    logger.debug(
                        "WS forwarded Redis message",
                        driver_id=driver_id,
                        preview=str(message["data"])[:60],
                    )
                await asyncio.sleep(0)  # yield to event loop
        except Exception as e:
            logger.error("redis_to_ws error", driver_id=driver_id, error=str(e))

    # Task 2: periodic ping to keep connection alive
    async def ping_loop():
        try:
            while True:
                await asyncio.sleep(PING_INTERVAL)
                if websocket.client_state != WebSocketState.CONNECTED:
                    break
                await websocket.send_text(json.dumps({"type": "ping"}))
        except Exception:
            pass

    # Start background tasks
    redis_task = asyncio.create_task(redis_to_ws())
    ping_task = asyncio.create_task(ping_loop())

    try:
        # Main loop: receive driver-published events (driver as publisher)
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                logger.warning("WS bad JSON from driver", driver_id=driver_id, raw=raw[:80])
                continue

            msg_type = msg.get("type")
            logger.debug("WS received from driver", driver_id=driver_id, type=msg_type)

            if msg_type == "location_update":
                await _handle_location_update(driver_id, msg)

            elif msg_type == "accept_offer":
                order_id = msg.get("order_id")
                if order_id:
                    try:
                        await dispatch_service.accept_offer(driver_id, order_id)
                    except (OrderConflict, InvalidStateTransition) as e:
                        # Another driver won the race, or the order was
                        # cancelled. Tell this driver so their offer card clears
                        # instead of hanging on an order they will never get.
                        logger.info(
                            "Offer could not be accepted",
                            driver_id=driver_id,
                            order_id=order_id,
                            error=str(e),
                        )
                        await _send_error(
                            websocket, "offer_unavailable", order_id, str(e)
                        )

            elif msg_type == "decline_offer":
                order_id = msg.get("order_id")
                if order_id:
                    await dispatch_service.decline_offer(driver_id, order_id)

            elif msg_type == "status_change":
                status = msg.get("status", "OFFLINE")
                await dispatch_service.redis.hset(
                    f"driver:{driver_id}", "status", status
                )
                logger.info("Driver status changed", driver_id=driver_id, status=status)

            elif msg_type == "delivery_action":
                order_id = msg.get("order_id")
                backend_state = msg.get("state")
                if order_id and backend_state:
                    try:
                        from app.order.service import OrderService

                        # `require_driver_id` is the important part: a driver may
                        # only advance the delivery they are actually carrying.
                        # Without it, any authenticated driver could walk any
                        # order they knew the id of through to DELIVERED.
                        await OrderService.transition_state(
                            order_id,
                            OrderState(backend_state),
                            actor_id=driver_id,
                            reason="driver_delivery_action",
                            require_driver_id=driver_id,
                        )
                        logger.info(
                            "Delivery action applied",
                            driver_id=driver_id,
                            order_id=order_id,
                            state=backend_state,
                        )
                    except Exception as e:
                        logger.warning(
                            "Failed to apply delivery action",
                            driver_id=driver_id,
                            order_id=order_id,
                            state=backend_state,
                            error=str(e),
                        )
                        await _send_error(
                            websocket, "delivery_action_rejected", order_id, str(e)
                        )

            elif msg_type == "pong":
                pass  # keepalive ack

            else:
                logger.warning(
                    "WS unknown message type", driver_id=driver_id, type=msg_type
                )

    except WebSocketDisconnect:
        logger.info("Driver WebSocket disconnected", driver_id=driver_id)
    except Exception as e:
        logger.error("Driver WebSocket error", driver_id=driver_id, error=str(e))
    finally:
        redis_task.cancel()
        ping_task.cancel()
        try:
            await pubsub.unsubscribe(f"driver_{driver_id}")
        except Exception:
            pass
        try:
            await r.close()
        except Exception:
            pass
        logger.info("Driver WebSocket cleaned up", driver_id=driver_id)


async def _handle_location_update(driver_id: str, msg: dict):
    """Parse and apply a location_update message from the driver."""
    try:
        lat = float(msg["lat"])
        lng = float(msg["lng"])
        status = msg.get("status", "ONLINE")
        battery = int(msg.get("battery", 0))
        timestamp = utc_now()

        update = DriverLocationUpdate(
            driver_id=driver_id,
            lat=lat,
            lng=lng,
            status=status,
            battery=battery,
            timestamp=timestamp,
        )
        await dispatch_service.update_location(update)
    except (KeyError, ValueError, TypeError) as e:
        logger.warning(
            "WS invalid location_update payload",
            driver_id=driver_id,
            error=str(e),
        )
