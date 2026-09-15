from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.order.state_machine import OrderState
from app.location.models import Location


class Field:
    def __eq__(self, value):
        return ("eq", value)

    def __ge__(self, value):
        return ("ge", value)

    def __gt__(self, value):
        return ("gt", value)

    def __lt__(self, value):
        return ("lt", value)

    def __neg__(self):
        return self


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


def user(id="user-1"):
    return SimpleNamespace(id=id)


@pytest.mark.asyncio
async def test_exchange_rates_cached_default_and_update(monkeypatch):
    import app.finance.router as module
    import app.finance.exchange as exchange_module

    class Redis:
        def __init__(self, cached=None):
            self.cached = cached
            self.get = AsyncMock(side_effect=lambda key: self.cached)
            self.set = AsyncMock()
            self.close = AsyncMock()

    # Publishing a rate now appends an immutable audit record before the cache
    # is touched, so stand in for the Beanie document (no database here).
    class FakeExchangeRate:
        written = []

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "rate-1"

        async def insert(self):
            FakeExchangeRate.written.append(self)
            return self

    monkeypatch.setattr(exchange_module, "ExchangeRate", FakeExchangeRate)

    default_redis = Redis()
    monkeypatch.setattr(module.aioredis, "from_url", lambda *args, **kwargs: default_redis)
    default = await module.get_exchange_rates()
    assert default.rates == module.DEFAULT_RATES
    default_redis.close.assert_awaited_once()
    # Provenance travels with the rates so a client can spot a stale quote.
    assert default.meta["ZIG"]["source"]
    assert default.meta["USD"]["is_stale"] is False

    cached_redis = Redis('{"ZIG": 14.0}')
    monkeypatch.setattr(module.aioredis, "from_url", lambda *args, **kwargs: cached_redis)
    cached = await module.get_exchange_rates()
    assert cached.rates["ZIG"] == 14.0
    updated = await module.update_exchange_rate("zar", 19.0, "token")
    assert updated["rates"]["ZAR"] == 19.0
    assert updated["published"]["source"] == "manual"
    # Rates are persisted as exact integer micro-units, never floats.
    assert FakeExchangeRate.written[-1].rate_micros == 19_000_000
    assert cached_redis.set.await_count >= 1

    fresh_redis = Redis()
    monkeypatch.setattr(module.aioredis, "from_url", lambda *args, **kwargs: fresh_redis)
    assert (await module.update_exchange_rate("zig", 15.0, "token"))["rates"]["ZIG"] == 15.0


