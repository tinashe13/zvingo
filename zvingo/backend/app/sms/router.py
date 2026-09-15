"""Outbound SMS API.

This used to initialise Africa's Talking directly from `AT_USERNAME` /
`AT_API_KEY` environment variables and fall back to "mock" whenever a key was
missing — including in production, where the OTP would then be silently
swallowed. It also let *any* authenticated user send an SMS to *any* number,
which is a metered, billable open relay.

Both are fixed here:

* delivery goes through :mod:`app.sms.gateway`, whose mock/production split is
  driven by `SMS_MOCK_MODE` and refuses to run mock in production;
* the endpoint requires an admin, because ordinary users never need to send
  free-form SMS — the OTP and order flows call the gateway internally.
"""

import structlog
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app.auth.models import User
from app.auth.router import get_current_admin
from app.config import settings
from app.sms.gateway import sms_gateway

logger = structlog.get_logger()
router = APIRouter()

#: One SMS segment is 160 GSM-7 characters; four segments is a sane ceiling for
#: an operational message and keeps a typo from costing a fortune.
MAX_MESSAGE_LENGTH = 640


class SMSRequest(BaseModel):
    to: str = Field(min_length=6, max_length=20)
    message: str = Field(min_length=1, max_length=MAX_MESSAGE_LENGTH)

    @field_validator("to")
    @classmethod
    def _e164(cls, value: str) -> str:
        cleaned = value.strip().replace(" ", "")
        if not cleaned.startswith("+") or not cleaned[1:].isdigit():
            raise ValueError("Phone number must be E.164, e.g. +263771234567")
        return cleaned


@router.post("/send")
async def send_sms(
    request: SMSRequest, current_admin: User = Depends(get_current_admin)
):
    """Send an operational SMS. Admin-only — this endpoint costs real money."""
    try:
        delivered = await sms_gateway.send_sms(request.to, request.message)
    except Exception as e:
        logger.error("SMS send failed", error=str(e))
        raise HTTPException(status_code=502, detail="SMS gateway unavailable")

    provider = "mock" if sms_gateway.mock_mode else "africastalking"
    if not delivered:
        logger.warning("SMS not delivered", to=request.to, provider=provider)
        raise HTTPException(status_code=502, detail="SMS gateway rejected the message")

    logger.info(
        "SMS sent",
        to=request.to,
        provider=provider,
        admin_id=str(current_admin.id),
    )
    return {
        "status": "success",
        "provider": provider,
        "environment": settings.ENVIRONMENT,
    }
