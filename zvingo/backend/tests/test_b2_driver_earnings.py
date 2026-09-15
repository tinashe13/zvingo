"""Driver earnings: cent-exact, ledger-backed, and idempotent per delivery."""

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.location.models import Location


class Field:
    def __eq__(self, other):
        return ("eq", other)

    def __ge__(self, other):
        return ("ge", other)

    def __neg__(self):
        return self


class Query:
    def __init__(self, values=None):
        self.values = list(values or [])

    def sort(self, *_a):
        return self

    def limit(self, *_a):
        return self

    def skip(self, *_a):
        return self

    async def to_list(self):
        return self.values

    async def count(self):
        return len(self.values)


@pytest.fixture
def harness(monkeypatch):
    """Wire up fakes for everything `record_earning` touches."""
    import app.catalog.models as catalog_models
    import app.finance.models as finance_models
    import app.finance.router as module
    import app.payment.models as payment_models
    from app.finance.ledger import LedgerService

    created = []

    class FakeEarning:
        driver_id = Field()
        order_id = Field()
        completed_at = Field()
        payment_method = Field()
        total_earning_cents = Field()
        existing = None

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = f"earning-{len(created) + 1}"

        async def insert(self):
            created.append(self)
            return self

        async def save(self):
            return self

        @classmethod
        def find(cls, *_a):
            return Query(created)

        @classmethod
        async def find_one(cls, *_a):
            return cls.existing

    order = SimpleNamespace(
        merchant_id="merchant-1",
        pickup_location=Location.from_lat_lng(-17.80, 31.05),
        dropoff_location=Location.from_lat_lng(-17.82, 31.08),
        delivery_fee=10.0,
        tip_amount=2.0,
        delivery_instructions="14 Selous Ave, Harare",
    )

    class FakeOrder:
        get = AsyncMock(return_value=order)

    class FakeRestaurant:
        merchant_id = Field()
        find_one = AsyncMock(
            return_value=SimpleNamespace(name="Pizza Inn", address="123B Main Road")
        )
        get = AsyncMock(return_value=None)

    class FakePayment:
        order_id = Field()
        find_one = AsyncMock(
            return_value=SimpleNamespace(
                id="p1", method=SimpleNamespace(value="ECOCASH"), charge_currency="USD"
            )
        )

    postings = []

    async def capture(posting):
        posting.validate_balanced()
        postings.append(posting)
        return []

    monkeypatch.setattr(finance_models, "DriverEarning", FakeEarning)
    monkeypatch.setattr(module, "Order", FakeOrder)
    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    monkeypatch.setattr(payment_models, "Payment", FakePayment)
    monkeypatch.setattr(LedgerService, "post", capture)

    return SimpleNamespace(
        module=module, order=order, earning=FakeEarning, created=created,
        postings=postings, restaurant=FakeRestaurant, payment=FakePayment,
    )


def driver(driver_id="driver-1"):
    return SimpleNamespace(id=driver_id, role="driver")


@pytest.mark.asyncio
async def test_earnings_are_recorded_in_exact_cents_with_a_balanced_posting(harness):
    result = await harness.module.record_earning("o1", "driver-1", driver())

    assert result["status"] == "recorded"
    assert result["delivery_fee_cents"] == 1000
    assert result["driver_earning_cents"] == 850   # 85% of the gross fee
    assert result["tip_cents"] == 200              # the tip passes through whole
    assert result["total_earning_cents"] == 1050
    assert result["ledger_posted"] is True

    record = harness.created[-1]
    assert record.merchant_name == "Pizza Inn"
    assert record.pickup_area == "** Main Road"     # street number masked
    assert record.payment_method == "ecocash"

    posting = harness.postings[-1]
    assert posting.idempotency_key == "order:o1:driver-payout:driver-1"
    # The earning is traceable back to the money movement that backs it.
    assert record.ledger_posting_key == posting.idempotency_key
    assert record.currency == "USD"
    driver_total = sum(
        line["amount_minor"] for line in posting.lines
        if line["party_type"].value == "DRIVER"
    )
    assert driver_total == 1050
    assert posting.balance() == 0


@pytest.mark.asyncio
async def test_a_fee_with_an_odd_number_of_cents_still_splits_exactly(harness):
    harness.order.delivery_fee = 7.77
    harness.order.tip_amount = 0
    result = await harness.module.record_earning("o1", "driver-1", driver())
    assert result["delivery_fee_cents"] == 777
    # 777 * 0.85 = 660.45 -> 660, leaving 117 commission; 660 + 117 == 777.
    assert result["driver_earning_cents"] == 660
    assert result["total_earning_cents"] == 660
    assert harness.postings[-1].balance() == 0