@pytest.mark.asyncio
async def test_merchant_analytics(monkeypatch):
    import app.finance.router as module

    now = datetime.now()
    delivered = SimpleNamespace(total_amount=20.13)
    history = SimpleNamespace(
        events=[
            SimpleNamespace(state=OrderState.ACCEPTED, timestamp=now),
            SimpleNamespace(state=OrderState.PICKED_UP, timestamp=now + timedelta(minutes=20)),
        ]
    )

    class FakeOrder:
        merchant_id = Field()
        state = Field()
        updated_at = Field()
        created_at = Field()
        queue = []

        @classmethod
        def find(cls, *args):
            return cls.queue.pop(0)

    # Orders key on a RESTAURANT id, so the handler resolves the merchant's
    # restaurants first and queries on those. Comparing Order.merchant_id to a
    # merchant user id matches nothing -- which is what it used to do.
    owned_restaurant = SimpleNamespace(
        id="restaurant-1",
        menu=[
            SimpleNamespace(is_available=True),
            SimpleNamespace(is_available=False),
        ],
    )

    class FakeRestaurant:
        merchant_id = Field()
        queue = []

        @classmethod
        def find(cls, *args):
            return cls.queue.pop(0)

    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(module, "Restaurant", FakeRestaurant)
    with pytest.raises(HTTPException) as exc:
        await module.get_merchant_analytics("merchant", user("other"))
    assert exc.value.status_code == 403

    FakeRestaurant.queue = [Query([owned_restaurant])]
    FakeOrder.queue = [
        Query([delivered]), Query(count=3), Query([delivered, delivered]), Query([history])
    ]
    result = await module.get_merchant_analytics("merchant", user("merchant"))
    assert result == {
        "today_orders": 1, "today_gmv": 20.13, "today_gmv_minor": 2013,
        "total_orders": 3, "total_gmv": 40.26, "total_gmv_minor": 4026,
        "active_items": 1, "avg_prep_time": 20.0,
    }

    # A merchant with no restaurant has nothing to measure. avg_prep_time is
    # None rather than the old hardcoded 18, which reported a prep time for a
    # kitchen that had never completed an order.
    FakeRestaurant.queue = [Query([])]
    result = await module.get_merchant_analytics("merchant", user("merchant"))
    assert result["active_items"] == 0
    assert result["avg_prep_time"] is None
    assert result["today_orders"] == 0

    # Restaurant exists but nothing has reached PICKED_UP yet.
    FakeRestaurant.queue = [Query([owned_restaurant])]
    no_events = SimpleNamespace(events=[SimpleNamespace(state=OrderState.CREATED, timestamp=now)])
    FakeOrder.queue = [Query([]), Query(count=0), Query([]), Query([no_events])]
    result = await module.get_merchant_analytics("merchant", user("merchant"))
    assert result["avg_prep_time"] is None


def earning(**overrides):
    values = {
        "id": "earning-1",
        "order_id": "order-1",
        "merchant_name": "Pizza Place",
        "pickup_area": "** Main Road",
        "dropoff_area": "** Oak Street",
        "delivery_fee_cents": 300,
        "driver_earning_cents": 255,
        "tip_cents": 100,
        "total_earning_cents": 355,
        "payment_method": "cash",
        "distance_km": 4.2,
        "completed_at": datetime.now(),
        "created_date": "2026-08-09",
    }
    values.update(overrides)
    return SimpleNamespace(**values)


class FakeEarning:
    driver_id = Field()
    order_id = Field()
    completed_at = Field()
    payment_method = Field()
    total_earning_cents = Field()
    found = []
    queues = []
    existing = None
    created = []

    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)
        self.id = "new-earning"
        self.insert = AsyncMock(side_effect=lambda: self.created.append(self))

    @classmethod
    def find(cls, *args):
        if cls.queues:
            return cls.queues.pop(0)
        return Query(cls.found)

    @classmethod
    async def find_one(cls, *args):
        return cls.existing


@pytest.mark.asyncio
async def test_driver_earnings_summary_daily_and_history(monkeypatch):
    import app.finance.router as module
    import app.finance.models as models

    monkeypatch.setattr(models, "DriverEarning", FakeEarning)
    with pytest.raises(HTTPException):
        await module.get_driver_earnings("driver", user("other"))

    today = [earning(), earning(payment_method="ecocash", total_earning_cents=500, tip_cents=0)]
    week = today + [earning(id="earning-3", total_earning_cents=200, tip_cents=20)]
    FakeEarning.queues = [Query(today), Query(week)]
    summary = await module.get_driver_earnings("driver", user("driver"))
    assert summary["today_deliveries"] == 2
    assert summary["week_earnings_cents"] == 1055
    assert summary["cash_on_hand_cents"] == 355

    with pytest.raises(HTTPException):
        await module.get_daily_breakdown("driver", 30, user("other"))
    FakeEarning.found = [earning(), earning(total_earning_cents=100, tip_cents=0), earning(
        created_date="2026-08-08", payment_method="ecocash", total_earning_cents=200
    )]
    daily = await module.get_daily_breakdown("driver", 30, user("driver"))
    assert daily[0]["trip_count"] == 2
    assert daily[0]["cash_collected_cents"] == 455

    with pytest.raises(HTTPException):
        await module.get_earnings_history("driver", current_user=user("other"))
    FakeEarning.found = [
        earning(), earning(id="earning-2", merchant_name="Other", pickup_area="West", dropoff_area="East")
    ]
    history = await module.get_earnings_history(
        "driver", start_date="2026-01-01", end_date="2026-12-31",
        payment_method="CASH", min_amount_cents=100, merchant_name="pizza",
        area="main", page=1, page_size=20, current_user=user("driver"),
    )
    assert history["total"] == 2
    assert len(history["records"]) == 1
    assert history["records"][0]["completed_at"]

    history = await module.get_earnings_history(
        "driver", start_date="bad", end_date="bad", payment_method=None,
        min_amount_cents=None, merchant_name=None, area="oak", page=1,
        page_size=20, current_user=user("driver"),
    )
    assert len(history["records"]) == 1


