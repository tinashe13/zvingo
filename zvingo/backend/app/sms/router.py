import africastalking
import os
import structlog
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from app.auth.router import get_current_user
from app.auth.models import User

logger = structlog.get_logger()
router = APIRouter()

class SMSRequest(BaseModel):
    to: str
    message: str

# Initialize Africa's Talking
username = os.getenv("AT_USERNAME", "sandbox")
api_key = os.getenv("AT_API_KEY", "")

if api_key:
    africastalking.initialize(username, api_key)
    sms = africastalking.SMS
else:
    sms = None
    logger.warning("Africa's Talking API Key not found. SMS will be mocked.")

@router.post("/send")
async def send_sms(request: SMSRequest, current_user: User = Depends(get_current_user)):
    # Auth required: without it this endpoint is an open SMS relay
    try:
        if sms:
            response = sms.send(request.message, [request.to])
            logger.info("SMS Sent via AT", response=response)
            return {"status": "success", "provider": "africastalking", "data": response}
        else:
            logger.info("SMS Mock Sent", to=request.to, message=request.message)
            return {"status": "success", "provider": "mock"}
    except Exception as e:
        logger.error("SMS Send Failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))
