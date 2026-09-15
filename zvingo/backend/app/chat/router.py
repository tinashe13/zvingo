import asyncio
import json
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sse_starlette.sse import EventSourceResponse
from typing import Annotated, List, Optional
import redis.asyncio as aioredis
import structlog
from app.config import settings
from app.chat.models import ChatMessage
from app.chat.schemas import ChatMessageCreate, ChatMessageResponse, ChatReadReceipt
from app.order.models import Order
from app.order.access import can_access_order
from app.order.state_machine import OrderState
from app.auth.router import get_current_user, get_current_user_flexible
from app.auth.models import User

router = APIRouter()
logger = structlog.get_logger()

KEEPALIVE_INTERVAL = 15  # seconds between pings on an idle chat stream

DEFAULT_PAGE_SIZE = 50
MAX_PAGE_SIZE = 200

#: A finished order's thread stays readable forever but stops accepting new
#: messages — nobody should be able to message a driver about a delivery that
#: ended three weeks ago.
CLOSED_STATES = (OrderState.DELIVERED, OrderState.CANCELLED)


def _to_response(message: ChatMessage) -> ChatMessageResponse:
    return ChatMessageResponse(
        id=str(message.id),
        order_id=message.order_id,
        sender_id=message.sender_id,
        sender_role=message.sender_role,
        text=message.text,
        read_by=list(getattr(message, "read_by", None) or []),
        created_at=message.created_at,
    )


async def _can_participate(order: Order, user: User) -> bool:
    """True if the user is the consumer, assigned driver, or owning merchant."""
    return await can_access_order(order, user)


async def _load_order(order_id: str, user: User) -> Order:
    """Fetch an order and assert the caller is one of its three participants."""
    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if not await _can_participate(order, user):
        raise HTTPException(status_code=403, detail="Not a participant in this order")
    return order


def _is_closed(order: Order) -> bool:
    state = getattr(order, "state", None)
    if state is None:
        return False
    return state in CLOSED_STATES


async def _publish(order_id: str, event: str, payload: str) -> None:
    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        await r.publish(f"chat_{order_id}", payload)
    except Exception as e:  # pragma: no cover - the message is already stored
        logger.warning("Chat publish failed", order_id=order_id, event=event, error=str(e))
    finally:
        await r.close()


@router.post("/orders/{order_id}/messages", response_model=ChatMessageResponse)
async def send_message(
    order_id: str,
    message_in: ChatMessageCreate,
    current_user: User = Depends(get_current_user),
):
    """Post a message into an order's thread.

    Allowed only for the order's participants, and only while the order is
    still live.
    """
    order = await _load_order(order_id, current_user)
    if _is_closed(order):
        raise HTTPException(
            status_code=409,
            detail="This order is finished — its chat is read-only",
        )

    message = ChatMessage(
        order_id=order_id,
        sender_id=str(current_user.id),
        sender_role=current_user.role,
        text=message_in.text.strip(),
        read_by=[str(current_user.id)],
    )
    await message.insert()

    # Publish to Redis so SSE subscribers (and future WebSocket) get it live.
    await _publish(order_id, "message", _to_response(message).model_dump_json())

    return _to_response(message)


@router.get("/orders/{order_id}/messages", response_model=List[ChatMessageResponse])
async def list_messages(
    order_id: str,
    current_user: User = Depends(get_current_user),
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
):
    """An order's messages, oldest first. Paginated — a thread can be long."""
    await _load_order(order_id, current_user)

    messages = await (
        ChatMessage.find(ChatMessage.order_id == order_id)
        .sort("created_at")
        .skip(offset)
        .limit(limit)
        .to_list()
    )
    return [_to_response(m) for m in messages]


@router.get("/orders/{order_id}/messages/unread", response_model=ChatReadReceipt)
async def unread_count(
    order_id: str, current_user: User = Depends(get_current_user)
):
    """How many messages in this thread the caller has not read yet."""
    await _load_order(order_id, current_user)
    user_id = str(current_user.id)
    unread = await ChatMessage.find(
        {
            "order_id": order_id,
            "sender_id": {"$ne": user_id},
            "read_by": {"$ne": user_id},
        }
    ).count()
    return ChatReadReceipt(order_id=order_id, read_count=0, unread_count=unread)


@router.post("/orders/{order_id}/messages/read", response_model=ChatReadReceipt)
async def mark_read(order_id: str, current_user: User = Depends(get_current_user)):
    """Mark every message in the thread as read by the caller.

    Idempotent: `$addToSet` means calling it twice does not double-count, and
    it never touches messages the caller sent.
    """
    await _load_order(order_id, current_user)
    user_id = str(current_user.id)

    result = await ChatMessage.find(
        {
            "order_id": order_id,
            "sender_id": {"$ne": user_id},
            "read_by": {"$ne": user_id},
        }
    ).update({"$addToSet": {"read_by": user_id}})

    updated = int(getattr(result, "modified_count", 0) or 0)
    if updated:
        await _publish(
            order_id,
            "read",
            json.dumps({"event": "read", "order_id": order_id, "reader_id": user_id}),
        )
    return ChatReadReceipt(order_id=order_id, read_count=updated, unread_count=0)


async def _stream(request: Request, order_id: str, current_user: User):
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
    return await _stream(request, order_id, current_user)


@router.get("/orders/{order_id}/messages/stream")
async def stream_messages_alias(
    request: Request,
    order_id: str,
    current_user: User = Depends(get_current_user_flexible),
):
    """Alias of `/orders/{id}/stream` that sits under the messages collection."""
    return await _stream(request, order_id, current_user)
