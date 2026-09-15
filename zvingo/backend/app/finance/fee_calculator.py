"""Delivery fee and order fee-split engine.

Pricing formula: **$5 per started 5 km block.**

    blocks       = ceil(distance_km / 5)
    gross_fee    = blocks * $5
    driver_share = gross_fee * DRIVER_SHARE_RATIO   (default 0.85)
    commission   = gross_fee - driver_share          (the platform's ~15%)

Example: 8 km → ceil(8/5) = 2 blocks → $10.00 gross → $8.50 driver, $1.50 commission.

All arithmetic here runs on **integer minor units** via :mod:`app.finance.money`;
the ``float``-returning helpers at the bottom exist only because callers outside
the finance package (``app.order.service``, ``app.notification.service``) still
pass and expect floats. They convert at the boundary and never round twice.

The driver's share is a **split of a shared pot**, so it uses banker's rounding
(``ROUND_HALF_EVEN``). The commission is then whatever is left over — it is
never rounded independently, which is what guarantees
``driver_share + commission == gross_fee`` exactly, for every amount.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Optional, Tuple

from app.config import settings
from app.finance.money import (
    DEFAULT_CURRENCY,
    apply_ratio,
    minor_to_float,
    split_minor,
    to_decimal,
    to_minor,
)

# ── Tunables ────────────────────────────────────────────────────────
# Documented module defaults. Each reads its override from `settings` when the
# setting exists, so adding the setting in app/config.py changes behaviour with
# no edit here. See the report for the exact settings requested from F4.
DEFAULT_BLOCK_SIZE_KM = Decimal("5")
DEFAULT_BLOCK_PRICE_USD = Decimal("5.00")
DEFAULT_DRIVER_SHARE_RATIO = Decimal("0.85")
# Who funds a promo discount: "platform" (Zvingo absorbs it, merchant is paid in
# full) or "merchant" (deducted from the merchant payout).
DEFAULT_PROMO_FUNDED_BY = "platform"


def _setting_decimal(name: str, default: Decimal) -> Decimal:
    raw = getattr(settings, name, None)
    if raw is None:
        return default
    return to_decimal(raw)


def block_size_km() -> Decimal:
    return _setting_decimal("DELIVERY_BLOCK_SIZE_KM", DEFAULT_BLOCK_SIZE_KM)


def block_price_usd() -> Decimal:
    return _setting_decimal("DELIVERY_BLOCK_PRICE_USD", DEFAULT_BLOCK_PRICE_USD)


def driver_share_ratio() -> Decimal:
    """Fraction of the gross delivery fee the driver keeps (default 0.85).

    Sourced from ``settings.DRIVER_SHARE_RATIO``. Converted through ``str`` so a
    float setting such as ``0.85`` becomes ``Decimal("0.85")`` exactly rather
    than its binary expansion.
    """
    ratio = _setting_decimal("DRIVER_SHARE_RATIO", DEFAULT_DRIVER_SHARE_RATIO)
    if not (Decimal(0) <= ratio <= Decimal(1)):
        raise ValueError(
            f"DRIVER_SHARE_RATIO must be between 0 and 1, got {ratio}"
        )
    return ratio


def promo_funded_by() -> str:
    value = str(getattr(settings, "PROMO_DISCOUNT_FUNDED_BY", DEFAULT_PROMO_FUNDED_BY)).lower()
    if value not in ("platform", "merchant"):
        raise ValueError(
            f"PROMO_DISCOUNT_FUNDED_BY must be 'platform' or 'merchant', got {value!r}"
        )
    return value


# Backwards-compatible module constant. `app.finance.router` imports this name;
# prefer driver_share_ratio() in new code so a settings change is picked up
# without a process restart.
DRIVER_SHARE_RATIO = float(DEFAULT_DRIVER_SHARE_RATIO)
try:  # pragma: no cover - trivial
    DRIVER_SHARE_RATIO = float(driver_share_ratio())
except Exception:  # pragma: no cover - defensive; keep the documented default
    pass

BLOCK_SIZE_KM = float(DEFAULT_BLOCK_SIZE_KM)
BLOCK_PRICE_USD = float(DEFAULT_BLOCK_PRICE_USD)

# Haversine
_R = 6371.0  # Earth radius in km


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Compute great-circle distance in km between two lat/lng points.

    Distance is a physical quantity, not money — float is correct here.
    """
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlng / 2) ** 2
    )
    return _R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ── Minor-unit core ─────────────────────────────────────────────────


def delivery_fee_minor(distance_km: float) -> int:
    """Gross delivery fee in USD cents for a delivery of ``distance_km``.

    A zero or negative distance still charges one block — a delivery always
    costs at least the base block.
    """
    block_price_minor = to_minor(block_price_usd(), DEFAULT_CURRENCY)
    if distance_km is None or distance_km <= 0:
        return block_price_minor
    size = block_size_km()
    blocks = int(math.ceil(to_decimal(distance_km) / size))
    return block_price_minor * max(blocks, 1)


