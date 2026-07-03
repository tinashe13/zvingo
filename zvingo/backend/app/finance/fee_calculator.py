"""
Delivery fee calculation engine.

Formula:  $5 per started 5 km block.
  blocks = ceil(distance_km / 5)
  gross_fee = blocks * 5.0
  driver_share = gross_fee * 0.85  (driver keeps 85%)

Example: 8 km → ceil(8/5) = 2 blocks → $10 gross → $8.50 driver share.
"""

import math
from typing import Tuple

from app.config import settings

# Fee constants
BLOCK_SIZE_KM = 5.0
BLOCK_PRICE_USD = 5.0
DRIVER_SHARE_RATIO = settings.DRIVER_SHARE_RATIO  # default 0.85

# Haversine
_R = 6371.0  # Earth radius in km


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Compute great-circle distance in km between two lat/lng points."""
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlng / 2) ** 2
    )
    return _R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def calculate_delivery_fee(distance_km: float) -> Tuple[float, float]:
    """
    Calculate delivery fee given the delivery distance (pickup → dropoff).

    Returns:
        (gross_fee_usd, driver_share_usd)
    """
    if distance_km <= 0:
        return (BLOCK_PRICE_USD, round(BLOCK_PRICE_USD * DRIVER_SHARE_RATIO, 2))

    blocks = math.ceil(distance_km / BLOCK_SIZE_KM)
    gross = blocks * BLOCK_PRICE_USD
    driver = round(gross * DRIVER_SHARE_RATIO, 2)
    return (gross, driver)


def calculate_delivery_fee_from_coords(
    pickup_lat: float,
    pickup_lng: float,
    dropoff_lat: float,
    dropoff_lng: float,
) -> Tuple[float, float, float]:
    """
    Calculate delivery fee from pickup/dropoff coordinates.

    Returns:
        (gross_fee_usd, driver_share_usd, distance_km)
    """
    dist = haversine_km(pickup_lat, pickup_lng, dropoff_lat, dropoff_lng)
    gross, driver = calculate_delivery_fee(dist)
    return (gross, driver, round(dist, 2))
