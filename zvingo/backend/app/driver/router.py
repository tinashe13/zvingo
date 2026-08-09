from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from app.time_utils import utc_now
from app.auth.router import get_current_user
from app.auth.models import User, Location
from app.dispatch.service import dispatch_service
from app.dispatch.schemas import DriverLocationUpdate

router = APIRouter()

class DashSessionRequest(BaseModel):
    active: bool
    lat: Optional[float] = None
    lng: Optional[float] = None
    radius: Optional[int] = 10

@router.post("/dash/session")
async def update_dash_session(req: DashSessionRequest, current_user: User = Depends(get_current_user)):
    driver_id = str(current_user.id)
    current_user.is_dashing = req.active

    if req.active and req.lat is not None and req.lng is not None:
        current_user.current_location = Location(coordinates=[req.lng, req.lat])
        current_user.dash_radius = req.radius or 10

        # Sync into Redis geo index so the dispatcher can find this driver
        await dispatch_service.update_location(DriverLocationUpdate(
            driver_id=driver_id,
            lat=req.lat,
            lng=req.lng,
            status="ONLINE",
            timestamp=utc_now()
        ))
    elif not req.active:
        # Mark driver OFFLINE in Redis so they are excluded from dispatch
        await dispatch_service.redis.hset(f"driver:{driver_id}", "status", "OFFLINE")

    await current_user.save()
    return {"status": "updated", "is_dashing": current_user.is_dashing}
