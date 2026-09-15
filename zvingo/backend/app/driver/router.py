from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator, model_validator
from typing import List, Optional
from datetime import datetime
from app.catalog.hours import DEFAULT_TIMEZONE, InvalidHours, format_hhmm, parse_hhmm
from app.time_utils import utc_now
from app.auth.router import get_current_user
from app.auth.models import User, Location
from app.dispatch.service import dispatch_service
from app.dispatch.schemas import DriverLocationUpdate

router = APIRouter()

#: The three shifts the driver app's schedule grid is built from, and the local
#: wall-clock window each one covers. A driver who wants a different window
#: sends explicit `start`/`end` times instead.
SLOT_WINDOWS = {
    0: ("06:00", "12:00"),   # Morning
    1: ("12:00", "17:00"),   # Afternoon
    2: ("17:00", "23:00"),   # Evening
}
SLOT_LABELS = {0: "Morning", 1: "Afternoon", 2: "Evening"}

DAY_LABELS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

VEHICLE_TYPES = ("bicycle", "motorbike", "car", "van", "scooter", "on_foot")


class DashSessionRequest(BaseModel):
    active: bool
    lat: Optional[float] = None
    lng: Optional[float] = None
    radius: Optional[int] = 10


class ScheduleSlot(BaseModel):
    """One availability window on a weekday, in the driver's local timezone.

    The driver app's three-button grid sends `slot` (0/1/2) and the server
    expands it into `start`/`end`; a richer UI can send explicit times and
    leave `slot` unset. Either way the stored shape is the same, so both
    clients read each other's data.
    """

    slot: Optional[int] = Field(default=None, ge=0, le=2)
    start: Optional[str] = None
    end: Optional[str] = None

    @field_validator("start", "end")
    @classmethod
    def _valid_time(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        try:
            return format_hhmm(parse_hhmm(value))
        except InvalidHours as e:
            raise ValueError(str(e)) from None

    @model_validator(mode="after")
    def _expand(self) -> "ScheduleSlot":
        if self.slot is not None and not (self.start and self.end):
            start, end = SLOT_WINDOWS[self.slot]
            object.__setattr__(self, "start", start)
            object.__setattr__(self, "end", end)
        if not (self.start and self.end):
            raise ValueError("Each slot needs either `slot` or both `start` and `end`")
        if parse_hhmm(self.end) <= parse_hhmm(self.start):
            raise ValueError("Slot `end` must be after `start`")
        return self


class ScheduleDay(BaseModel):
    """A weekday's availability.

    `slots` is the legacy list of 0/1/2 shift ids the driver app already sends;
    `windows` is the expanded form the server stores and returns alongside it,
    so an existing client keeps working while a richer one gets real times.
    """

    day: int = Field(ge=0, le=6)  # 0=Mon … 6=Sun
    slots: List[int] = []
    windows: List[ScheduleSlot] = []

    @model_validator(mode="after")
    def _reconcile(self) -> "ScheduleDay":
        if self.slots and not self.windows:
            object.__setattr__(
                self, "windows", [ScheduleSlot(slot=s) for s in sorted(set(self.slots))]
            )
        elif self.windows and not self.slots:
            object.__setattr__(
                self,
                "slots",
                sorted({w.slot for w in self.windows if w.slot is not None}),
            )
        return self


class ScheduleUpdate(BaseModel):
    """A driver's full recurring weekly availability.

    Times are always Africa/Harare wall-clock — Zvingo operates in one
    timezone, and `GET /driver/schedule` echoes it back so the app never has to
    assume. (Per-driver timezones would need a `schedule_timezone` field on the
    user document.)
    """

    days: List[ScheduleDay]


class VehicleUpdate(BaseModel):
    make: Optional[str] = Field(default=None, max_length=40)
    model: Optional[str] = Field(default=None, max_length=40)
    color: Optional[str] = Field(default=None, max_length=24)
    plate: Optional[str] = Field(default=None, max_length=16)
    vehicle_type: Optional[str] = None

    @field_validator("vehicle_type")
    @classmethod
    def _known_type(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalised = value.strip().lower().replace(" ", "_")
        if normalised not in VEHICLE_TYPES:
            raise ValueError(f"vehicle_type must be one of {', '.join(VEHICLE_TYPES)}")
        return normalised

    @field_validator("plate")
    @classmethod
    def _tidy_plate(cls, value: Optional[str]) -> Optional[str]:
        return value.strip().upper() if value else value


def _schedule_payload(user: User) -> dict:
    days = user.schedule or []
    return {
        "days": days,
        "timezone": DEFAULT_TIMEZONE,
        "slot_windows": {
            str(slot): {
                "label": SLOT_LABELS[slot],
                "start": window[0],
                "end": window[1],
            }
            for slot, window in SLOT_WINDOWS.items()
        },
        "day_labels": list(DAY_LABELS),
    }


@router.get("/schedule")
async def get_schedule(current_user: User = Depends(get_current_user)):
    """Return the driver's saved weekly availability.

    Alongside `days` it returns the slot dictionary the UI needs to label the
    grid, so the app never has to hard-code shift times that the backend owns.
    """
    return _schedule_payload(current_user)


@router.put("/schedule")
async def save_schedule(
    req: ScheduleUpdate, current_user: User = Depends(get_current_user)
):
    """Persist the driver's weekly availability (recurring, every week)."""
    seen: set = set()
    days = []
    for day in req.days:
        if day.day in seen:
            raise HTTPException(
                status_code=400, detail=f"Duplicate entry for {DAY_LABELS[day.day]}"
            )
        seen.add(day.day)
        days.append(day.model_dump())
    current_user.schedule = days
    await current_user.save()
    return _schedule_payload(current_user)


@router.get("/vehicle")
async def get_vehicle(current_user: User = Depends(get_current_user)):
    """Return the driver's registered vehicle, or null if unset."""
    return {"vehicle": current_user.vehicle, "vehicle_types": list(VEHICLE_TYPES)}


@router.put("/vehicle")
async def save_vehicle(
    req: VehicleUpdate, current_user: User = Depends(get_current_user)
):
    """Create or update the driver's vehicle details."""
    vehicle = dict(current_user.vehicle) if current_user.vehicle else {}
    for field in ("make", "model", "color", "plate", "vehicle_type"):
        value = getattr(req, field)
        if value is not None:
            vehicle[field] = value
    current_user.vehicle = vehicle
    await current_user.save()
    return {"vehicle": current_user.vehicle, "vehicle_types": list(VEHICLE_TYPES)}


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
