import asyncio
import json
from fastapi import APIRouter, Query, Request
from typing import Annotated, List, Optional
from sse_starlette.sse import EventSourceResponse
import redis.asyncio as aioredis

from app.config import settings
from app.catalog.models import Restaurant
from app.location.service import LocationService
from app.notification.stream_auth import redeem_ticket

router = APIRouter()


@router.get("/restaurants/nearby")
async def nearby_restaurants(
    lat: float,
    lng: float,
    radius_km: float = 5.0,
    open_now: bool = False,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 25,
):
    """Restaurants near a point, nearest first, ranked and paginated.

    Each result carries the same `availability` and `discovery` blocks as
    `/catalog/search`, so a map or "near you" carousel can show distance and
    open/closed without a second round trip.
    """
    return await LocationService.find_nearby_restaurants(
        lat, lng, radius_km, limit=limit, offset=offset, open_now=open_now
    )


@router.get("/driver/{driver_id}/track")
async def track_driver(request: Request, driver_id: str, ticket: str = ""):
    """SSE stream of a driver's live position, for consumer order tracking.

    Requires a ticket from ``POST /notification/stream-ticket`` for the
    ``driver_loc_{driver_id}`` channel. Unauthenticated, this endpoint was a
    stalking primitive aimed at gig workers: anyone who knew a driver id could
    follow them in real time. The ticket is only issued to that driver, an
    admin, or a participant in an order they are currently delivering.
    """
    await redeem_ticket(ticket, f"driver_loc_{driver_id}")
    async def event_generator():
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        pubsub = r.pubsub()
        await pubsub.subscribe(f"driver_loc_{driver_id}")

        try:
            async for message in pubsub.listen():
                if await request.is_disconnected():
                    break
                if message["type"] == "message":
                    yield {
                        "event": "location",
                        "data": message["data"]
                    }
        except asyncio.CancelledError:
            pass
        finally:
            await pubsub.unsubscribe(f"driver_loc_{driver_id}")
            await r.close()

    return EventSourceResponse(event_generator())


@router.get("/geocode")
async def geocode(q: str, country: str = "zw"):
    results = await LocationService.geocode(q, country)
    return results
