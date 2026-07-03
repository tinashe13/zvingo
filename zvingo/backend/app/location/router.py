import asyncio
import json
from fastapi import APIRouter, Request
from typing import List, Optional
from sse_starlette.sse import EventSourceResponse
import redis.asyncio as aioredis

from app.config import settings
from app.catalog.models import Restaurant
from app.location.service import LocationService

router = APIRouter()


@router.get("/restaurants/nearby")
async def nearby_restaurants(lat: float, lng: float, radius_km: float = 5.0):
    restaurants = await LocationService.find_nearby_restaurants(lat, lng, radius_km)
    return restaurants


@router.get("/driver/{driver_id}/track")
async def track_driver(request: Request, driver_id: str):
    """SSE stream of driver location updates for consumer order tracking."""
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
