"""Shared GeoJSON Point model used across the domain.

``coordinates`` is stored in MongoDB GeoJSON order: ``[longitude, latitude]``.
Use the ``lat`` / ``lng`` properties (or ``Location.from_lat_lng``) instead of
indexing the list, to avoid accidentally swapping the two values.
"""

from typing import List

from pydantic import BaseModel, model_validator


class Location(BaseModel):
    """A GeoJSON ``Point`` with ergonomic latitude/longitude accessors."""

    type: str = "Point"
    coordinates: List[float]  # [longitude, latitude]

    @property
    def lat(self) -> float:
        """Latitude (coordinates[1])."""
        return self.coordinates[1]

    @property
    def lng(self) -> float:
        """Longitude (coordinates[0])."""
        return self.coordinates[0]

    @property
    def is_null_island(self) -> bool:
        """True when the point is the unresolved (0, 0) sentinel."""
        return abs(self.lat) < 0.01 and abs(self.lng) < 0.01

    @classmethod
    def from_lat_lng(cls, lat: float, lng: float) -> "Location":
        """Build a Location from conventional ``(latitude, longitude)`` order."""
        return cls(coordinates=[lng, lat])

    @model_validator(mode="after")
    def _check_coordinates(self) -> "Location":
        if len(self.coordinates) != 2:
            raise ValueError("Location.coordinates must be [longitude, latitude]")
        return self
