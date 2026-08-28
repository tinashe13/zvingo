"""Merchant lifecycle happy-path integration tests.

These tests exercise the merchant dashboard flow end-to-end at the router
level, following the same ``SimpleNamespace`` + ``AsyncMock`` + ``monkeypatch``
mocking style used elsewhere in the suite. There is no real DB or Redis here:
every persistence and external call is stubbed.

Scenarios:
  1. Merchant creates a restaurant and gets a correctly-ordered GeoJSON location.
  2. Merchant updates restaurant settings, including the new fields.
  3. Merchant adds a menu item and sees it on the restaurant menu.
  4. Merchant lists their own orders, mapped through their restaurants.
  5. Merchant advances an order from CREATED to ACCEPTED.
"""

from datetime import datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.location.models import Location
from app.order.schemas import OrderItem, OrderUpdateState
from app.order.state_machine import OrderState


class Field:
    def __eq__(self, value):
        return ("eq", value)

    def __neg__(self):
        return self


class Query:
    """A tiny Beanie-query double supporting the chain used by the routers."""

    def __init__(self, values=None):
        self.values = list(values or [])

    def sort(self, *args):
        return self

    def limit(self, *args):
        return self

    def skip(self, *args):
        return self

    async def to_list(self):
        return self.values

    async def count(self):
        return len(self.values)


class OrderQuery(Query):
    """Query double that actually applies a ``merchant_id`` ``$in`` filter."""

    def __init__(self, values=None, filter_dict=None):
        super().__init__(values)
        self.filter_dict = filter_dict

    async def to_list(self):
        if self.filter_dict and "merchant_id" in self.filter_dict:
            allowed = set(self.filter_dict["merchant_id"]["$in"])
            return [v for v in self.values if v.merchant_id in allowed]
        return self.values


def user(id="merchant-1", role="merchant"):
    return SimpleNamespace(id=id, role=role)


