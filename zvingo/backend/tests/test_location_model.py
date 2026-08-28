"""Unit tests for the shared Location model and OrderCreate location normalization."""

import pytest
from pydantic import ValidationError

from app.location.models import Location
from app.order.schemas import OrderCreate, OrderItem


class TestLocationModel:
    def test_default_type_is_point(self):
        loc = Location(coordinates=[31.0, -17.8])
        assert loc.type == "Point"

    def test_lat_lng_properties_respect_geojson_order(self):
        loc = Location(coordinates=[31.0, -17.8])
        assert loc.lng == 31.0
        assert loc.lat == -17.8

    def test_from_lat_lng_swaps_into_geojson_order(self):
        loc = Location.from_lat_lng(lat=-17.8, lng=31.0)
        assert loc.coordinates == [31.0, -17.8]
        assert loc.lat == -17.8
        assert loc.lng == 31.0

    def test_is_null_island_detects_zero_sentinel(self):
        assert Location.from_lat_lng(0, 0).is_null_island is True
        assert Location.from_lat_lng(-17.8, 31.0).is_null_island is False

    def test_round_trips_to_geojson_dict(self):
        loc = Location.from_lat_lng(-17.8, 31.0)
        assert loc.model_dump() == {"type": "Point", "coordinates": [31.0, -17.8]}

    def test_rejects_non_pair_coordinates(self):
        with pytest.raises(ValidationError):
            Location(coordinates=[31.0])


class TestOrderCreateLocationNormalization:
    def _base(self, **overrides):
        values = {
            "merchant_id": "merchant",
            "consumer_id": "consumer",
            "items": [OrderItem(name="Burger", quantity=1, price=10)],
            "total_amount": 15,
        }
        values.update(overrides)
        return values

    def test_accepts_nested_locations(self):
        order = OrderCreate(
            **self._base(
                pickup=Location.from_lat_lng(-17.8, 31.0),
                dropoff=Location.from_lat_lng(-17.9, 31.1),
            )
        )
        assert order.pickup.lat == -17.8
        assert order.dropoff.lng == 31.1

    def test_folds_legacy_flat_fields_into_locations(self):
        order = OrderCreate(
            **self._base(
                pickup_lat=-17.8,
                pickup_lng=31.0,
                dropoff_lat=-17.9,
                dropoff_lng=31.1,
            )
        )
        assert order.pickup.coordinates == [31.0, -17.8]
        assert order.dropoff.coordinates == [31.1, -17.9]

    def test_legacy_pickup_requires_both_coordinates(self):
        with pytest.raises(ValidationError):
            OrderCreate(**self._base(pickup_lat=-17.8, dropoff=Location.from_lat_lng(-17.9, 31.1)))

    def test_legacy_dropoff_requires_both_coordinates(self):
        with pytest.raises(ValidationError):
            OrderCreate(**self._base(pickup=Location.from_lat_lng(-17.8, 31.0), dropoff_lng=31.1))

    def test_allows_omitted_pickup_for_backend_resolution(self):
        # A missing pickup is allowed at the schema layer; the service resolves
        # it from the restaurant record (or rejects if unresolvable).
        order = OrderCreate(**self._base(dropoff=Location.from_lat_lng(-17.9, 31.1)))
        assert order.pickup is None
