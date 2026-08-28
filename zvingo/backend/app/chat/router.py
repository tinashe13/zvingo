import asyncio
import json
from fastapi import APIRouter, Depends, HTTPException, Request
from sse_starlette.sse import EventSourceResponse
from typing import List
import redis.asyncio as aioredis
import structlog
from app.config import settings
from app.chat.models import ChatMessage
from app.chat.schemas import ChatMessageCreate, ChatMessageResponse
from app.order.models import Order
from app.order.access import can_access_order
from app.auth.router import get_current_user, get_current_user_flexible
from app.auth.models import User

router = APIRouter()
logger = structlog.get_logger()

KEEPALIVE_INTERVAL = 15  # seconds between pings on an idle chat stream


def _to_response(message: ChatMessage) -> ChatMessageResponse:
    return ChatMessageResponse(
        id=str(message.id),
        order_id=message.order_id,
        sender_id=message.sender_id,
        sender_role=message.sender_role,
        text=message.text,
        created_at=message.created_at,
    )


async def _can_participate(order: Order, user: User) -> bool:
    """True if the user is the consumer, assigned driver, or owning merchant."""
    return await can_access_order(order, user)


@router.post("/orders/{order_id}/messages", response_model=ChatMessageResponse)
async def send_message(
    order_id: str,
    message_in: ChatMessageCreate,
    current_user: User = Depends(get_current_user),
):
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if not await _can_participate(order, current_user):
        raise HTTPException(status_code=403, detail="Not a participant in this order")

    message = ChatMessage(
        order_id=order_id,
        sender_id=str(current_user.id),
        sender_role=current_user.role,
        text=message_in.text.strip(),
    )
    await message.insert()

    # Publish to Redis so SSE subscribers (and future WebSocket) get it live.
    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        await r.publish(
            f"chat_{order_id}",
            _to_response(message).model_dump_json(),
        )
    finally:
        await r.close()

    return _to_response(message)


@router.get("/orders/{order_id}/messages", response_model=List[ChatMessageResponse])
async def list_messages(
    order_id: str, current_user: User = Depends(get_current_user)
):
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if not await _can_participate(order, current_user):
        raise HTTPException(status_code=403, detail="Not a participant in this order")

    messages = await ChatMessage.find(ChatMessage.order_id == order_id).sort(
        "created_at"
    ).to_list()
    return [_to_response(m) for m in messages]


@router.get("/orders/{order_id}/stream")
async def stream_messages(
    request: Request,
    order_id: str,
    current_user: User = Depends(get_current_user_flexible),
):
    """SSE stream of new chat messages for an order.

    Mirrors the notification SSE: an immediate `connected` event, `message`
    events carrying the same JSON body as `POST /chat/orders/{id}/messages`,
    and a `ping` whenever the stream is idle so proxies keep it open.
    Authenticates from the Authorization header or a `token` query parameter,
    since `EventSource` cannot set headers.
    """
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if not await _can_participate(order, current_user):
        raise HTTPException(status_code=403, detail="Not a participant in this order")

    channel = f"chat_{order_id}"

    async def event_generator():
        r = None
        pubsub = None
        try:
            r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
            pubsub = r.pubsub()
            await pubsub.subscribe(channel)
            logger.info("Chat SSE connected", order_id=order_id)

            yield {"event": "connected", "data": json.dumps({"order_id": order_id})}

            while True:
                if await request.is_disconnected():
                    break
                message = await pubsub.get_message(
                    ignore_subscribe_messages=True, timeout=KEEPALIVE_INTERVAL
                )
                if message is not None and message["type"] == "message":
                    yield {"event": "message", "data": message["data"]}
                else:
                    yield {"event": "ping", "data": "ping"}
        except asyncio.CancelledError:
            logger.info("Chat SSE cancelled", order_id=order_id)
        except Exception as e:
            logger.error("Chat SSE error", order_id=order_id, error=str(e))
            yield {"event": "error", "data": json.dumps({"detail": str(e)})}
        finally:
            if pubsub:
                try:
                    await pubsub.unsubscribe(channel)
                except Exception:
                    pass
            if r:
                try:
                    await r.close()
                except Exception:
                    pass
            logger.info("Chat SSE disconnected", order_id=order_id)

    return EventSourceResponse(event_generator(), ping=None)
