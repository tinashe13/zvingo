import httpx
import structlog
from typing import List, Optional
from app.catalog.models import Restaurant

logger = structlog.get_logger()

NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"


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
        """Forward geocode using OpenStreetMap Nominatim (free, no API key)."""
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
                    headers={"User-Agent": "Zvingo/1.0"},
                    timeout=10.0,
                )
                resp.raise_for_status()
                results = resp.json()
                return [
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
