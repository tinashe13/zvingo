"""Exchange rates: pinned to the order, auditable, and never silently stale."""

from datetime import timedelta
from decimal import Decimal

import pytest

from app.finance import exchange
from app.finance.money import MoneyError
from app.time_utils import utc_now


class FakeRedis:
    def __init__(self, values=None):
        self.values = dict(values or {})
        self.closed = 0

    async def get(self, key):
        return self.values.get(key)

    async def set(self, key, value, ex=None):
        self.values[key] = value

    async def close(self):
        self.closed += 1


@pytest.fixture
def redis(monkeypatch):
    fake = FakeRedis()
    monkeypatch.setattr(exchange.aioredis, "from_url", lambda *a, **k: fake)
    return fake


@pytest.fixture
def audit(monkeypatch):
    written = []

    class FakeExchangeRate:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = f"rate-{len(written) + 1}"

        async def insert(self):
            written.append(self)
            return self

    monkeypatch.setattr(exchange, "ExchangeRate", FakeExchangeRate)
    return written


@pytest.fixture
def locks(monkeypatch):
    rows = []

    class FakeLock:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = f"lock-{len(rows) + 1}"
            self.locked_at = kwargs.get("locked_at") or utc_now()

        @property
        def rate(self):
            return Decimal(self.rate_micros) / exchange.RATE_SCALE

        async def insert(self):
            rows.append(self)
            return self

    async def find_one(order_id, currency):
        for row in rows:
            if row.order_id == order_id and row.currency == currency:
                return row
        return None

    monkeypatch.setattr(exchange, "OrderRateLock", FakeLock)
    monkeypatch.setattr(exchange, "get_order_rate_lock", find_one)
    return rows


# ── representation ──────────────────────────────────────────────────


def test_rates_are_stored_as_exact_integer_micro_units():
    assert exchange.to_micros(13.5) == 13_500_000
    assert exchange.to_micros("13.456789") == 13_456_789
    assert exchange.to_micros(Decimal("1")) == 1_000_000
    # A float that is not exactly representable still round-trips.
    assert exchange.to_micros(0.1) == 100_000


def test_conversion_uses_bankers_rounding_and_rejects_unknown_currencies():
    assert exchange.convert_minor(1000, Decimal("13.5"), "ZIG") == 13500
    # 3 * 1.5 = 4.5 -> 4 (even)
    assert exchange.convert_minor(3, Decimal("1.5"), "ZIG") == 4
    # 5 * 1.5 = 7.5 -> 8 (even)
    assert exchange.convert_minor(5, Decimal("1.5"), "ZIG") == 8
    with pytest.raises(MoneyError):
        exchange.convert_minor(1000, Decimal("1"), "GBP")


# ── staleness ───────────────────────────────────────────────────────


def test_usd_is_never_stale_and_a_dated_rate_ages():
    usd = exchange.RateQuote("USD", Decimal(1), "base", effective_at=None)
    assert usd.is_stale is False

    fresh = exchange.RateQuote("ZIG", Decimal("13.5"), "manual", effective_at=utc_now())
    assert fresh.is_stale is False
    assert fresh.age_seconds < 5

    old = exchange.RateQuote(
        "ZIG", Decimal("13.5"), "manual",
        effective_at=utc_now() - timedelta(seconds=exchange.max_rate_age_seconds() + 60),
    )
    assert old.is_stale is True

    # A rate nobody has ever published has no age and counts as stale.
    undated = exchange.RateQuote("ZIG", Decimal("13.5"), "seed-default")
    assert undated.age_seconds is None
    assert undated.is_stale is True

    # A rate pinned to an order is frozen on purpose and never reads as stale.
    pinned = exchange.RateQuote(
        "ZIG", Decimal("13.5"), "manual",
        effective_at=utc_now() - timedelta(days=7), pinned=True,
    )
    assert pinned.is_stale is False
    assert pinned.as_dict()["pinned"] is True


# ── resolution ──────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_usd_short_circuits(redis):
    quote = await exchange.get_rate("usd")
    assert quote.rate == Decimal(1)
    assert quote.source == "base"


@pytest.mark.asyncio
async def test_rate_resolution_prefers_the_meta_cache(redis, audit):
    await exchange.record_rate("ZIG", "14.25", source="rbz", set_by="admin-1")
    assert audit[-1].rate_micros == 14_250_000
    assert audit[-1].source == "rbz"
    assert audit[-1].set_by == "admin-1"

    quote = await exchange.get_rate("zig")
    assert quote.rate == Decimal("14.25")
    assert quote.source == "rbz"
    assert quote.is_stale is False


@pytest.mark.asyncio
async def test_legacy_redis_keys_still_resolve(redis):
    redis.values["exchange_rate:ZAR"] = "18.75"
    quote = await exchange.get_rate("ZAR")
    assert quote.rate == Decimal("18.75")
    assert quote.source == "redis-legacy"

    redis.values.clear()
    redis.values["exchange_rates"] = '{"ZAR": 19.0}'
    quote = await exchange.get_rate("ZAR")
    assert quote.rate == Decimal("19.0")
    assert quote.source == "redis-legacy-map"


@pytest.mark.asyncio
async def test_a_seed_rate_is_returned_but_marked_stale(redis):
    quote = await exchange.get_rate("ZIG")
    assert quote.rate == Decimal("13.50")
    assert quote.source == "seed-default"
    assert quote.is_stale is True


@pytest.mark.asyncio
async def test_malformed_cache_payloads_do_not_break_resolution(redis):
    redis.values["exchange_rates:meta"] = "not json"
    redis.values["exchange_rates"] = "also not json"
    quote = await exchange.get_rate("ZIG")
    assert quote.source == "seed-default"


