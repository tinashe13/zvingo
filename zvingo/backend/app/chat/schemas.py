from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class ChatMessageCreate(BaseModel):
    text: str


class ChatMessageResponse(BaseModel):
    id: str
    order_id: str
    sender_id: str
    sender_role: str
    text: str
    created_at: datetime
