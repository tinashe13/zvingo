"""Money primitives for Zvingo.

**Floats must never represent money.** Binary floating point cannot represent
`0.10` or `0.07` exactly, so `0.1 + 0.2 != 0.3` and a long chain of fee
arithmetic silently drifts. At Zimbabwean ZIG scale (thousands of units per
USD) that drift becomes visible in a single order.

The rules used everywhere in `app.finance` and `app.payment`:

1. **Storage and arithmetic use integer minor units** (cents for USD/ZAR/ZIG).
   An ``int`` is exact, sums exactly, and round-trips through JSON and BSON
   without loss.
2. **Intermediate ratio maths uses :class:`decimal.Decimal`** with an explicit
   rounding mode — never ``float``.
3. **Rounding is banker's rounding** (``ROUND_HALF_EVEN``) wherever a fee is
   *split*, so repeated half-cent splits do not systematically favour one
   party. Rounding is always explicit at the call site; nothing rounds by
   accident.
4. **Conversion to float happens only at the presentation boundary** — the last
   step before JSON goes out to a client, via :func:`minor_to_decimal` /
   :func:`format_money`.

Any value that reaches this module as a ``float`` (legacy documents, request
payloads typed ``float`` in another team's schema) is converted through
``str()`` first, which reproduces the shortest decimal that round-trips — the
number a human actually meant — instead of the binary expansion.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_EVEN, ROUND_HALF_UP, localcontext
from typing import Iterable, List, Sequence, Union

Numeric = Union[int, float, str, Decimal]

__all__ = [
    "Numeric",
    "CurrencySpec",
    "CURRENCIES",
    "DEFAULT_CURRENCY",
    "currency_spec",
    "is_supported_currency",
    "to_decimal",
    "to_minor",
    "minor_to_decimal",
    "minor_to_float",
    "format_money",
    "apply_ratio",
    "split_minor",
    "allocate_minor",
    "sum_minor",
    "MoneyError",
]


class MoneyError(ValueError):
    """Raised when an amount cannot be represented safely."""


@dataclass(frozen=True)
class CurrencySpec:
    """Static facts about a currency Zvingo settles in."""

    code: str
    exponent: int  # number of decimal places, e.g. 2 => minor unit is 1/100
    symbol: str

    @property
    def scale(self) -> Decimal:
        return Decimal(10) ** self.exponent


# Zimbabwe market. USD is the pricing/base currency; ZIG (Zimbabwe Gold) and
# ZAR are settlement currencies quoted against it.
CURRENCIES = {
    "USD": CurrencySpec("USD", 2, "$"),
    "ZIG": CurrencySpec("ZIG", 2, "ZiG"),
    "ZAR": CurrencySpec("ZAR", 2, "R"),
}

DEFAULT_CURRENCY = "USD"


def currency_spec(currency: str) -> CurrencySpec:
    """Return the :class:`CurrencySpec` for ``currency``.

    Unknown currencies are rejected rather than silently assumed to have two
    decimal places — a wrong exponent is a 100x money error.
    """
    code = (currency or "").strip().upper()
    spec = CURRENCIES.get(code)
    if spec is None:
        raise MoneyError(
            f"Unsupported currency {currency!r}; supported: {sorted(CURRENCIES)}"
        )
    return spec


def is_supported_currency(currency: str) -> bool:
    return (currency or "").strip().upper() in CURRENCIES


def to_decimal(value: Numeric) -> Decimal:
    """Convert any numeric input to :class:`Decimal` without binary drift.

    Floats go through ``repr``/``str`` so ``0.1`` becomes ``Decimal("0.1")``
    rather than ``Decimal("0.1000000000000000055511151231257827021181583404541015625")``.
    """
    if isinstance(value, Decimal):
        return value
    if isinstance(value, bool):  # bool is an int subclass; never money
        raise MoneyError("bool is not a monetary amount")
    if isinstance(value, int):
        return Decimal(value)
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            raise MoneyError(f"Non-finite monetary amount: {value!r}")
        return Decimal(str(value))
    if isinstance(value, str):
        try:
            return Decimal(value.strip())
        except Exception as exc:  # pragma: no cover - defensive
            raise MoneyError(f"Cannot parse monetary amount {value!r}") from exc
    raise MoneyError(f"Cannot interpret {type(value).__name__} as money")


def to_minor(value: Numeric, currency: str = DEFAULT_CURRENCY, *, rounding: str = ROUND_HALF_UP) -> int:
    """Convert a major-unit amount (dollars) to integer minor units (cents).

    ``rounding`` defaults to ``ROUND_HALF_UP`` because this is a *representation*
    conversion of a price a human quoted, not a split of a shared pot. Use
    :func:`apply_ratio` / :func:`split_minor` (banker's rounding) when dividing.
    """
    spec = currency_spec(currency)
    amount = to_decimal(value)
    with localcontext() as ctx:
        ctx.prec = 34
        scaled = (amount * spec.scale).quantize(Decimal(1), rounding=rounding)
    return int(scaled)


def minor_to_decimal(minor: int, currency: str = DEFAULT_CURRENCY) -> Decimal:
    """Exact major-unit :class:`Decimal` for a minor-unit integer."""
    spec = currency_spec(currency)
    return (Decimal(int(minor)) / spec.scale).quantize(
        Decimal(1).scaleb(-spec.exponent)
    )


def minor_to_float(minor: int, currency: str = DEFAULT_CURRENCY) -> float:
    """Presentation boundary only: major units as ``float`` for JSON output.

    Never feed the result back into arithmetic.
    """
    return float(minor_to_decimal(minor, currency))


def format_money(minor: int, currency: str = DEFAULT_CURRENCY) -> str:
    """Human-readable amount with an explicit currency symbol.

    ``format_money(1050, "USD") == "$10.50"``; negatives keep the sign in front
    of the symbol so a refund reads ``-$10.50``.
    """
    spec = currency_spec(currency)
    amount = minor_to_decimal(minor, spec.code)
    sign = "-" if amount < 0 else ""
    return f"{sign}{spec.symbol}{abs(amount):,.{spec.exponent}f}"


def apply_ratio(
    minor: int, ratio: Numeric, *, rounding: str = ROUND_HALF_EVEN
) -> int:
    """Multiply a minor-unit amount by a ratio with explicit banker's rounding.

    Used for the driver's share of a delivery fee and the platform commission.
    ``ROUND_HALF_EVEN`` means an exact half-cent lands on the even cent, so
    across many orders the rounding error does not systematically favour the
    platform or the driver.
    """
    with localcontext() as ctx:
        ctx.prec = 34
        product = Decimal(int(minor)) * to_decimal(ratio)
        return int(product.quantize(Decimal(1), rounding=rounding))


def split_minor(
    minor: int, ratio: Numeric, *, rounding: str = ROUND_HALF_EVEN
) -> tuple:
    """Split ``minor`` into ``(share, remainder)`` with no cent lost.

    ``share`` is ``minor * ratio`` rounded, and ``remainder`` is whatever is
    left, so ``share + remainder == minor`` exactly, always.
    """
    share = apply_ratio(minor, ratio, rounding=rounding)
    return share, int(minor) - share


def allocate_minor(minor: int, weights: Sequence[Numeric]) -> List[int]:
    """Allocate ``minor`` across ``weights`` so the parts sum exactly to ``minor``.

    Largest-remainder method: every part is floored, then the leftover cents go
    to the parts with the largest fractional remainders (ties broken by order).
    Used to split a basket-wide promo discount across sibling orders without
    losing or inventing a cent.
    """
    total_minor = int(minor)
    decimals = [to_decimal(w) for w in weights]
    if not decimals:
        return []
    if any(d < 0 for d in decimals):
        raise MoneyError("allocation weights must be non-negative")

    total_weight = sum(decimals)
    if total_weight == 0:
        # Degenerate: spread evenly, remainder to the first buckets.
        base, rem = divmod(total_minor, len(decimals))
        return [base + (1 if i < rem else 0) for i in range(len(decimals))]

    exact = []
    with localcontext() as ctx:
        ctx.prec = 34
        for weight in decimals:
            exact.append(Decimal(total_minor) * weight / total_weight)

    floors = [int(e.to_integral_value(rounding="ROUND_FLOOR")) for e in exact]
    leftover = total_minor - sum(floors)
    order = sorted(
        range(len(exact)), key=lambda i: (-(exact[i] - floors[i]), i)
    )
    for i in range(leftover):
        floors[order[i % len(order)]] += 1
    return floors


def sum_minor(values: Iterable[int]) -> int:
    """Exact sum of minor-unit amounts (documents intent at call sites)."""
    return sum(int(v) for v in values)
