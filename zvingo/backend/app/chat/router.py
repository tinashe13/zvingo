from fastapi import APIRouter, Depends, HTTPException
from typing import List
import redis.asyncio as aioredis
from app.config import settings
from app.chat.models import ChatMessage
from app.chat.schemas import ChatMessageCreate, ChatMessageResponse
from app.order.models import Order
from app.auth.router import get_current_user
from app.auth.models import User

router = APIRouter()


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
    uid = str(user.id)
    if uid in (order.consumer_id, order.driver_id):
        return True
    try:
        from app.catalog.models import Restaurant
        restaurant = await Restaurant.get(order.merchant_id)
        if restaurant and restaurant.merchant_id == uid:
            return True
    except Exception:
        pass
    return False


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
