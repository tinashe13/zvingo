from pydantic import BaseModel, Field, field_validator
from typing import List, Optional
from datetime import datetime

#: Long enough for a real message, short enough that the chat cannot be used
#: as free storage or to flood a driver's screen mid-delivery.
MAX_MESSAGE_LENGTH = 1000


class ChatMessageCreate(BaseModel):
    text: str = Field(min_length=1, max_length=MAX_MESSAGE_LENGTH)

    @field_validator("text")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Message cannot be empty")
        return stripped


class ChatMessageResponse(BaseModel):
    id: str
    order_id: str
    sender_id: str
    sender_role: str
    text: str
    read_by: List[str] = []
    created_at: datetime


class ChatReadReceipt(BaseModel):
    order_id: str
    read_count: int
    unread_count: int = 0
