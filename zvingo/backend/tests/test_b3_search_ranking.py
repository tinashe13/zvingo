"""Catalog search: typo tolerance, cross-field matching, ranking, pagination."""

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.catalog import search_service
from app.catalog.hours import DayHours, HoursInterval


class Query:
    """Beanie-query double supporting the chain the catalog router uses."""

    def __init__(self, values=None):
        self.values = list(values or [])
        self.skip_value = None
        self.limit_value = None

    def sort(self, *args):
        return self

    def skip(self, value):
        self.skip_value = value
        return self

    def limit(self, value):
        self.limit_value = value
        return self

    async def to_list(self):
        return self.values


def item(name, category="Mains", price=10.0, description=None, available=True):
    return SimpleNamespace(
        id=name.lower().replace(" ", "-"),
        name=name,
        category=category,
        price_usd=price,
        description=description,
        is_available=available,
    )


def restaurant(name, **overrides):
    values = {
        "id": name.lower().replace(" ", "-"),
        "merchant_id": "merchant-1",
        "name": name,
        "description": "",
        "location": SimpleNamespace(coordinates=[31.05, -17.83]),
        "rating": 4.5,
        "review_count": 100,
        "delivery_time_min": 25,
        "delivery_time_max": 40,
        "delivery_fee_usd": 2.0,
        "is_active": True,
        "categories": [],
        "dietary_tags": [],
        "promotions": [],
        "menu": [],
        "hours": [],
        "timezone": "Africa/Harare",
        "is_open_override": None,
        "pause_until": None,
        "accepts_scheduled_orders": True,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def patch_catalog(monkeypatch, restaurants):
    import app.catalog.router as module

    query = Query(restaurants)

    class FakeRestaurant:
        merchant_id = SimpleNamespace(__eq__=lambda self, other: ("eq", other))
        is_active = SimpleNamespace(__eq__=lambda self, other: ("eq", other))
        get = AsyncMock(return_value=restaurants[0] if restaurants else None)

        @classmethod
        def find(cls, *args, **kwargs):
            return query

    monkeypatch.setattr(module, "Restaurant", FakeRestaurant)
    return module, query


# ── Text normalisation and token matching ───────────────────────────


def test_normalise_strips_case_accents_and_punctuation():
    assert search_service.normalise("Café  Nando's!") == "cafe nandos"
    assert search_service.normalise(None) == ""


def test_tokenize_singularises():
    assert search_service.tokenize("Burgers and Fries") == ["burger", "and", "fry"]


def test_token_score_ranks_exact_above_prefix_above_substring():
    exact = search_service.token_score("pizza", "pizza")
    word = search_service.token_score("pizza", "pizza place")
    prefix = search_service.token_score("piz", "pizza place")
    substring = search_service.token_score("izza", "pizza place")
    assert exact > word > prefix > substring > 0


@pytest.mark.parametrize("typo", ["piza", "pizzza", "pzza"])
def test_fuzzy_matching_absorbs_typos(typo):
    assert search_service.token_score(typo, "pizza") > 0


def test_unrelated_words_do_not_match():
    assert search_service.token_score("sushi", "pizza") == 0.0
    assert search_service.token_score("", "pizza") == 0.0


# ── Cross-field relevance ───────────────────────────────────────────


def test_query_matches_a_menu_item_even_when_the_name_does_not():
    """The headline requirement: searching "pizza" finds a shop that sells it."""
    mario = restaurant("Mario's Kitchen", menu=[item("Margherita Pizza")])
    relevance, matched = search_service.score_relevance(mario, ["pizza"])
    assert relevance > 0
    assert matched == ["Margherita Pizza"]


def test_query_matches_a_cuisine_category():
    spot = restaurant("The Corner Spot", categories=["Pizza", "Italian"])
    relevance, _ = search_service.score_relevance(spot, ["italian"])
    assert relevance > 0


def test_unavailable_menu_items_are_not_searchable():
    shop = restaurant("Shop", menu=[item("Pizza", available=False)])
    relevance, _ = search_service.score_relevance(shop, ["pizza"])
    assert relevance == 0.0


def test_a_name_hit_outranks_a_menu_hit():
    named = restaurant("Pizza Palace")
    seller = restaurant("Mario's", menu=[item("Pizza")])
    assert (
        search_service.score_relevance(named, ["pizza"])[0]
        > search_service.score_relevance(seller, ["pizza"])[0]
    )


def test_every_query_token_must_match_something():
    shop = restaurant("Pizza Palace", menu=[item("Margherita")])
    assert search_service.score_relevance(shop, ["pizza", "sushi"])[0] == 0.0
    assert search_service.score_relevance(shop, ["pizza", "margherita"])[0] > 0


def test_empty_query_matches_everything_at_full_relevance():
    assert search_service.score_relevance(restaurant("Anything"), [])[0] == 1.0


# ── Ranking signals ─────────────────────────────────────────────────


def test_proximity_decays_to_zero_at_the_radius_edge():
    assert search_service.proximity_score(0.0, 10.0) == 1.0
    assert search_service.proximity_score(5.0, 10.0) == pytest.approx(0.5)
    assert search_service.proximity_score(20.0, 10.0) == 0.0
    # No consumer location means nothing to prefer.
    assert search_service.proximity_score(None, 10.0) == 1.0


def test_quality_is_bayesian_so_one_five_star_review_does_not_win():
    lucky = restaurant("Lucky", rating=5.0, review_count=1)
    proven = restaurant("Proven", rating=4.6, review_count=500)
    assert search_service.quality_score(proven) > search_service.quality_score(lucky)


def test_speed_prefers_a_faster_promise():
    assert search_service.speed_score(restaurant("F", delivery_time_min=10)) == 1.0
    assert search_service.speed_score(restaurant("S", delivery_time_min=60)) == 0.0


def test_promotion_signal_counts_free_delivery():
    assert search_service.promotion_score(restaurant("A", delivery_fee_usd=0)) == 1.0
    assert search_service.promotion_score(restaurant("B", promotions=["x"])) == 1.0
    assert search_service.promotion_score(restaurant("C")) == 0.0


def test_closer_restaurant_wins_when_everything_else_is_equal():
    near = restaurant("Near", location=SimpleNamespace(coordinates=[31.05, -17.83]))
    far = restaurant("Far", location=SimpleNamespace(coordinates=[31.35, -17.83]))
    ranked = search_service.rank([far, near], lat=-17.83, lng=31.05, radius_km=10)
    assert [r["restaurant"].name for r in ranked] == ["Near", "Far"]
    assert ranked[0]["distance_km"] == pytest.approx(0.0, abs=0.01)


def test_closed_restaurants_are_demoted_but_never_hidden():
    shut = restaurant(
        "Shut",
        rating=5.0,
        review_count=1000,
        is_open_override=False,
    )
    open_now = restaurant("Open", rating=4.0, review_count=1000)
    ranked = search_service.rank([shut, open_now])
    names = [r["restaurant"].name for r in ranked]
    assert names == ["Open", "Shut"]
    # Still present, and flagged with a reason the UI can render.
    assert ranked[1]["availability"]["status"] == "closed_by_merchant"


def test_a_hard_closed_restaurant_is_demoted_below_a_preorderable_one():
    preorder = restaurant(
        "Preorder",
        hours=[DayHours(day=d, intervals=[]) for d in range(7)],
        accepts_scheduled_orders=True,
    )
    delisted = restaurant(
        "Delisted",
        hours=[DayHours(day=d, intervals=[]) for d in range(7)],
        accepts_scheduled_orders=False,
    )
    ranked = search_service.rank([delisted, preorder])
    assert [r["restaurant"].name for r in ranked] == ["Preorder", "Delisted"]


def test_rank_is_deterministic_for_identical_scores():
    a = restaurant("Alpha")
    b = restaurant("Beta")
    first = [r["restaurant"].name for r in search_service.rank([b, a])]
    second = [r["restaurant"].name for r in search_service.rank([a, b])]
    assert first == second == ["Alpha", "Beta"]


# ── The /catalog/search endpoint ────────────────────────────────────


@pytest.mark.asyncio
async def test_search_requires_a_meaningful_query(monkeypatch):
    module, _ = patch_catalog(monkeypatch, [restaurant("Pizza Palace")])
    assert await module.search_catalog("") == []
    assert await module.search_catalog("p") == []
    assert await module.search_catalog("  ") == []


@pytest.mark.asyncio
async def test_search_finds_a_restaurant_by_its_menu_and_reports_why(monkeypatch):
    mario = restaurant("Mario's Kitchen", menu=[item("Pepperoni Pizza")])
    module, _ = patch_catalog(monkeypatch, [mario])

    results = await module.search_catalog("pizza")
    assert results == [mario]
    # The ranking metadata rides along so the UI can say *why* it matched.
    assert mario._discovery["matched_menu_items"] == ["Pepperoni Pizza"]
    assert mario._discovery["score"] > 0


@pytest.mark.asyncio
async def test_search_tolerates_a_typo(monkeypatch):
    mario = restaurant("Mario's Kitchen", menu=[item("Pepperoni Pizza")])
    module, _ = patch_catalog(monkeypatch, [mario])
    assert await module.search_catalog("piza") == [mario]


@pytest.mark.asyncio
async def test_search_drops_inactive_restaurants(monkeypatch):
    module, _ = patch_catalog(
        monkeypatch, [restaurant("Pizza Palace", is_active=False)]
    )
    assert await module.search_catalog("pizza") == []


@pytest.mark.asyncio
async def test_search_filters_stack(monkeypatch):
    cheap = restaurant(
        "Pizza Cheap", menu=[item("Pizza", price=4.0)], delivery_fee_usd=0,
        rating=4.9, delivery_time_max=25, dietary_tags=["Vegan"], categories=["Pizza"],
    )
    pricey = restaurant(
        "Pizza Pricey", menu=[item("Pizza", price=30.0)], delivery_fee_usd=5,
        rating=3.2, delivery_time_max=70, categories=["Pizza"],
    )
    module, _ = patch_catalog(monkeypatch, [cheap, pricey])

    assert await module.search_catalog("pizza", free_delivery=True) == [cheap]
    assert await module.search_catalog("pizza", min_rating=4.0) == [cheap]
    assert await module.search_catalog("pizza", max_delivery_minutes=30) == [cheap]
    assert await module.search_catalog("pizza", price_band=1) == [cheap]
    assert await module.search_catalog("pizza", dietary="Vegan") == [cheap]
    assert len(await module.search_catalog("pizza", category="Pizza")) == 2


@pytest.mark.asyncio
async def test_search_open_now_filter_excludes_closed(monkeypatch):
    shut = restaurant("Pizza Shut", is_open_override=False)
    open_now = restaurant("Pizza Open")
    module, _ = patch_catalog(monkeypatch, [shut, open_now])

    assert await module.search_catalog("pizza") == [open_now, shut]
    assert await module.search_catalog("pizza", open_now=True) == [open_now]


@pytest.mark.asyncio
async def test_search_is_paginated_and_bounds_the_database_read(monkeypatch):
    shops = [restaurant(f"Pizza {i:02d}") for i in range(40)]
    module, query = patch_catalog(monkeypatch, shops)

    first = await module.search_catalog("pizza", limit=10)
    assert len(first) == 10
    second = await module.search_catalog("pizza", limit=10, offset=10)
    assert len(second) == 10
    assert {r.name for r in first}.isdisjoint({r.name for r in second})
    # The query itself is bounded — never an unbounded collection scan.
    assert query.limit_value is not None
    assert query.limit_value <= module.CANDIDATE_POOL


@pytest.mark.asyncio
async def test_restaurant_listing_is_paginated(monkeypatch):
    shops = [restaurant(f"Shop {i:02d}") for i in range(40)]
    module, query = patch_catalog(monkeypatch, shops)

    page = await module.list_restaurants(limit=5)
    assert len(page) == 5
    assert query.limit_value <= module.CANDIDATE_POOL

    # The default page size is bounded too, even with no arguments.
    assert len(await module.list_restaurants()) == module.DEFAULT_PAGE_SIZE


@pytest.mark.asyncio
async def test_listing_can_hide_closed_restaurants(monkeypatch):
    shut = restaurant("Shut", is_open_override=False)
    open_now = restaurant("Open")
    module, _ = patch_catalog(monkeypatch, [shut, open_now])

    assert len(await module.list_restaurants()) == 2
    assert await module.list_restaurants(open_now=True) == [open_now]
    assert await module.list_restaurants(include_closed=False) == [open_now]


# ── In-restaurant menu search ───────────────────────────────────────


@pytest.mark.asyncio
async def test_menu_search_is_typo_tolerant_and_best_match_first(monkeypatch):
    import app.catalog.router as module

    shop = restaurant(
        "Grill",
        menu=[
            item("Veggie Burger", description="grilled halloumi"),
            item("Beef Burger", description="classic"),
            item("Chips", category="Sides"),
        ],
    )
    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=shop))

    results = await module.search_restaurant_items("restaurant-1", "burgur")
    assert [i.name for i in results] == ["Beef Burger", "Veggie Burger"]

    # Description and category are searchable too.
    assert [i.name for i in await module.search_restaurant_items("r", "halloumi")] == [
        "Veggie Burger"
    ]
    assert [i.name for i in await module.search_restaurant_items("r", "sides")] == [
        "Chips"
    ]
    assert await module.search_restaurant_items("r", "sushi") == []


