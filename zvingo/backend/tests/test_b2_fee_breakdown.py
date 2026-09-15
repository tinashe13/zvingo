"""Commission, driver share and the full fee breakdown must reconcile exactly."""

import random
from decimal import Decimal
from types import SimpleNamespace

import pytest

from app.finance import fee_calculator as fc
from app.finance.fee_calculator import (
    FeeBreakdown,
    breakdown_for_order,
    build_breakdown,
    calculate_delivery_fee,
    commission_minor,
    delivery_fee_minor,
    driver_share_minor,
    split_delivery_fee_minor,
)


def test_block_pricing_in_minor_units():
    assert delivery_fee_minor(0) == 500        # minimum one block
    assert delivery_fee_minor(-1) == 500
    assert delivery_fee_minor(5.0) == 500      # exactly one block
    assert delivery_fee_minor(5.01) == 1000    # a started second block
    assert delivery_fee_minor(12.4) == 1500


def test_driver_share_and_commission_always_sum_to_the_gross_fee():
    for gross in range(0, 10_001):
        driver = driver_share_minor(gross)
        commission = commission_minor(gross)
        assert driver + commission == gross, gross
        assert 0 <= driver <= gross


def test_commission_is_the_remainder_not_an_independent_rounding():
    """The classic bug: rounding both sides separately loses or invents a cent."""
    gross = 333  # $3.33 -> 0.85 share = 283.05
    driver, commission = split_delivery_fee_minor(gross)
    assert driver + commission == gross
    # Rounding 15% independently would give 50, and 283 + 50 = 333 here, but
    # the guarantee must hold for every amount, which the remainder gives us.
    for amount in (1, 3, 7, 13, 17, 99, 101, 1007):
        d, c = split_delivery_fee_minor(amount)
        assert d + c == amount


def test_float_api_keeps_its_documented_contract():
    assert calculate_delivery_fee(0) == (5.0, 4.25)
    assert calculate_delivery_fee(5.0) == (5.0, 4.25)
    assert calculate_delivery_fee(5.01) == (10.0, 8.5)


def test_driver_share_ratio_comes_from_settings(monkeypatch):
    monkeypatch.setattr(fc.settings, "DRIVER_SHARE_RATIO", 0.80, raising=False)
    assert fc.driver_share_ratio() == Decimal("0.8")
    assert driver_share_minor(1000) == 800
    assert commission_minor(1000) == 200

    # An out-of-range ratio is refused rather than silently paying a driver
    # more than the fee collected.
    monkeypatch.setattr(fc.settings, "DRIVER_SHARE_RATIO", 1.5, raising=False)
    with pytest.raises(ValueError):
        fc.driver_share_ratio()


def test_documented_module_default_when_the_setting_is_absent(monkeypatch):
    monkeypatch.delattr(fc.settings, "DRIVER_SHARE_RATIO", raising=False)
    assert fc.driver_share_ratio() == fc.DEFAULT_DRIVER_SHARE_RATIO == Decimal("0.85")


# ── Full breakdown reconciliation ───────────────────────────────────


def _assert_reconciles(b: FeeBreakdown):
    total = b.customer_total_minor
    parts = b.merchant_payout_minor + b.driver_payout_minor + b.platform_net_minor
    assert parts == total, (b.as_dict(), parts, total)
    assert b.driver_share_minor + b.platform_commission_minor == b.delivery_fee_minor
    assert b.driver_payout_minor == b.driver_share_minor + b.tip_minor


def test_simple_breakdown_reconciles_and_reads_correctly():
    b = build_breakdown(
        subtotal_minor=2000,      # $20.00 food
        delivery_fee_minor=1000,  # $10.00 delivery
        service_fee_minor=150,
        tax_minor=100,
        tip_minor=200,
        discount_minor=300,
    )
    assert b.customer_total_minor == 2000 + 1000 + 150 + 100 + 200 - 300
    assert b.driver_share_minor == 850
    assert b.platform_commission_minor == 150
    assert b.driver_payout_minor == 1050         # share + full tip
    assert b.merchant_payout_minor == 2000       # platform funds the promo
    assert b.platform_revenue_minor == 150 + 150 - 300
    assert b.tax_collected_minor == 100
    _assert_reconciles(b)


def test_merchant_funded_promo_also_reconciles(monkeypatch):
    # PROMO_DISCOUNT_FUNDED_BY is not yet a Settings field (requested from F4),
    # so exercise the switch through the accessor that reads it.
    monkeypatch.setattr(fc, "promo_funded_by", lambda: "merchant")
    b = build_breakdown(
        subtotal_minor=2000, delivery_fee_minor=1000, discount_minor=500
    )
    assert b.merchant_payout_minor == 1500
    assert b.platform_revenue_minor == 150
    _assert_reconciles(b)


