"""Money representation: integer minor units, explicit rounding, no float drift."""

from decimal import Decimal

import pytest

from app.finance.money import (
    MoneyError,
    allocate_minor,
    apply_ratio,
    currency_spec,
    format_money,
    is_supported_currency,
    minor_to_decimal,
    minor_to_float,
    split_minor,
    to_decimal,
    to_minor,
)


def test_floats_are_converted_through_their_decimal_representation():
    """0.1 + 0.2 must not become 0.30000000000000004 cents."""
    assert to_decimal(0.1) == Decimal("0.1")
    assert to_decimal(20.15) == Decimal("20.15")
    # The naive route loses the value; ours does not.
    assert Decimal(0.1) != Decimal("0.1")


def test_to_minor_is_exact_for_the_values_floats_get_wrong():
    for value, expected in [
        (0.1, 10),
        (0.07, 7),
        (1.005, 101),   # half cent rounds up (ROUND_HALF_UP): a quoted price
        (20.15, 2015),
        (8.29, 829),
        (1.15, 115),
        ("13.37", 1337),
        (Decimal("0.01"), 1),
        (0, 0),
    ]:
        assert to_minor(value) == expected, value


def test_summing_prices_in_cents_never_drifts():
    prices = [0.1, 0.2, 0.3, 19.99, 0.07] * 40
    cents = sum(to_minor(p) for p in prices)
    assert cents == (10 + 20 + 30 + 1999 + 7) * 40
    # The float route is off by a fraction of a cent, which is exactly the bug.
    assert abs(sum(prices) * 100 - cents) < 1
    assert sum(prices) * 100 != cents


def test_minor_round_trip_and_presentation():
    assert minor_to_decimal(1050) == Decimal("10.50")
    assert minor_to_float(1050) == 10.5
    assert format_money(1050, "USD") == "$10.50"
    assert format_money(-1050, "USD") == "-$10.50"
    assert format_money(135000, "ZIG") == "ZiG1,350.00"
    assert format_money(2500, "ZAR") == "R25.00"


def test_unsupported_currency_is_rejected_not_assumed():
    assert is_supported_currency("usd")
    assert not is_supported_currency("GBP")
    with pytest.raises(MoneyError):
        currency_spec("GBP")
    with pytest.raises(MoneyError):
        to_minor(10, "GBP")


def test_non_monetary_inputs_are_rejected():
    with pytest.raises(MoneyError):
        to_decimal(True)
    with pytest.raises(MoneyError):
        to_decimal(float("nan"))
    with pytest.raises(MoneyError):
        to_decimal(float("inf"))
    with pytest.raises(MoneyError):
        to_decimal(None)
    with pytest.raises(MoneyError):
        to_decimal("not money")


def test_apply_ratio_uses_bankers_rounding():
    """An exact half-cent lands on the even cent, so splits are unbiased."""
    # 50 * 0.85 = 42.5 -> 42 (even), 150 * 0.85 = 127.5 -> 128 (even)
    assert apply_ratio(50, Decimal("0.85")) == 42
    assert apply_ratio(150, Decimal("0.85")) == 128
    # ROUND_HALF_UP would give 43 and 128; the point is that half-cents do not
    # systematically favour one side.
    assert apply_ratio(1000, Decimal("0.85")) == 850


def test_split_minor_never_loses_a_cent():
    for amount in range(0, 2000, 7):
        share, remainder = split_minor(amount, Decimal("0.85"))
        assert share + remainder == amount


def test_allocate_minor_distributes_exactly():
    # A $1.00 discount across three baskets: 33 + 33 + 34, not 33 + 33 + 33.
    parts = allocate_minor(100, [1, 1, 1])
    assert sum(parts) == 100
    assert sorted(parts) == [33, 33, 34]

    # Weighted by basket subtotal.
    parts = allocate_minor(1000, [Decimal("12.50"), Decimal("37.50")])
    assert sum(parts) == 1000
    assert parts == [250, 750]

    # Degenerate zero weights still conserve the total.
    parts = allocate_minor(7, [0, 0, 0])
    assert sum(parts) == 7

    assert allocate_minor(100, []) == []
    with pytest.raises(MoneyError):
        allocate_minor(100, [-1, 2])


def test_allocation_is_exact_across_many_awkward_splits():
    for total in (1, 7, 99, 101, 1000, 12345):
        for buckets in (2, 3, 7, 11):
            parts = allocate_minor(total, [1] * buckets)
            assert sum(parts) == total
            assert max(parts) - min(parts) <= 1