@pytest.mark.asyncio
async def test_record_earning_all_paths(monkeypatch):
    import app.finance.router as module
    import app.finance.models as models
    import app.catalog.models as catalog_models
    import app.payment.models as payment_models

    monkeypatch.setattr(models, "DriverEarning", FakeEarning)
    FakeEarning.existing = earning()
    duplicate = await module.record_earning("order-1", "driver-1", user("driver-1"))
    assert duplicate["status"] == "already_recorded"

    # Ownership check: cannot record for another driver.
    with pytest.raises(HTTPException) as exc:
        await module.record_earning("order-1", "driver-1", user("other"))
    assert exc.value.status_code == 403

    FakeEarning.existing = None

    class FakeOrder:
        get = AsyncMock(return_value=None)

    monkeypatch.setattr(module, "Order", FakeOrder)
    assert (await module.record_earning("missing", "driver-1", user("driver-1")))["status"] == "error"

    current_order = SimpleNamespace(
        merchant_id="merchant-1", pickup_location=Location.from_lat_lng(-17.0, 31.0),
        dropoff_location=Location.from_lat_lng(-17.1, 31.1), delivery_fee=3.0,
        tip_amount=1.0, delivery_instructions="14 Main Road",
    )
    FakeOrder.get.return_value = current_order

    class FakeRestaurant:
        merchant_id = Field()
        find_one = AsyncMock(return_value=None)
        get = AsyncMock(return_value=SimpleNamespace(name="Restaurant", address="123B Market Street"))

    class FakePayment:
        order_id = Field()
        find_one = AsyncMock(return_value=SimpleNamespace(method=SimpleNamespace(value="ECOCASH")))

    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    monkeypatch.setattr(payment_models, "Payment", FakePayment)
    FakeEarning.created = []
    recorded = await module.record_earning("order-1", "driver-1", user("driver-1"))
    assert recorded["status"] == "recorded"
    assert FakeEarning.created[-1].merchant_name == "Restaurant"
    assert FakeEarning.created[-1].pickup_area == "** Market Street"
    assert FakeEarning.created[-1].payment_method == "ecocash"

    current_order.delivery_fee = 0
    current_order.tip_amount = 0
    current_order.delivery_instructions = ""
    FakeRestaurant.find_one.return_value = SimpleNamespace(name="Direct", address="")
    FakePayment.find_one.return_value = None
    recorded = await module.record_earning("order-2", "driver-1", user("driver-1"))
    assert recorded["tip_cents"] == 0
    assert FakeEarning.created[-1].payment_method == "cash"

    FakeRestaurant.find_one.side_effect = RuntimeError("restaurant db")
    FakePayment.find_one.side_effect = RuntimeError("payment db")
    recorded = await module.record_earning("order-3", "driver-1", user("driver-1"))
    assert recorded["status"] == "recorded"
    assert FakeEarning.created[-1].merchant_name == "Unknown"


def test_mask_address_edges():
    from app.finance.models import mask_address

    assert mask_address("") == ""
    assert mask_address("  123B Main Road ") == "** Main Road"
    assert mask_address("Main Road") == "Main Road"