def driver_share_minor(gross_fee_minor: int) -> int:
    """Driver's cut of a gross delivery fee, banker's-rounded."""
    return apply_ratio(int(gross_fee_minor), driver_share_ratio())


def commission_minor(gross_fee_minor: int) -> int:
    """Platform commission — the exact remainder after the driver's share.

    Deriving it as a remainder (rather than rounding ``gross * 0.15``
    separately) is what makes the split reconcile to the cent every time.
    """
    _, remainder = split_minor(int(gross_fee_minor), driver_share_ratio())
    return remainder


def split_delivery_fee_minor(gross_fee_minor: int) -> Tuple[int, int]:
    """``(driver_share_minor, platform_commission_minor)``; always sums to gross."""
    return split_minor(int(gross_fee_minor), driver_share_ratio())


# ── Full order breakdown ────────────────────────────────────────────


@dataclass(frozen=True)
class FeeBreakdown:
    """Every money component of one order, in integer minor units.

    The invariant this type exists to enforce:

        merchant_payout + driver_payout + platform_net == customer_total

    exactly, for every input, with no rounding slack. :meth:`validate` raises if
    that ever stops being true, and it is called in :meth:`__post_init__`, so an
    unbalanced breakdown cannot be constructed at all.
    """

    currency: str = DEFAULT_CURRENCY

    # What the customer is billed for
    subtotal_minor: int = 0        # food, before anything else
    delivery_fee_minor: int = 0    # gross delivery fee
    service_fee_minor: int = 0     # platform service fee
    tax_minor: int = 0             # tax collected for remittance
    tip_minor: int = 0             # goes to the driver in full
    discount_minor: int = 0        # promo, subtracted (stored positive)

    # How the money is divided
    driver_share_minor: int = 0        # driver's cut of the delivery fee
    platform_commission_minor: int = 0  # remainder of the delivery fee
    promo_funded_by: str = DEFAULT_PROMO_FUNDED_BY

    def __post_init__(self):
        self.validate()

    # -- customer side --
    @property
    def customer_total_minor(self) -> int:
        """What the consumer actually owes — the amount to charge at Paynow."""
        return (
            self.subtotal_minor
            + self.delivery_fee_minor
            + self.service_fee_minor
            + self.tax_minor
            + self.tip_minor
            - self.discount_minor
        )

    # -- payout side --
    @property
    def merchant_discount_minor(self) -> int:
        return self.discount_minor if self.promo_funded_by == "merchant" else 0

    @property
    def platform_discount_minor(self) -> int:
        return self.discount_minor if self.promo_funded_by == "platform" else 0

    @property
    def merchant_payout_minor(self) -> int:
        return self.subtotal_minor - self.merchant_discount_minor

    @property
    def driver_payout_minor(self) -> int:
        """Driver's share of the delivery fee plus 100% of the tip."""
        return self.driver_share_minor + self.tip_minor

    @property
    def platform_revenue_minor(self) -> int:
        """Zvingo's own income: commission + service fee, less any promo it funds."""
        return (
            self.platform_commission_minor
            + self.service_fee_minor
            - self.platform_discount_minor
        )

    @property
    def tax_collected_minor(self) -> int:
        """Tax held on the customer's behalf for remittance — not revenue."""
        return self.tax_minor

    @property
    def platform_net_minor(self) -> int:
        return self.platform_revenue_minor + self.tax_collected_minor

    def validate(self) -> None:
        for name in (
            "subtotal_minor",
            "delivery_fee_minor",
            "service_fee_minor",
            "tax_minor",
            "tip_minor",
            "discount_minor",
        ):
            if getattr(self, name) < 0:
                raise ValueError(f"{name} must not be negative")
        if self.driver_share_minor + self.platform_commission_minor != self.delivery_fee_minor:
            raise ValueError(
                "delivery fee split does not reconcile: "
                f"{self.driver_share_minor} + {self.platform_commission_minor} "
                f"!= {self.delivery_fee_minor}"
            )
        if self.discount_minor > (
            self.subtotal_minor
            + self.delivery_fee_minor
            + self.service_fee_minor
            + self.tax_minor
        ):
            raise ValueError("discount exceeds the charge it is discounting")
        total = self.customer_total_minor
        parts = (
            self.merchant_payout_minor
            + self.driver_payout_minor
            + self.platform_net_minor
        )
        if parts != total:
            raise ValueError(
                f"fee breakdown does not reconcile: parts={parts} total={total}"
            )

    def as_dict(self) -> dict:
        """Inspectable breakdown, minor units plus display strings.

        Minor units are the contract; the ``*_display`` floats exist only so a
        client can render without doing its own division.
        """
        c = self.currency
        return {
            "currency": c,
            "subtotal_minor": self.subtotal_minor,
            "delivery_fee_minor": self.delivery_fee_minor,
            "service_fee_minor": self.service_fee_minor,
            "tax_minor": self.tax_minor,
            "tip_minor": self.tip_minor,
            "discount_minor": self.discount_minor,
            "customer_total_minor": self.customer_total_minor,
            "driver_share_minor": self.driver_share_minor,
            "driver_payout_minor": self.driver_payout_minor,
            "platform_commission_minor": self.platform_commission_minor,
            "platform_revenue_minor": self.platform_revenue_minor,
            "tax_collected_minor": self.tax_collected_minor,
            "platform_net_minor": self.platform_net_minor,
            "merchant_payout_minor": self.merchant_payout_minor,
            "promo_funded_by": self.promo_funded_by,
            "customer_total_display": minor_to_float(self.customer_total_minor, c),
            "driver_payout_display": minor_to_float(self.driver_payout_minor, c),
            "merchant_payout_display": minor_to_float(self.merchant_payout_minor, c),
            "platform_net_display": minor_to_float(self.platform_net_minor, c),
        }