def restaurant(**overrides):
    values = {
        "id": "restaurant-1",
        "merchant_id": "merchant-1",
        "name": "Pizza Place",
        "description": "Fresh vegan pizza",
        "location": Location.from_lat_lng(-17.8, 31.0),
        "rating": 4.8,
        "delivery_time_min": 20,
        "delivery_time_max": 35,
        "delivery_fee_usd": 0,
        "free_delivery_threshold": None,
        "is_zvingo_plus": False,
        "review_count": None,
        "neighbors_liked": None,
        "customer_photos_count": None,
        "is_active": True,
        "operating_hours": None,
        "address": "",
        "image_url": None,
        "banner_url": None,
        "categories": ["Pizza"],
        "dietary_tags": ["Vegan"],
        "promotions": [],
        "menu": [],
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def order(**overrides):
    values = {
        "id": "order-1",
        "state": OrderState.CREATED,
        "total_amount": 12.5,
        "created_at": datetime.now(),
        "updated_at": datetime.now(),
        "driver_id": None,
        "merchant_id": "restaurant-1",
        "consumer_id": "consumer-1",
        "items": [OrderItem(name="Meal", quantity=2, price=5.0)],
        "pickup_location": Location.from_lat_lng(-17.8, 31.0),
        "dropoff_location": Location.from_lat_lng(-17.9, 31.1),
        "delivery_instructions": None,
        "group_id": None,
        "events": [],
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
async def test_merchant_creates_restaurant_with_geojson_location(monkeypatch):
    import app.catalog.router as module

    created_instances = []

    class FakeRestaurant:
        merchant_id = Field()
        is_active = Field()

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "restaurant-new"
            self.insert = AsyncMock(
                side_effect=lambda: created_instances.append(self)
            )

    monkeypatch.setattr(module, "Restaurant", FakeRestaurant)
    monkeypatch.setattr(module.settings, "DEV_FORCE_DEFAULT_RESTAURANT_LOCATION", False)

    payload = module.RestaurantCreate(name="New Spot", lat=-17.8, lng=31.1)

    # A non-merchant cannot create a restaurant.
    with pytest.raises(HTTPException) as exc:
        await module.create_restaurant(payload, user(role="consumer"))
    assert exc.value.status_code == 403

    created = await module.create_restaurant(payload, user())

    # Location must be stored in GeoJSON [longitude, latitude] order.
    assert created.location.coordinates == [31.1, -17.8]
    assert created.location.lng == 31.1
    assert created.location.lat == -17.8
    assert created.merchant_id == "merchant-1"
    assert created.name == "New Spot"
    created.insert.assert_awaited_once()
    assert created_instances == [created]


@pytest.mark.asyncio
async def test_merchant_updates_restaurant_settings(monkeypatch):
    import app.catalog.router as module

    current = restaurant()

    class FakeRestaurant:
        get = AsyncMock(return_value=current)

    monkeypatch.setattr(module, "Restaurant", FakeRestaurant)

    update = module.RestaurantUpdate(
        name="Pizza Place 2",
        is_active=False,
        operating_hours="08:00-22:00",
        address="1 Main St",
    )
    result = await module.update_restaurant("restaurant-1", update, user())

    # New fields persist.
    assert result is current
    assert current.name == "Pizza Place 2"
    assert current.is_active is False
    assert current.operating_hours == "08:00-22:00"
    assert current.address == "1 Main St"
    current.save.assert_awaited_once()

    # A different merchant is denied.
    with pytest.raises(HTTPException) as exc:
        await module.update_restaurant(
            "restaurant-1", module.RestaurantUpdate(name="Hijack"), user("other")
        )
    assert exc.value.status_code == 403

    # Updating location still works and produces the correct GeoJSON order.
    location_update = module.RestaurantUpdate(lat=-18.0, lng=32.0)
    await module.update_restaurant("restaurant-1", location_update, user())
    assert current.location.coordinates == [32.0, -18.0]
    assert current.location.lng == 32.0
    assert current.location.lat == -18.0


@pytest.mark.asyncio
async def test_merchant_adds_menu_item(monkeypatch):
    import app.catalog.router as module

    current = restaurant(menu=[])

    class FakeRestaurant:
        get = AsyncMock(return_value=current)

    monkeypatch.setattr(module, "Restaurant", FakeRestaurant)

    item_in = module.MenuItemCreate(
        name="Margherita", description="cheese", price_usd=7.5, category="Mains"
    )
    result = await module.add_menu_item("restaurant-1", item_in, user())

    assert result is current
    assert len(current.menu) == 1
    added = current.menu[0]
    assert added.name == "Margherita"
    assert added.description == "cheese"
    assert added.price_usd == 7.5
    assert added.category == "Mains"
    assert added.is_available is True
    current.save.assert_awaited_once()

    # A non-owner cannot add items to someone else's restaurant.
    with pytest.raises(HTTPException) as exc:
        await module.add_menu_item("restaurant-1", item_in, user("other"))
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_merchant_lists_their_orders(monkeypatch):
    import app.catalog.models as catalog_models
    import app.order.router as module

    owned = [
        order(id="order-1", merchant_id="restaurant-1"),
        order(id="order-2", merchant_id="restaurant-2"),
    ]
    foreign = order(id="order-3", merchant_id="restaurant-3")

    class FakeOrder:
        created_at = Field()
        found = owned + [foreign]
        last_filter = None

        @classmethod
        def find(cls, *args):
            if args and isinstance(args[0], dict):
                cls.last_filter = args[0]
            return OrderQuery(cls.found, cls.last_filter)

    class FakeRestaurant:
        merchant_id = Field()

        @classmethod
        def find(cls, *args):
            return Query(
                [SimpleNamespace(id="restaurant-1"), SimpleNamespace(id="restaurant-2")]
            )

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)

    # Ownership check: merchants may only list their own account's orders.
    with pytest.raises(HTTPException) as exc:
        await module.get_merchant_orders("merchant-1", user("other"))
    assert exc.value.status_code == 403

    result = await module.get_merchant_orders("merchant-1", user("merchant-1"))

    # Orders are mapped through the merchant's restaurants (restaurant-3 excluded).
    assert FakeOrder.last_filter == {
        "merchant_id": {"$in": ["restaurant-1", "restaurant-2"]}
    }
    assert [r.id for r in result] == ["order-1", "order-2"]
    assert result[0].merchant_id == "restaurant-1"
    assert result[1].merchant_id == "restaurant-2"
    assert result[0].items[0].name == "Meal"

    # A merchant with no restaurants has no orders to list.
    FakeRestaurant.find = classmethod(lambda cls, *args: Query([]))
    assert await module.get_merchant_orders("merchant-1", user("merchant-1")) == []


@pytest.mark.asyncio
async def test_merchant_advances_order_state(monkeypatch):
    import app.catalog.models as catalog_models
    import app.notification.service as notification_module
    import app.order.router as router_module
    import app.order.service as service_module

    current = order(state=OrderState.CREATED, driver_id=None, events=[])

    class FakeOrder:
        get = AsyncMock(return_value=current)

    # The router resolves the order through its own `Order` import, and
    # OrderService.transition_state resolves it again through the service.
    monkeypatch.setattr(router_module, "Order", FakeOrder)
    monkeypatch.setattr(service_module, "Order", FakeOrder)
    monkeypatch.setattr(
        notification_module.notification_service, "notify_consumer", AsyncMock()
    )

    class FakeRestaurant:
        get = AsyncMock(return_value=SimpleNamespace(merchant_id="merchant-1"))

    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)

    spawned = []
    monkeypatch.setattr(
        service_module.asyncio,
        "create_task",
        lambda coro: (spawned.append(coro), coro.close())[0],
    )

    result = await router_module.update_order_state(
        "order-1",
        OrderUpdateState(state=OrderState.ACCEPTED),
        user(),
    )

    assert result.state == OrderState.ACCEPTED
    # The security fix: a merchant transitioning CREATED -> ACCEPTED must NOT
    # be assigned as the driver (driver_id comes from the dispatch accept flow,
    # never from this endpoint).
    assert result.driver_id is None
    assert result.items[0].name == "Meal"

    assert current.state == OrderState.ACCEPTED
    assert current.driver_id is None
    assert current.events[-1].state == OrderState.ACCEPTED
    assert current.events[-1].actor_id == "merchant-1"
    current.save.assert_awaited_once()
    assert len(spawned) == 1