@pytest.mark.asyncio
async def test_menu_search_404s_on_a_missing_restaurant(monkeypatch):
    import app.catalog.router as module

    monkeypatch.setattr(module.Restaurant, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.search_restaurant_items("missing", "burger")
    assert exc.value.status_code == 404


# ── Nearby ──────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_nearby_is_bounded_ranked_and_paginated(monkeypatch):
    import app.location.service as module

    shops = [restaurant(f"Shop {i:02d}") for i in range(30)]
    query = Query(shops)
    monkeypatch.setattr(module.Restaurant, "find", lambda *a, **k: query)

    page = await module.LocationService.find_nearby_restaurants(
        -17.83, 31.05, radius_km=5, limit=10
    )
    assert len(page) == 10
    assert query.limit_value <= module.NEARBY_POOL
    assert page[0]._discovery["distance_km"] is not None


@pytest.mark.asyncio
async def test_nearby_can_exclude_closed_restaurants(monkeypatch):
    import app.location.service as module

    shut = restaurant("Shut", is_open_override=False)
    open_now = restaurant("Open")
    monkeypatch.setattr(module.Restaurant, "find", lambda *a, **k: Query([shut, open_now]))

    assert len(await module.LocationService.find_nearby_restaurants(-17.8, 31.0)) == 2
    only_open = await module.LocationService.find_nearby_restaurants(
        -17.8, 31.0, open_now=True
    )
    assert [r.name for r in only_open] == ["Open"]
