"""Consumer ↔ driver/merchant in-app messaging tied to an order."""

from typing import Optional
from datetime import datetime
from app.time_utils import utc_now
from beanie import Document, Indexed
from pydantic import Field


class ChatMessage(Document):
    """A single chat message within an order's conversation."""

    order_id: Indexed(str)
    sender_id: Indexed(str)  # user id
    sender_role: str = "consumer"  # consumer | driver | merchant
    text: str
    created_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "chat_messages"
        indexes = [
            [("order_id", 1), ("created_at", 1)],
        ]
