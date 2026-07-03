import httpx
import structlog
from typing import List, Optional
from app.catalog.models import Restaurant

logger = structlog.get_logger()

NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"


class LocationService:
    @staticmethod
    async def find_nearby_restaurants(lat: float, lng: float, radius_km: float = 5.0, limit: int = 20) -> List[Restaurant]:
        radius_meters = radius_km * 1000
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
        ).limit(limit).to_list()
        return restaurants

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
