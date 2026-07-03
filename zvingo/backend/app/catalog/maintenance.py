import structlog
from app.catalog.models import Restaurant, Location
from app.config import settings

logger = structlog.get_logger()

# Place default restaurants ~X miles north of base location
MILES_TO_KM = 1.60934
KM_PER_DEG_LAT = 111.32


def get_default_restaurant_coords() -> tuple[float, float]:
    offset_deg_lat = (settings.DEV_DEFAULT_OFFSET_MILES * MILES_TO_KM) / KM_PER_DEG_LAT
    default_lat = settings.DEV_DEFAULT_BASE_LAT + offset_deg_lat
    default_lng = settings.DEV_DEFAULT_BASE_LNG
    return default_lat, default_lng


async def backfill_restaurant_locations(force_all: bool = False) -> None:
    """
    Ensure all existing restaurants have a default location.
    If force_all=True, overwrite locations for all restaurants.
    """
    restaurants = await Restaurant.find_all().to_list()
    if not restaurants:
        return

    default_lat, default_lng = get_default_restaurant_coords()
    updated = 0
    for r in restaurants:
        if not force_all:
            coords = r.location.coordinates if r.location else None
            if coords and abs(coords[0]) > 0.01 and abs(coords[1]) > 0.01:
                continue

        r.location = Location(coordinates=[default_lng, default_lat])
        await r.save()
        updated += 1

    logger.info("Restaurant location backfill complete", total=len(restaurants), updated=updated)
