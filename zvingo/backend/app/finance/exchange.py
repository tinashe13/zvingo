"""Exchange rates: auditable, pinned to the order, never silently stale.

Zimbabwe runs a hard-currency economy with a volatile local unit. A ZIG rate
can move materially within a day, so three properties matter:

1. **Pinned at order time.** The rate that converts an order's USD price into
   the charged currency is captured once, in an :class:`OrderRateLock`, and
   reused for every subsequent quote, retry, status poll and refund of that
   order. A rate move mid-order can never change what the customer owes.
2. **Auditable.** Every rate an admin posts is appended to
   :class:`ExchangeRate` with the value, the source, who set it and when it
   became effective. Rates are stored as integer micro-units (1e-6), never
   floats.
3. **Never silently stale.** A quote carries its age. In production a rate
   older than ``EXCHANGE_RATE_MAX_AGE_SECONDS`` — or a built-in seed default
   that nobody has ever refreshed — raises :class:`StaleExchangeRateError`
   rather than quietly charging at yesterday's number.

USD is the base currency: its rate is exactly 1 and is never stale.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from decimal import ROUND_HALF_EVEN, Decimal, localcontext
from typing import Dict, List, Optional

import redis.asyncio as aioredis
import structlog
from beanie import Document, Indexed
from pydantic import Field
from pymongo import IndexModel

from app.config import settings
from app.finance.money import (
    DEFAULT_CURRENCY,
    MoneyError,
    currency_spec,
    is_supported_currency,
    to_decimal,
)
from app.time_utils import ensure_utc, utc_now, utc_now_aware

logger = structlog.get_logger()

__all__ = [
    "quotes_from_cache_payload",
    "META_CACHE_KEY",
    "LEGACY_MAP_KEY",
    "ExchangeRate",
    "OrderRateLock",
    "RateQuote",
    "StaleExchangeRateError",
    "UnsupportedCurrencyError",
    "SEED_RATES",
    "RATE_SCALE",
    "record_rate",
    "get_rate",
    "resolve_rate_for_order",
    "get_order_rate_lock",
    "convert_minor",
    "current_rates_map",
    "max_rate_age_seconds",
]

# Rates are held as integers scaled by 1e6 — six decimal places is far more
# precision than any published ZIG/ZAR quote and is exact in BSON.
RATE_SCALE = Decimal(10) ** 6

# Seed values so a fresh development environment works out of the box. These
# are NOT usable for charging in production: they carry no effective_at, so
# resolve_rate_for_order() rejects them there.
SEED_RATES: Dict[str, Decimal] = {
    "USD": Decimal("1"),
    "ZIG": Decimal("13.50"),
    "ZAR": Decimal("18.50"),
}

DEFAULT_MAX_RATE_AGE_SECONDS = 6 * 60 * 60  # 6 hours

META_CACHE_KEY = "exchange_rates:meta"
LEGACY_MAP_KEY = "exchange_rates"

# Internal aliases kept short at call sites.
_META_CACHE_KEY = META_CACHE_KEY
_LEGACY_MAP_KEY = LEGACY_MAP_KEY


class StaleExchangeRateError(RuntimeError):
    """The only rate available is too old (or never set) to charge against."""


class UnsupportedCurrencyError(ValueError):
    """A currency Zvingo does not settle in."""


def max_rate_age_seconds() -> int:
    return int(
        getattr(settings, "EXCHANGE_RATE_MAX_AGE_SECONDS", DEFAULT_MAX_RATE_AGE_SECONDS)
    )


def _is_production() -> bool:
    return getattr(settings, "ENVIRONMENT", "development") == "production"


class ExchangeRate(Document):
    """Append-only audit record of one published rate.

    ``rate_micros`` is how many minor units of ``currency`` one unit of ``base``
    buys, scaled by 1e6. For ZIG at 13.50/USD, ``rate_micros == 13_500_000``.
    """

    currency: Indexed(str)  # type: ignore
    base: str = DEFAULT_CURRENCY
    rate_micros: int

    effective_at: datetime = Field(default_factory=utc_now)
    source: str = "manual"       # "manual" | "rbz" | "seed" | integration name
    set_by: Optional[str] = None  # admin user id
    created_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "exchange_rates"
        indexes = [[("currency", 1), ("effective_at", -1)]]

    @property
    def rate(self) -> Decimal:
        return Decimal(self.rate_micros) / RATE_SCALE


class OrderRateLock(Document):
    """The rate pinned to one order, in one currency. Written once, never updated."""

    order_id: Indexed(str)  # type: ignore
    currency: str
    base: str = DEFAULT_CURRENCY
    rate_micros: int

    rate_effective_at: Optional[datetime] = None
    source: str = "manual"
    locked_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "order_rate_locks"
        # Unique: the pin is what guarantees an order's rate cannot move, so
        # two concurrent quotes for the same order must not create two locks.
        # `_pin` relies on the duplicate-key failure to fall back to the winner.
        indexes = [
            IndexModel(
                [("order_id", 1), ("currency", 1)],
                name="order_rate_lock_unique",
                unique=True,
            )
        ]

    @property
    def rate(self) -> Decimal:
        return Decimal(self.rate_micros) / RATE_SCALE


@dataclass(frozen=True)
class RateQuote:
    """A rate with everything needed to judge whether it may be used."""

    currency: str
    rate: Decimal
    source: str
    effective_at: Optional[datetime] = None
    locked_at: Optional[datetime] = None
    pinned: bool = False

    @property
    def age_seconds(self) -> Optional[float]:
        """Seconds since the rate became effective, or ``None`` if undated.

        Stored timestamps are naive UTC while anything parsed off the wire may
        be aware; ``ensure_utc`` normalises both so the subtraction can never
        raise.
        """
        if self.effective_at is None:
            return None
        return (utc_now_aware() - ensure_utc(self.effective_at)).total_seconds()

    @property
    def is_stale(self) -> bool:
        """USD is never stale; an undated or over-age rate is."""
        if self.currency == DEFAULT_CURRENCY:
            return False
        if self.pinned:
            # A pinned rate is intentionally frozen for this order's lifetime.
            return False
        age = self.age_seconds
        if age is None:
            return True
        return age > max_rate_age_seconds()

    def as_dict(self) -> dict:
        return {
            "currency": self.currency,
            "rate": float(self.rate),
            "source": self.source,
            "effective_at": self.effective_at.isoformat() if self.effective_at else None,
            "locked_at": self.locked_at.isoformat() if self.locked_at else None,
            "pinned": self.pinned,
            "age_seconds": self.age_seconds,
            "is_stale": self.is_stale,
        }


def _normalise(currency: str) -> str:
    code = (currency or "").strip().upper()
    if not code:
        raise UnsupportedCurrencyError("currency is required")
    return code


def to_micros(rate: object) -> int:
    with localcontext() as ctx:
        ctx.prec = 34
        value = to_decimal(rate) * RATE_SCALE
        return int(value.quantize(Decimal(1), rounding=ROUND_HALF_EVEN))


def convert_minor(amount_minor: int, rate: Decimal, target_currency: str) -> int:
    """Convert a USD minor-unit amount into ``target_currency`` minor units.

    Both currencies use the same exponent in this market, so the conversion is
    a straight multiply; banker's rounding keeps repeated conversions unbiased.
    """
    currency_spec(target_currency)
    with localcontext() as ctx:
        ctx.prec = 34
        converted = Decimal(int(amount_minor)) * to_decimal(rate)
        return int(converted.quantize(Decimal(1), rounding=ROUND_HALF_EVEN))


async def _redis():
    return aioredis.from_url(settings.REDIS_URL, decode_responses=True)


async def record_rate(
    currency: str,
    rate: object,
    *,
    source: str = "manual",
    set_by: Optional[str] = None,
    effective_at: Optional[datetime] = None,
) -> RateQuote:
    """Publish a new rate: append the audit record, then refresh the cache.

    The audit record is written first so a cache write that fails can never
    leave a rate in use that has no provenance.
    """
    code = _normalise(currency)
    if not is_supported_currency(code):
        raise UnsupportedCurrencyError(
            f"Unsupported currency {code!r}; supported: {sorted(SEED_RATES)}"
        )
    value = to_decimal(rate)
    if value <= 0:
        raise MoneyError("Exchange rate must be positive")
    if code == DEFAULT_CURRENCY and value != Decimal(1):
        raise MoneyError("USD is the base currency; its rate is fixed at 1")

    when = effective_at or utc_now()
    record = ExchangeRate(
        currency=code,
        rate_micros=to_micros(value),
        effective_at=when,
        source=source,
        set_by=set_by,
    )
    await record.insert()

    await _write_cache(code, value, when, source)
    logger.info(
        "Exchange rate published",
        currency=code,
        rate=str(value),
        source=source,
        set_by=set_by,
    )
    return RateQuote(currency=code, rate=value, source=source, effective_at=when)


async def _write_cache(
    code: str, value: Decimal, effective_at: datetime, source: str
) -> None:
    """Refresh both the rich meta cache and the legacy float map/key."""
    r = await _redis()
    try:
        raw_meta = await r.get(_META_CACHE_KEY)
        meta = json.loads(raw_meta) if raw_meta else {}
        meta[code] = {
            "rate": str(value),
            "effective_at": effective_at.isoformat(),
            "source": source,
        }
        await r.set(_META_CACHE_KEY, json.dumps(meta))

        raw_map = await r.get(_LEGACY_MAP_KEY)
        rates = json.loads(raw_map) if raw_map else {}
        rates[code] = float(value)
        await r.set(_LEGACY_MAP_KEY, json.dumps(rates), ex=3600)
        await r.set(f"exchange_rate:{code}", str(value), ex=3600)
    finally:
        await r.close()


async def _quote_from_cache(code: str) -> Optional[RateQuote]:
    r = await _redis()
    try:
        raw_meta = await r.get(_META_CACHE_KEY)
        if raw_meta:
            try:
                meta = json.loads(raw_meta)
            except (TypeError, ValueError):
                meta = {}
            entry = meta.get(code)
            if entry:
                effective = entry.get("effective_at")
                return RateQuote(
                    currency=code,
                    rate=to_decimal(entry["rate"]),
                    source=entry.get("source", "cache"),
                    effective_at=_parse_dt(effective),
                )

        legacy = await r.get(f"exchange_rate:{code}")
        if legacy:
            # Operator-set legacy key. Redis expires it after an hour, so it is
            # bounded in age even without an explicit effective_at.
            return RateQuote(
                currency=code,
                rate=to_decimal(legacy),
                source="redis-legacy",
                effective_at=utc_now(),
            )

        raw_map = await r.get(_LEGACY_MAP_KEY)
        if raw_map:
            try:
                rates = json.loads(raw_map)
            except (TypeError, ValueError):
                rates = {}
            if code in rates:
                return RateQuote(
                    currency=code,
                    rate=to_decimal(rates[code]),
                    source="redis-legacy-map",
                    effective_at=utc_now(),
                )
    finally:
        await r.close()
    return None


def _parse_dt(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except (TypeError, ValueError):
        return None


async def _quote_from_db(code: str) -> Optional[RateQuote]:
    try:
        record = (
            await ExchangeRate.find(ExchangeRate.currency == code)
            .sort(-ExchangeRate.effective_at)
            .limit(1)
            .to_list()
        )
    except Exception as exc:  # collection not initialised in unit tests
        logger.debug("Exchange rate lookup unavailable", error=str(exc))
        return None
    if not record:
        return None
    row = record[0]
    return RateQuote(
        currency=code,
        rate=row.rate,
        source=row.source,
        effective_at=row.effective_at,
    )


async def get_rate(currency: str) -> RateQuote:
    """Best available quote for ``currency``, with its provenance and age.

    Resolution order: USD short-circuit → Redis meta cache → legacy Redis keys
    → newest :class:`ExchangeRate` record → built-in seed. The caller decides
    whether the quote is good enough; :func:`resolve_rate_for_order` is the one
    that enforces it.
    """
    code = _normalise(currency)
    if code == DEFAULT_CURRENCY:
        return RateQuote(
            currency=code, rate=Decimal(1), source="base", effective_at=utc_now()
        )

    quote = await _quote_from_cache(code)
    if quote is not None:
        return quote

    quote = await _quote_from_db(code)
    if quote is not None:
        return quote

    seed = SEED_RATES.get(code)
    if seed is not None:
        # effective_at deliberately None: a seed has never been published, so
        # it reads as stale and cannot be used to charge in production.
        return RateQuote(currency=code, rate=seed, source="seed-default")

    return RateQuote(currency=code, rate=Decimal(1), source="unknown-currency")


async def get_order_rate_lock(order_id: str, currency: str) -> Optional[OrderRateLock]:
    code = _normalise(currency)
    try:
        return await OrderRateLock.find_one(
            OrderRateLock.order_id == order_id, OrderRateLock.currency == code
        )
    except Exception as exc:  # collection not initialised in unit tests
        logger.debug("Rate lock lookup unavailable", error=str(exc))
        return None


async def resolve_rate_for_order(
    currency: str, order_id: Optional[str] = None
) -> RateQuote:
    """The rate that applies to ``order_id``, pinning it on first use.

    * If the order already has a lock for this currency, that pinned rate is
      returned unchanged — no matter how far the market has moved.
    * Otherwise the current rate is resolved, **checked for staleness**, and
      written as the order's lock.
    * In production an unusable rate (undated seed, over-age, unsupported
      currency) raises rather than charging the customer at a guess. Outside
      production it is allowed with a loud warning so development keeps working.
    """
    code = _normalise(currency)

    if order_id:
        lock = await get_order_rate_lock(order_id, code)
        if lock is not None:
            return RateQuote(
                currency=code,
                rate=lock.rate,
                source=lock.source,
                effective_at=lock.rate_effective_at,
                locked_at=lock.locked_at,
                pinned=True,
            )

    quote = await get_rate(code)

    if not is_supported_currency(code):
        message = f"Unsupported settlement currency {code!r}"
        if _is_production():
            raise UnsupportedCurrencyError(message)
        logger.warning(
            "Unsupported currency used outside production; charging 1:1",
            currency=code,
        )
    elif quote.is_stale:
        age = quote.age_seconds
        message = (
            f"Exchange rate for {code} is stale (source={quote.source}, "
            f"age={'unknown' if age is None else int(age)}s, "
            f"limit={max_rate_age_seconds()}s). Publish a fresh rate via "
            f"POST /finance/rates before charging in {code}."
        )
        if _is_production():
            raise StaleExchangeRateError(message)
        logger.warning("Stale exchange rate used outside production", detail=message)

    if order_id:
        quote = await _pin(order_id, quote)
    return quote


async def _pin(order_id: str, quote: RateQuote) -> RateQuote:
    """Write the order's rate lock; if one was created concurrently, use that."""
    lock = OrderRateLock(
        order_id=order_id,
        currency=quote.currency,
        rate_micros=to_micros(quote.rate),
        rate_effective_at=quote.effective_at,
        source=quote.source,
    )
    try:
        await lock.insert()
    except Exception as exc:
        existing = await get_order_rate_lock(order_id, quote.currency)
        if existing is not None:
            return RateQuote(
                currency=quote.currency,
                rate=existing.rate,
                source=existing.source,
                effective_at=existing.rate_effective_at,
                locked_at=existing.locked_at,
                pinned=True,
            )
        logger.warning(
            "Could not pin exchange rate to order", order_id=order_id, error=str(exc)
        )
        return quote

    logger.info(
        "Exchange rate pinned to order",
        order_id=order_id,
        currency=quote.currency,
        rate=str(quote.rate),
        source=quote.source,
    )
    return RateQuote(
        currency=quote.currency,
        rate=quote.rate,
        source=quote.source,
        effective_at=quote.effective_at,
        locked_at=lock.locked_at,
        pinned=True,
    )


