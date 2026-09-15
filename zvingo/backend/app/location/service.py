import json
import httpx
import structlog
from typing import List, Optional
from app.catalog.models import Restaurant
from app.config import settings
from app.db.redis import redis_client

logger = structlog.get_logger()

NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"

#: Geocode results are cached this long. Addresses are stable, and Nominatim's
#: usage policy requires caching rather than re-asking.
GEOCODE_CACHE_TTL = 30 * 24 * 60 * 60  # 30 days
#: Empty results expire sooner, so a genuine new address is not shadowed for a
#: month by one bad lookup.
GEOCODE_EMPTY_CACHE_TTL = 60 * 60  # 1 hour


def _nominatim_user_agent() -> str:
    """Nominatim requires a User-Agent that identifies the app and a contact.

    A bare "Zvingo/1.0" does not identify anyone to contact before a block.
    """
    contact = getattr(settings, "NOMINATIM_CONTACT_EMAIL", None) or ""
    base = f"Zvingo/{getattr(settings, 'APP_VERSION', '1.0')}"
    return f"{base} ({contact})" if contact else base




#: Ceiling on how many documents one nearby lookup may pull, however the
#: caller paginates. `$near` returns nearest-first, so this is a real bound.
NEARBY_POOL = 200


class LocationService:
    @staticmethod
    async def find_nearby_restaurants(
        lat: float,
        lng: float,
        radius_km: float = 5.0,
        limit: int = 20,
        offset: int = 0,
        open_now: bool = False,
    ) -> List[Restaurant]:
        """Active restaurants within `radius_km`, ranked and page-bounded.

        Uses the 2dsphere index on `Restaurant.location` for the geo filter,
        then applies the shared discovery ranking so "near me" orders by the
        same signals as search (distance, rating, speed, promos, open-now).
        """
        from app.catalog import search_service
        from app.catalog.hours import availability_of

        radius_meters = radius_km * 1000
        pool = min(NEARBY_POOL, max(offset + limit, limit) * 4)
        restaurants = await Restaurant.find(
            {
                "location": {
                    "$near": {
                        "$geometry": {
                            "type": "Point",
                            "coordinates": [lng, lat]
                        },
                        "$maxDistance": radius_meters
                    }
                },
                "is_active": True
            }
        ).limit(pool).to_list()

        if open_now:
            restaurants = [r for r in restaurants if availability_of(r)["is_open"]]

        ranked = search_service.rank(
            restaurants, lat=lat, lng=lng, radius_km=radius_km
        )
        page = ranked[offset : offset + limit]
        return [search_service.attach_discovery(entry) for entry in page]

    @staticmethod
    async def geocode(query: str, country: str = "zw") -> List[dict]:
        """Forward geocode via OpenStreetMap Nominatim.

        This endpoint stays anonymous on purpose: merchant sign-up needs it
        before an account exists. That makes caching the control that matters.
        Nominatim's usage policy is roughly one request a second, requires an
        identifying User-Agent, and requires caching -- breach it and the
        droplet's IP is banned, which takes address search down for every user
        of every app at once.

        Results are cached in Redis by normalised query, so repeated lookups
        (and a user typing the same address twice) cost nothing upstream.
        """
        normalised = " ".join(query.split()).lower()
        if not normalised:
            return []

        cache_key = f"geocode:{country}:{normalised}"

        try:
            async with redis_client() as r:
                cached = await r.get(cache_key)
                if cached:
                    return json.loads(cached)
        except Exception as e:  # cache is an optimisation, never a dependency
            logger.debug("Geocode cache read failed", error=str(e))

        try:
            async with httpx.AsyncClient() as client:
                resp = await client.get(
                    NOMINATIM_URL,
                    params={
                        "q": query,
                        "format": "json",
                        "countrycodes": country,
                        "limit": 5,
                        "addressdetails": 1,
                    },
                    headers={"User-Agent": _nominatim_user_agent()},
                    timeout=10.0,
                )
                resp.raise_for_status()
                results = resp.json()
                parsed = [
                    {
                        "display_name": r.get("display_name", ""),
                        "lat": float(r["lat"]),
                        "lng": float(r["lon"]),
                        "type": r.get("type", ""),
                    }
                    for r in results
                ]
        except Exception as e:
            logger.error("Geocode failed", error=str(e))
            return []

        try:
            async with redis_client() as r:
                # Addresses do not move. A long TTL is what keeps us inside the
                # upstream policy; empty results are cached briefly so a typo
                # cannot be used to hammer through the cache.
                ttl = GEOCODE_CACHE_TTL if parsed else GEOCODE_EMPTY_CACHE_TTL
                await r.setex(cache_key, ttl, json.dumps(parsed))
        except Exception as e:
            logger.debug("Geocode cache write failed", error=str(e))

        return parsed