def build_breakdown(
    *,
    subtotal_minor: int,
    delivery_fee_minor: int = 0,
    service_fee_minor: int = 0,
    tax_minor: int = 0,
    tip_minor: int = 0,
    discount_minor: int = 0,
    currency: str = DEFAULT_CURRENCY,
) -> FeeBreakdown:
    """Build a :class:`FeeBreakdown`, splitting the delivery fee correctly."""
    driver, commission = split_delivery_fee_minor(delivery_fee_minor)
    return FeeBreakdown(
        currency=currency,
        subtotal_minor=int(subtotal_minor),
        delivery_fee_minor=int(delivery_fee_minor),
        service_fee_minor=int(service_fee_minor),
        tax_minor=int(tax_minor),
        tip_minor=int(tip_minor),
        discount_minor=int(discount_minor),
        driver_share_minor=driver,
        platform_commission_minor=commission,
        promo_funded_by=promo_funded_by(),
    )


def breakdown_for_order(order: Any, currency: str = DEFAULT_CURRENCY) -> FeeBreakdown:
    """Derive the authoritative fee breakdown for an ``Order`` document.

    ``Order.total_amount`` is the **basket subtotal before fees, tip and promo
    discount** — that is how ``CheckoutBasket.subtotal`` is defined and how
    ``OrderService.create_checkout`` populates it. ``delivery_fee``,
    ``service_fee``, ``tax_amount``, ``tip_amount`` and ``discount_amount`` are
    separate fields on the order and are *added on top*.

    This is the single place that interpretation lives. Reading
    ``order.total_amount`` directly as "the amount to charge" undercharges the
    customer by the whole delivery fee (see the B2 report).

    The order's money fields are still ``float`` (``app/order/models.py`` is
    owned by another team); each is converted through
    :func:`app.finance.money.to_minor`, which routes via ``str`` so the value a
    human meant is what gets charged.
    """

    def field(name: str) -> int:
        value = getattr(order, name, None) or 0
        return to_minor(value, currency)

    return build_breakdown(
        subtotal_minor=field("total_amount"),
        delivery_fee_minor=field("delivery_fee"),
        service_fee_minor=field("service_fee"),
        tax_minor=field("tax_amount"),
        tip_minor=field("tip_amount"),
        discount_minor=field("discount_amount"),
        currency=currency,
    )


# ── Float boundary (legacy callers outside app.finance) ─────────────


def calculate_delivery_fee(distance_km: float) -> Tuple[float, float]:
    """Calculate delivery fee for a distance.

    Returns ``(gross_fee_usd, driver_share_usd)`` as floats **for display and
    for the float-typed ``Order`` fields owned by another module**. Internally
    the maths is integer cents; the floats are produced once, at the end.
    """
    gross = delivery_fee_minor(distance_km)
    driver = driver_share_minor(gross)
    return (minor_to_float(gross), minor_to_float(driver))


def calculate_delivery_fee_from_coords(
    pickup_lat: float,
    pickup_lng: float,
    dropoff_lat: float,
    dropoff_lng: float,
) -> Tuple[float, float, float]:
    """Calculate delivery fee from pickup/dropoff coordinates.

    Returns ``(gross_fee_usd, driver_share_usd, distance_km)``.
    """
    dist = haversine_km(pickup_lat, pickup_lng, dropoff_lat, dropoff_lng)
    gross, driver = calculate_delivery_fee(dist)
    return (gross, driver, round(dist, 2))


def delivery_fee_minor_from_coords(
    pickup_lat: float, pickup_lng: float, dropoff_lat: float, dropoff_lng: float
) -> Tuple[int, int, float]:
    """Minor-unit variant of :func:`calculate_delivery_fee_from_coords`."""
    dist = haversine_km(pickup_lat, pickup_lng, dropoff_lat, dropoff_lng)
    gross = delivery_fee_minor(dist)
    return (gross, driver_share_minor(gross), round(dist, 2))
