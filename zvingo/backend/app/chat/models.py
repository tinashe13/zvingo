"""Consumer ↔ driver/merchant in-app messaging tied to an order."""

from typing import List, Optional
from datetime import datetime
from app.time_utils import utc_now
from beanie import Document, Indexed
from pydantic import Field


class ChatMessage(Document):
    """A single chat message within an order's conversation.

    Read state is stored as the set of user ids that have seen the message.
    A per-message set (rather than a single `is_read` flag) is what makes a
    three-party thread — consumer, driver, merchant — report unread counts
    correctly for each participant.
    """

    order_id: Indexed(str)
    sender_id: Indexed(str)  # user id
    sender_role: str = "consumer"  # consumer | driver | merchant
    text: str
    read_by: List[str] = []
    created_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "chat_messages"
        indexes = [
            # Every read is "this order's messages, oldest first"; every unread
            # count is "this order's messages not sent by me".
            [("order_id", 1), ("created_at", 1)],
            [("order_id", 1), ("sender_id", 1)],
        ]