def test_promo_funding_default_and_validation(monkeypatch):
    assert fc.promo_funded_by() == fc.DEFAULT_PROMO_FUNDED_BY == "platform"

    class FakeSettings:
        PROMO_DISCOUNT_FUNDED_BY = "nonsense"

    monkeypatch.setattr(fc, "settings", FakeSettings)
    with pytest.raises(ValueError):
        fc.promo_funded_by()


def test_reconciliation_holds_across_a_wide_spread_of_awkward_amounts():
    """Every combination must reconcile to the cent — especially odd ones."""
    awkward = [0, 1, 3, 7, 13, 17, 33, 49, 99, 101, 333, 777, 1001, 1999, 12345]
    for subtotal in awkward:
        for fee in awkward:
            b = build_breakdown(
                subtotal_minor=subtotal,
                delivery_fee_minor=fee,
                service_fee_minor=fee // 7,
                tax_minor=subtotal // 13,
                tip_minor=fee // 3,
                discount_minor=min(subtotal, 17),
            )
            _assert_reconciles(b)


def test_reconciliation_holds_for_random_amounts():
    rng = random.Random(20260915)
    for _ in range(2000):
        subtotal = rng.randint(0, 500_00)
        fee = rng.randint(0, 100_00)
        b = build_breakdown(
            subtotal_minor=subtotal,
            delivery_fee_minor=fee,
            service_fee_minor=rng.randint(0, 500),
            tax_minor=rng.randint(0, 2_00),
            tip_minor=rng.randint(0, 20_00),
            discount_minor=rng.randint(0, subtotal or 1) if subtotal else 0,
        )
        _assert_reconciles(b)


def test_breakdown_refuses_to_exist_in_an_unbalanced_state():
    with pytest.raises(ValueError):
        FeeBreakdown(
            subtotal_minor=1000,
            delivery_fee_minor=1000,
            driver_share_minor=850,
            platform_commission_minor=200,  # 850 + 200 != 1000
        )
    with pytest.raises(ValueError):
        build_breakdown(subtotal_minor=-100)
    with pytest.raises(ValueError):
        build_breakdown(subtotal_minor=100, discount_minor=500)


def test_breakdown_is_inspectable():
    b = build_breakdown(subtotal_minor=1234, delivery_fee_minor=1000, tip_minor=150)
    data = b.as_dict()
    for key in (
        "subtotal_minor",
        "delivery_fee_minor",
        "service_fee_minor",
        "tax_minor",
        "tip_minor",
        "discount_minor",
        "customer_total_minor",
        "driver_share_minor",
        "driver_payout_minor",
        "platform_commission_minor",
        "merchant_payout_minor",
        "platform_net_minor",
    ):
        assert key in data
    assert data["customer_total_display"] == 23.84


# ── Order interpretation ────────────────────────────────────────────


def test_order_breakdown_charges_the_whole_order_not_just_the_subtotal():
    """`Order.total_amount` is the basket subtotal; fees are added on top.

    Charging `total_amount` directly (the previous behaviour) handed the
    customer the delivery fee, service fee and tax for free.
    """
    order = SimpleNamespace(
        total_amount=20.00,
        delivery_fee=10.00,
        service_fee=1.50,
        tax_amount=1.00,
        tip_amount=2.00,
        discount_amount=3.00,
    )
    b = breakdown_for_order(order)
    assert b.subtotal_minor == 2000
    assert b.customer_total_minor == 3150
    assert b.customer_total_minor != b.subtotal_minor
    _assert_reconciles(b)


def test_order_breakdown_tolerates_missing_and_null_fee_fields():
    order = SimpleNamespace(total_amount=10.0)
    b = breakdown_for_order(order)
    assert b.customer_total_minor == 1000

    order = SimpleNamespace(
        total_amount=10.0, delivery_fee=None, service_fee=None,
        tax_amount=None, tip_amount=None, discount_amount=None,
    )
    assert breakdown_for_order(order).customer_total_minor == 1000


def test_order_breakdown_uses_the_decimal_value_not_the_binary_float():
    order = SimpleNamespace(total_amount=0.1, delivery_fee=0.2)
    b = breakdown_for_order(order)
    assert b.subtotal_minor == 10
    assert b.delivery_fee_minor == 20
    assert b.customer_total_minor == 30