def quotes_from_cache_payload(
    rates: Optional[dict], meta: Optional[dict]
) -> Dict[str, RateQuote]:
    """Build quotes from an already-fetched cache payload.

    Pure, so the ``/finance/rates`` endpoint can serve provenance from the one
    Redis round trip it already makes instead of opening a fresh connection per
    currency. Malformed cache entries (a bare number where a dict is expected,
    for instance) are skipped rather than raising — a rates endpoint must not
    500 because a cached value is the wrong shape.
    """
    quotes: Dict[str, RateQuote] = {}
    meta = meta if isinstance(meta, dict) else {}
    rates = rates if isinstance(rates, dict) else {}

    for code, entry in meta.items():
        if not isinstance(entry, dict) or "rate" not in entry:
            continue
        try:
            quotes[str(code).upper()] = RateQuote(
                currency=str(code).upper(),
                rate=to_decimal(entry["rate"]),
                source=entry.get("source", "cache"),
                effective_at=_parse_dt(entry.get("effective_at")),
            )
        except Exception:
            continue

    for code, value in rates.items():
        key = str(code).upper()
        if key in quotes:
            continue
        try:
            quotes[key] = RateQuote(
                currency=key,
                rate=to_decimal(value),
                source="redis-legacy-map",
                effective_at=utc_now(),
            )
        except Exception:
            continue

    for code, seed in SEED_RATES.items():
        quotes.setdefault(
            code,
            RateQuote(
                currency=code,
                rate=Decimal(1) if code == DEFAULT_CURRENCY else seed,
                source="base" if code == DEFAULT_CURRENCY else "seed-default",
                effective_at=utc_now() if code == DEFAULT_CURRENCY else None,
            ),
        )
    return quotes


async def current_rates_map() -> Dict[str, RateQuote]:
    """A quote per supported currency, for the public ``/finance/rates`` view."""
    quotes: Dict[str, RateQuote] = {}
    for code in SEED_RATES:
        quotes[code] = await get_rate(code)
    return quotes


async def rate_history(currency: str, limit: int = 50) -> List[ExchangeRate]:
    code = _normalise(currency)
    return (
        await ExchangeRate.find(ExchangeRate.currency == code)
        .sort(-ExchangeRate.effective_at)
        .limit(limit)
        .to_list()
    )