@pytest.mark.asyncio
async def test_recording_the_same_delivery_twice_pays_nothing_extra(harness):
    await harness.module.record_earning("o1", "driver-1", driver())
    harness.earning.existing = harness.created[-1]

    repeat = await harness.module.record_earning("o1", "driver-1", driver())
    assert repeat["status"] == "already_recorded"
    assert len(harness.created) == 1
    # No second payout posting was even attempted.
    assert len(harness.postings) == 1


@pytest.mark.asyncio
async def test_the_payout_posting_key_is_stable_so_a_replay_is_a_no_op(harness):
    """Even without the duplicate guard, the ledger key collapses a replay."""
    await harness.module.record_earning("o1", "driver-1", driver())
    await harness.module.record_earning("o1", "driver-1", driver())
    assert len({p.idempotency_key for p in harness.postings}) == 1


@pytest.mark.asyncio
async def test_a_missing_order_records_nothing(harness):
    harness.module.Order.get.return_value = None
    result = await harness.module.record_earning("missing", "driver-1", driver())
    assert result["status"] == "error"
    assert harness.created == []
    assert harness.postings == []


@pytest.mark.asyncio
async def test_an_order_without_a_fee_falls_back_to_the_distance_formula(harness):
    harness.order.delivery_fee = 0
    harness.order.tip_amount = 0
    result = await harness.module.record_earning("o1", "driver-1", driver())
    # A short hop is one $5 block.
    assert result["delivery_fee_cents"] == 500
    assert result["driver_earning_cents"] == 425


@pytest.mark.asyncio
async def test_a_cash_delivery_has_no_payment_record(harness):
    harness.payment.find_one.return_value = None
    result = await harness.module.record_earning("o1", "driver-1", driver())
    assert result["status"] == "recorded"
    assert harness.created[-1].payment_method == "cash"


@pytest.mark.asyncio
async def test_a_ledger_outage_does_not_block_the_drivers_earnings_record(
    harness, monkeypatch
):
    """The driver's record must survive a ledger failure; reconciliation catches it."""
    from app.finance.ledger import LedgerService

    monkeypatch.setattr(
        LedgerService, "post", AsyncMock(side_effect=RuntimeError("ledger offline"))
    )
    result = await harness.module.record_earning("o1", "driver-1", driver())
    assert result["status"] == "recorded"
    assert result["ledger_posted"] is False
    assert len(harness.created) == 1


@pytest.mark.asyncio
async def test_an_unavailable_restaurant_does_not_stop_the_record(harness):
    harness.restaurant.find_one.side_effect = RuntimeError("catalog offline")
    harness.restaurant.get.side_effect = RuntimeError("catalog offline")
    result = await harness.module.record_earning("o1", "driver-1", driver())
    assert result["status"] == "recorded"
    assert harness.created[-1].merchant_name == "Unknown"
    # Falls back to masking the delivery instructions.
    assert harness.created[-1].pickup_area == "** Selous Ave, Harare"


@pytest.mark.asyncio
async def test_the_summary_reports_the_independent_ledger_balance(monkeypatch):
    import app.finance.models as finance_models
    import app.finance.router as module
    from app.finance.ledger import LedgerService

    records = [
        SimpleNamespace(total_earning_cents=1050, tip_cents=200, payment_method="ecocash"),
        SimpleNamespace(total_earning_cents=425, tip_cents=0, payment_method="cash"),
    ]

    class FakeEarning:
        driver_id = Field()
        completed_at = Field()

        @classmethod
        def find(cls, *_a):
            return Query(records)

    monkeypatch.setattr(finance_models, "DriverEarning", FakeEarning)
    monkeypatch.setattr(
        LedgerService, "balance_for_party", AsyncMock(return_value=1475)
    )

    summary = await module.get_driver_earnings("driver-1", driver())
    assert summary["week_earnings_cents"] == 1475
    assert summary["ledger_week_earnings_cents"] == 1475
    assert summary["ledger_matches"] is True
    assert summary["cash_on_hand_cents"] == 425

    # A divergence between the projection and the ledger is made visible.
    monkeypatch.setattr(
        LedgerService, "balance_for_party", AsyncMock(return_value=1400)
    )
    summary = await module.get_driver_earnings("driver-1", driver())
    assert summary["ledger_matches"] is False

    # An unavailable ledger reports None rather than pretending to agree.
    monkeypatch.setattr(
        LedgerService, "balance_for_party", AsyncMock(side_effect=RuntimeError("offline"))
    )
    summary = await module.get_driver_earnings("driver-1", driver())
    assert summary["ledger_week_earnings_cents"] is None
    assert summary["ledger_matches"] is None