# ── publication ─────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_publishing_a_rate_rejects_nonsense(redis, audit):
    with pytest.raises(exchange.UnsupportedCurrencyError):
        await exchange.record_rate("GBP", 1.3)
    with pytest.raises(exchange.UnsupportedCurrencyError):
        await exchange.record_rate("", 1.3)
    with pytest.raises(MoneyError):
        await exchange.record_rate("ZIG", 0)
    with pytest.raises(MoneyError):
        await exchange.record_rate("ZIG", -5)
    # USD is the base unit; it cannot be repriced against itself.
    with pytest.raises(MoneyError):
        await exchange.record_rate("USD", 1.1)
    assert audit == []


@pytest.mark.asyncio
async def test_publishing_refreshes_both_the_new_and_legacy_caches(redis, audit):
    await exchange.record_rate("ZIG", "14.00")
    assert "exchange_rates:meta" in redis.values
    assert redis.values["exchange_rate:ZIG"] == "14.00"
    assert '"ZIG"' in redis.values["exchange_rates"]


# ── pinning to the order ────────────────────────────────────────────


@pytest.mark.asyncio
async def test_the_rate_is_pinned_at_first_use_and_never_moves(redis, audit, locks):
    await exchange.record_rate("ZIG", "13.50")

    first = await exchange.resolve_rate_for_order("ZIG", "order-1")
    assert first.rate == Decimal("13.50")
    assert first.pinned is True
    assert len(locks) == 1

    # The market moves hard mid-order.
    await exchange.record_rate("ZIG", "27.00")
    assert (await exchange.get_rate("ZIG")).rate == Decimal("27.00")

    # The order still owes what it owed.
    again = await exchange.resolve_rate_for_order("ZIG", "order-1")
    assert again.rate == Decimal("13.50")
    assert again.pinned is True
    assert len(locks) == 1

    # A different order gets the new rate.
    other = await exchange.resolve_rate_for_order("ZIG", "order-2")
    assert other.rate == Decimal("27.00")
    assert len(locks) == 2


@pytest.mark.asyncio
async def test_resolution_without_an_order_pins_nothing(redis, audit, locks):
    await exchange.record_rate("ZIG", "13.50")
    quote = await exchange.resolve_rate_for_order("ZIG")
    assert quote.pinned is False
    assert locks == []


@pytest.mark.asyncio
async def test_a_concurrent_pin_loses_gracefully(redis, audit, monkeypatch, locks):
    await exchange.record_rate("ZIG", "13.50")
    winner = await exchange.resolve_rate_for_order("ZIG", "order-1")

    class Clashing(exchange.OrderRateLock):
        async def insert(self):
            raise RuntimeError("duplicate key")

    monkeypatch.setattr(exchange, "OrderRateLock", Clashing)
    await exchange.record_rate("ZIG", "99.00")
    loser = await exchange.resolve_rate_for_order("ZIG", "order-1")
    assert loser.rate == winner.rate


# ── production safety ───────────────────────────────────────────────


@pytest.mark.asyncio
async def test_production_refuses_a_stale_rate(redis, audit, locks, monkeypatch):
    monkeypatch.setattr(exchange, "_is_production", lambda: True)
    with pytest.raises(exchange.StaleExchangeRateError) as exc:
        await exchange.resolve_rate_for_order("ZIG", "order-1")
    assert "stale" in str(exc.value)
    assert "POST /finance/rates" in str(exc.value)
    assert locks == []

    # Publish a fresh rate and it goes through.
    await exchange.record_rate("ZIG", "13.50")
    quote = await exchange.resolve_rate_for_order("ZIG", "order-1")
    assert quote.rate == Decimal("13.50")


@pytest.mark.asyncio
async def test_production_refuses_an_unsupported_currency(redis, audit, locks, monkeypatch):
    monkeypatch.setattr(exchange, "_is_production", lambda: True)
    with pytest.raises(exchange.UnsupportedCurrencyError):
        await exchange.resolve_rate_for_order("GBP", "order-1")


@pytest.mark.asyncio
async def test_development_warns_but_keeps_working(redis, audit, locks, monkeypatch):
    monkeypatch.setattr(exchange, "_is_production", lambda: False)
    quote = await exchange.resolve_rate_for_order("ZIG", "order-1")
    assert quote.rate == Decimal("13.50")
    assert quote.pinned is True

    unknown = await exchange.resolve_rate_for_order("GBP", "order-2")
    assert unknown.rate == Decimal(1)


@pytest.mark.asyncio
async def test_usd_is_usable_in_production_without_any_published_rate(redis, monkeypatch, locks):
    monkeypatch.setattr(exchange, "_is_production", lambda: True)
    quote = await exchange.resolve_rate_for_order("USD", "order-1")
    assert quote.rate == Decimal(1)
    # Nothing to pin: the base currency's rate is 1 by definition.
    assert locks == []


# ── the cached-payload view used by GET /finance/rates ──────────────


def test_quotes_from_cache_payload_is_defensive():
    quotes = exchange.quotes_from_cache_payload(
        {"ZAR": 18.5, "BAD": "x"},
        {"ZIG": {"rate": "14.0", "effective_at": utc_now().isoformat(), "source": "rbz"},
         "JUNK": 3, "WORSE": {"no_rate": 1}},
    )
    assert quotes["ZIG"].rate == Decimal("14.0")
    assert quotes["ZIG"].is_stale is False
    assert quotes["ZAR"].rate == Decimal("18.5")
    assert "JUNK" not in quotes
    assert "WORSE" not in quotes
    assert "BAD" not in quotes
    # Every supported currency is always present, even with an empty cache.
    assert set(exchange.quotes_from_cache_payload(None, None)) == set(exchange.SEED_RATES)
    assert exchange.quotes_from_cache_payload({}, {})["USD"].is_stale is False
