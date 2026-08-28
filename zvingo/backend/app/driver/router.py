from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import List, Optional
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


class ScheduleDay(BaseModel):
    day: int  # 0=Mon … 6=Sun
    slots: List[int] = []  # 0=Morning, 1=Afternoon, 2=Evening


class ScheduleUpdate(BaseModel):
    days: List[ScheduleDay]


class VehicleUpdate(BaseModel):
    make: Optional[str] = None
    model: Optional[str] = None
    color: Optional[str] = None
    plate: Optional[str] = None


@router.get("/schedule")
async def get_schedule(current_user: User = Depends(get_current_user)):
    """Return the driver's saved weekly availability."""
    return {"days": current_user.schedule}


@router.put("/schedule")
async def save_schedule(
    req: ScheduleUpdate, current_user: User = Depends(get_current_user)
):
    """Persist the driver's weekly availability."""
    current_user.schedule = [day.model_dump() for day in req.days]
    await current_user.save()
    return {"days": current_user.schedule}


@router.get("/vehicle")
async def get_vehicle(current_user: User = Depends(get_current_user)):
    """Return the driver's registered vehicle, or null if unset."""
    return {"vehicle": current_user.vehicle}


@router.put("/vehicle")
async def save_vehicle(
    req: VehicleUpdate, current_user: User = Depends(get_current_user)
):
    """Create or update the driver's vehicle details."""
    vehicle = dict(current_user.vehicle) if current_user.vehicle else {}
    for field in ("make", "model", "color", "plate"):
        value = getattr(req, field)
        if value is not None:
            vehicle[field] = value
    current_user.vehicle = vehicle
    await current_user.save()
    return {"vehicle": current_user.vehicle}

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
