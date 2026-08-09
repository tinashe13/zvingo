from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException


class Field:
    def __eq__(self, value):
        return ("eq", value)


class Query:
    def __init__(self, values=None, count=None):
        self.values = list(values or [])
        self.count_value = len(self.values) if count is None else count

    def sort(self, *args):
        return self

    def limit(self, *args):
        return self

    def skip(self, *args):
        return self

    async def to_list(self):
        return self.values

    async def count(self):
        return self.count_value


def user(role="merchant", id="merchant-1"):
    return SimpleNamespace(id=id, role=role)


def restaurant(**overrides):
    values = {
        "id": "restaurant-1",
        "merchant_id": "merchant-1",
        "name": "Pizza Place",
        "description": "Fresh vegan pizza",
        "location": SimpleNamespace(coordinates=[31.0, -17.0]),
        "rating": 4.8,
        "delivery_time_min": 20,
        "delivery_time_max": 35,
        "delivery_fee_usd": 0,
        "is_active": True,
        "categories": ["Pizza"],
        "dietary_tags": ["Vegan"],
        "promotions": ["deal"],
        "menu": [],
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def menu_item(**overrides):
    values = {
        "id": "item-1",
        "name": "Pepperoni Pizza",
        "description": "spicy favourite",
        "price_usd": 9.0,
        "category": "Mains",
        "is_available": True,
        "image_url": None,
        "images": [],
        "approval_percent": None,
        "approval_count": None,
        "is_great_price": False,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
async def test_restaurant_listing_creation_and_lookup(monkeypatch):
    import app.catalog.router as module

    first = restaurant()
    second = restaurant(
        id="restaurant-2", rating=3.0, delivery_time_min=45,
        delivery_fee_usd=3, categories=["Burgers"], dietary_tags=[],
        promotions=[],
    )

    class FakeRestaurant:
        merchant_id = Field()
        is_active = Field()
        get = AsyncMock()
        inserted = []
        found = [first, second]

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "new-restaurant"
            self.insert = AsyncMock(side_effect=lambda: self.inserted.append(self))

        @classmethod
        def find(cls, *args):
            return Query(cls.found)

    monkeypatch.setattr(module, "Restaurant", FakeRestaurant)

    assert await module.list_restaurants(merchant_id="merchant-1") == [first, second]
    assert await module.list_restaurants(lat=-17, lon=31) == [first, second]
    assert await module.list_restaurants() == [first, second]
    assert await module.list_restaurants(free_delivery=True) == [first]
    assert await module.list_restaurants(min_rating=4) == [first]
    assert await module.list_restaurants(dietary="Vegan, Vegetarian") == [first]
    assert await module.list_restaurants(category="pizza, chicken") == [first]
    assert await module.list_restaurants(has_promotions=True) == [first]
    assert (await module.list_restaurants(sort_by="rating"))[0] is first
    assert (await module.list_restaurants(sort_by="delivery_time"))[0] is first
    assert (await module.list_restaurants(sort_by="delivery_fee"))[0] is first

    payload = module.RestaurantCreate(name="New", lat=-17.8, lng=31.1)
    with pytest.raises(HTTPException) as exc:
        await module.create_restaurant(payload, user("consumer"))
    assert exc.value.status_code == 403

    monkeypatch.setattr(module.settings, "DEV_FORCE_DEFAULT_RESTAURANT_LOCATION", False)
    created = await module.create_restaurant(payload, user())
    assert created.location.coordinates == [31.1, -17.8]
    monkeypatch.setattr(module.settings, "DEV_FORCE_DEFAULT_RESTAURANT_LOCATION", True)
    monkeypatch.setattr(module, "get_default_restaurant_coords", lambda: (-18.0, 32.0))
    created = await module.create_restaurant(payload, user())
    assert created.location.coordinates == [32.0, -18.0]

    FakeRestaurant.get.return_value = None
    with pytest.raises(HTTPException) as exc:
        await module.get_restaurant("missing")
    assert exc.value.status_code == 404
    FakeRestaurant.get.return_value = first
    assert await module.get_restaurant("restaurant-1") is first


@pytest.mark.asyncio
async def test_restaurant_and_menu_mutations(monkeypatch):
    import app.catalog.router as module

    current = restaurant(menu=[menu_item()])

    class FakeRestaurant:
        get = AsyncMock(return_value=current)

    monkeypatch.setattr(module, "Restaurant", FakeRestaurant)
    full_update = module.RestaurantUpdate(
        name="Updated", description="Description", image_url="image",
        banner_url="banner", delivery_time_min=10, delivery_time_max=15,
        delivery_fee_usd=1.5, lat=-18, lng=32,
        free_delivery_threshold=20, is_zvingo_plus=True, review_count=10,
        neighbors_liked=3, customer_photos_count=4,
    )
    result = await module.update_restaurant("restaurant-1", full_update, user())
    assert result.name == "Updated"
    assert result.location.coordinates == [32, -18]
    result.save.assert_awaited()

    with pytest.raises(HTTPException) as exc:
        await module.update_restaurant(
            "restaurant-1", module.RestaurantUpdate(lat=-18), user()
        )
    assert exc.value.status_code == 400
    with pytest.raises(HTTPException) as exc:
        await module.update_restaurant("restaurant-1", module.RestaurantUpdate(), user(id="other"))
    assert exc.value.status_code == 403
    FakeRestaurant.get.return_value = None
    with pytest.raises(HTTPException):
        await module.update_restaurant("missing", module.RestaurantUpdate(), user())

    FakeRestaurant.get.return_value = current
    item_in = module.MenuItemCreate(
        name="Burger", description="good", price_usd=5, category="Mains",
        image_url="img", images=["a"], approval_percent=90,
        approval_count=12, is_great_price=True,
    )
    await module.add_menu_item("restaurant-1", item_in, user())
    assert current.menu[-1].name == "Burger"
    with pytest.raises(HTTPException):
        await module.add_menu_item("restaurant-1", item_in, user(id="other"))
    FakeRestaurant.get.return_value = None
    with pytest.raises(HTTPException):
        await module.add_menu_item("missing", item_in, user())

    FakeRestaurant.get.return_value = current
    update = module.MenuItemUpdate(
        is_available=False, name="Renamed", price_usd=7, category="Dinner",
        description="new", image_url="new-img", images=["b"],
        approval_percent=95, approval_count=20, is_great_price=True,
    )
    await module.update_menu_item("restaurant-1", "item-1", update, user())
    assert current.menu[0].name == "Renamed"
    with pytest.raises(HTTPException):
        await module.update_menu_item("restaurant-1", "missing", update, user())
    with pytest.raises(HTTPException):
        await module.update_menu_item("restaurant-1", "item-1", update, user(id="other"))
    FakeRestaurant.get.return_value = None
    with pytest.raises(HTTPException):
        await module.update_menu_item("missing", "item-1", update, user())

    FakeRestaurant.get.return_value = current
    with pytest.raises(HTTPException):
        await module.delete_menu_item("restaurant-1", "missing", user())
    current.menu = [menu_item()]
    await module.delete_menu_item("restaurant-1", "item-1", user())
    assert current.menu == []
    current.menu = [menu_item()]
    with pytest.raises(HTTPException):
        await module.delete_menu_item("restaurant-1", "item-1", user(id="other"))
    FakeRestaurant.get.return_value = None
    with pytest.raises(HTTPException):
        await module.delete_menu_item("missing", "item-1", user())


@pytest.mark.asyncio
async def test_catalog_search_and_promotions(monkeypatch):
    import app.catalog.router as module

    item = menu_item()
    current = restaurant(menu=[item, menu_item(id="item-2", name="Salad", description=None, category="Sides")])

    class FakeRestaurant:
        get = AsyncMock(return_value=current)

        @classmethod
        def find(cls, *args):
            return Query([current])

    monkeypatch.setattr(module, "Restaurant", FakeRestaurant)
    assert await module.search_catalog("x") == []
    assert await module.search_catalog("pizza") == [current]
    assert await module.search_restaurant_items("restaurant-1", "x") == []
    assert await module.search_restaurant_items("restaurant-1", "pizza") == [item]
    assert await module.search_restaurant_items("restaurant-1", "spicy") == [item]
    assert await module.search_restaurant_items("restaurant-1", "mains") == [item]
    FakeRestaurant.get.return_value = None
    with pytest.raises(HTTPException):
        await module.search_restaurant_items("missing", "pizza")

    promos = [
        SimpleNamespace(max_uses=None, current_uses=100),
        SimpleNamespace(max_uses=2, current_uses=1),
        SimpleNamespace(max_uses=1, current_uses=1),
    ]

    class FakePromotion:
        merchant_id = Field()
        get = AsyncMock()
        found = promos
        created = []

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "promo-new"
            self.insert = AsyncMock(side_effect=lambda: self.created.append(self))
            self.save = AsyncMock()
            self.delete = AsyncMock()

        @classmethod
        def find(cls, *args):
            return Query(cls.found)

    monkeypatch.setattr(module, "Promotion", FakePromotion)
    active = await module.list_active_promotions("restaurant-1")
    assert active == promos[:2]
    assert await module.list_merchant_promotions(user()) == promos

    create = module.PromotionCreate(title="Deal", subtitle="Save", starts_at=datetime.now())
    with pytest.raises(HTTPException):
        await module.create_promotion(create, user("consumer"))
    created = await module.create_promotion(create, user())
    assert created.title == "Deal"
    created_without_start = await module.create_promotion(
        module.PromotionCreate(title="Now", subtitle="Live"), user()
    )
    assert isinstance(created_without_start.starts_at, datetime)

    FakePromotion.get.return_value = None
    with pytest.raises(HTTPException):
        await module.get_promotion("missing")
    FakePromotion.get.return_value = created
    assert await module.get_promotion("promo-new") is created

    await module.update_promotion(
        "promo-new", module.PromotionUpdate(title="Changed", is_active=False), user()
    )
    assert created.title == "Changed"
    created.merchant_id = "other"
    with pytest.raises(HTTPException):
        await module.update_promotion("promo-new", module.PromotionUpdate(), user())
    created.merchant_id = "merchant-1"
    FakePromotion.get.return_value = None
    with pytest.raises(HTTPException):
        await module.update_promotion("missing", module.PromotionUpdate(), user())

    FakePromotion.get.return_value = created
    await module.delete_promotion("promo-new", user())
    created.delete.assert_awaited()
    created.merchant_id = "other"
    with pytest.raises(HTTPException):
        await module.delete_promotion("promo-new", user())
    created.merchant_id = "merchant-1"
    FakePromotion.get.return_value = None
    with pytest.raises(HTTPException):
        await module.delete_promotion("missing", user())

    FakePromotion.get.return_value = created
    created.is_active = False
    toggled = await module.toggle_promotion("promo-new", user())
    assert toggled.is_active is True
    created.merchant_id = "other"
    with pytest.raises(HTTPException):
        await module.toggle_promotion("promo-new", user())
    FakePromotion.get.return_value = None
    with pytest.raises(HTTPException):
        await module.toggle_promotion("missing", user())

    reset = AsyncMock()
    monkeypatch.setattr(module, "backfill_restaurant_locations", reset)
    monkeypatch.setattr(module.settings, "DEV_ALLOW_ADMIN_ENDPOINTS", False)
    with pytest.raises(HTTPException):
        await module.reset_restaurant_locations()
    monkeypatch.setattr(module.settings, "DEV_ALLOW_ADMIN_ENDPOINTS", True)
    assert await module.reset_restaurant_locations(False) == {"status": "ok", "force_all": False}
    reset.assert_awaited_once_with(force_all=False)
