"""The immutable double-entry ledger and the standard postings built on it."""

from decimal import Decimal
from types import SimpleNamespace

import pytest

from app.finance.fee_calculator import build_breakdown
from app.finance.ledger import (
    PLATFORM_PARTY_ID,
    EntryType,
    LedgerEntry,
    LedgerImmutableError,
    LedgerPosting,
    LedgerService,
    PartyType,
    UnbalancedPostingError,
)
from app.finance.postings import (
    build_charge_posting,
    build_driver_payout_posting,
    build_refund_posting,
    charge_key,
    driver_payout_key,
)


def _install(monkeypatch, existing=None):
    """Patch LedgerEntry with a minimal in-memory double."""
    rows = list(existing or [])

    class Query:
        def __init__(self, values):
            self.values = values

        async def to_list(self):
            return self.values

    class Entry:
        idempotency_key = "idempotency_key"

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = f"entry-{len(rows) + 1}"

        async def insert(self):
            rows.append(self)
            return self

        @classmethod
        def find(cls, *args):
            wanted = args[0][1] if args and isinstance(args[0], tuple) else None
            return Query([r for r in rows if r.idempotency_key == wanted])

    # `LedgerEntry.idempotency_key == key` must produce a comparable filter.
    class Field:
        def __eq__(self, other):
            return ("idempotency_key", other)

    Entry.idempotency_key = Field()
    monkeypatch.setattr("app.finance.ledger.LedgerEntry", Entry)
    return rows


# ── the document itself ─────────────────────────────────────────────


@pytest.mark.asyncio
async def test_ledger_entries_refuse_every_mutation():
    # model_construct skips Beanie's collection binding; the immutability
    # guards are plain methods and do not need a database.
    entry = LedgerEntry.model_construct(
        posting_id="p",
        idempotency_key="k",
        entry_type=EntryType.CHARGE,
        party_type=PartyType.CONSUMER,
        party_id="c1",
        amount_minor=-1000,
        currency="USD",
    )
    for method in ("save", "replace", "update", "set", "delete"):
        with pytest.raises(LedgerImmutableError):
            await getattr(entry, method)()
    assert "CHARGE" in entry.describe()
    assert "-$10.00" in entry.describe()


def test_posting_must_balance():
    posting = LedgerPosting(idempotency_key="k")
    posting.add(EntryType.CHARGE, PartyType.CONSUMER, -1000, party_id="c1")
    with pytest.raises(UnbalancedPostingError):
        posting.validate_balanced()

    posting.add(EntryType.CHARGE, PartyType.PLATFORM, 1000, party_id=PLATFORM_PARTY_ID)
    posting.validate_balanced()
    assert posting.balance() == 0


def test_zero_value_lines_are_dropped():
    posting = LedgerPosting(idempotency_key="k")
    posting.add(EntryType.TIP, PartyType.DRIVER, 0, party_id="d1")
    assert posting.lines == []


def test_posting_rejects_an_unknown_currency():
    posting = LedgerPosting(idempotency_key="k", currency="GBP")
    with pytest.raises(Exception):
        posting.validate_balanced()


# ── LedgerService ───────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_post_writes_a_balanced_set_once(monkeypatch):
    rows = _install(monkeypatch)

    posting = LedgerPosting(idempotency_key="pay-1", order_id="o1", payment_id="p1")
    posting.add(EntryType.CHARGE, PartyType.CONSUMER, -3150, party_id="c1")
    posting.add(EntryType.CHARGE, PartyType.PLATFORM, 3150, party_id=PLATFORM_PARTY_ID)

    written = await LedgerService.post(posting)
    assert len(written) == 2
    assert len(rows) == 2
    assert LedgerService.residual(written) == 0
    # All entries in one posting share a posting id.
    assert len({e.posting_id for e in written}) == 1

    # Replaying the same posting writes nothing more — this is what stops a
    # retried webhook from double-crediting.
    again = await LedgerService.post(posting)
    assert len(rows) == 2
    assert len(again) == 2


@pytest.mark.asyncio
async def test_post_refuses_an_unbalanced_posting_before_writing(monkeypatch):
    rows = _install(monkeypatch)
    posting = LedgerPosting(idempotency_key="bad")
    posting.add(EntryType.CHARGE, PartyType.CONSUMER, -1000, party_id="c1")
    posting.add(EntryType.CHARGE, PartyType.PLATFORM, 900, party_id=PLATFORM_PARTY_ID)
    with pytest.raises(UnbalancedPostingError):
        await LedgerService.post(posting)
    assert rows == []


@pytest.mark.asyncio
async def test_empty_posting_is_a_no_op(monkeypatch):
    rows = _install(monkeypatch)
    assert await LedgerService.post(LedgerPosting(idempotency_key="empty")) == []
    assert rows == []


# ── standard postings ───────────────────────────────────────────────


def test_charge_posting_balances_and_books_the_merchant_obligation():
    breakdown = build_breakdown(
        subtotal_minor=2000,
        delivery_fee_minor=1000,
        service_fee_minor=150,
        tax_minor=100,
        tip_minor=200,
        discount_minor=300,
    )
    posting = build_charge_posting(
        payment_id="p1",
        order_id="o1",
        consumer_id="c1",
        merchant_id="m1",
        total_minor=breakdown.customer_total_minor,
        breakdown=breakdown,
    )
    posting.validate_balanced()
    assert posting.idempotency_key == charge_key("p1")

    by_party = {}
    for line in posting.lines:
        by_party[line["party_type"]] = by_party.get(line["party_type"], 0) + line["amount_minor"]

    assert by_party[PartyType.CONSUMER] == -3150
    assert by_party[PartyType.MERCHANT] == 2000
    # The platform holds the delivery fee, fees, tax and tip until the driver
    # is known — no driver is assigned at payment time.
    assert by_party[PartyType.PLATFORM] == 1150
    assert sum(by_party.values()) == 0


def test_charge_posting_without_a_breakdown_is_still_balanced():
    posting = build_charge_posting(
        payment_id="p1",
        order_id="o1",
        consumer_id="c1",
        merchant_id="m1",
        total_minor=1000,
    )
    posting.validate_balanced()
    assert len(posting.lines) == 2


def test_charge_posting_converts_the_merchant_share_at_the_pinned_rate():
    breakdown = build_breakdown(subtotal_minor=2000, delivery_fee_minor=1000)
    rate = Decimal("13.5")
    posting = build_charge_posting(
        payment_id="p1",
        order_id="o1",
        consumer_id="c1",
        merchant_id="m1",
        total_minor=40500,  # 3000 USD cents * 13.5
        currency="ZIG",
        breakdown=breakdown,
        fx_rate=rate,
    )
    posting.validate_balanced()
    merchant = [l for l in posting.lines if l["party_type"] == PartyType.MERCHANT][0]
    assert merchant["amount_minor"] == 27000  # 2000 * 13.5
    # FX rounding lands on the platform, derived as the remainder.
    assert posting.balance() == 0


def test_charge_posting_never_books_more_to_the_merchant_than_was_collected():
    breakdown = build_breakdown(subtotal_minor=5000)
    posting = build_charge_posting(
        payment_id="p1",
        order_id="o1",
        consumer_id="c1",
        merchant_id="m1",
        total_minor=1000,  # partial capture
        breakdown=breakdown,
    )
    posting.validate_balanced()
    merchant = [l for l in posting.lines if l["party_type"] == PartyType.MERCHANT][0]
    assert merchant["amount_minor"] == 1000


def test_driver_payout_posting_pays_share_plus_full_tip():
    posting = build_driver_payout_posting(
        order_id="o1", driver_id="d1", driver_share_minor=850, tip_minor=200
    )
    posting.validate_balanced()
    assert posting.idempotency_key == driver_payout_key("o1", "d1")
    driver_total = sum(
        l["amount_minor"] for l in posting.lines if l["party_type"] == PartyType.DRIVER
    )
    assert driver_total == 1050
    tip_lines = [l for l in posting.lines if l["entry_type"] == EntryType.TIP]
    assert tip_lines[0]["amount_minor"] == 200


def test_driver_payout_of_nothing_writes_nothing():
    posting = build_driver_payout_posting(
        order_id="o1", driver_id="d1", driver_share_minor=0, tip_minor=0
    )
    assert posting.lines == []


def test_refund_posting_balances_and_is_keyed_by_refund():
    posting = build_refund_posting(
        refund_id="r1", payment_id="p1", order_id="o1", consumer_id="c1",
        amount_minor=3150,
    )
    posting.validate_balanced()
    assert posting.idempotency_key == "refund:r1:settled"
    consumer = [l for l in posting.lines if l["party_type"] == PartyType.CONSUMER][0]
    assert consumer["amount_minor"] == 3150

    assert build_refund_posting(
        refund_id="r1", payment_id="p1", order_id="o1", consumer_id="c1",
        amount_minor=0,
    ).lines == []


def test_end_to_end_order_ledger_nets_out_to_the_fee_breakdown():
    """Charge + driver payout must leave the platform with exactly its net."""
    breakdown = build_breakdown(
        subtotal_minor=2000,
        delivery_fee_minor=1000,
        service_fee_minor=150,
        tax_minor=100,
        tip_minor=200,
        discount_minor=300,
    )
    charge = build_charge_posting(
        payment_id="p1", order_id="o1", consumer_id="c1", merchant_id="m1",
        total_minor=breakdown.customer_total_minor, breakdown=breakdown,
    )
    payout = build_driver_payout_posting(
        order_id="o1", driver_id="d1",
        driver_share_minor=breakdown.driver_share_minor,
        tip_minor=breakdown.tip_minor,
        payment_id="p1",
    )
    charge.validate_balanced()
    payout.validate_balanced()

    totals = {}
    for line in charge.lines + payout.lines:
        totals[line["party_type"]] = totals.get(line["party_type"], 0) + line["amount_minor"]

    assert totals[PartyType.CONSUMER] == -breakdown.customer_total_minor
    assert totals[PartyType.MERCHANT] == breakdown.merchant_payout_minor
    assert totals[PartyType.DRIVER] == breakdown.driver_payout_minor
    assert totals[PartyType.PLATFORM] == breakdown.platform_net_minor
    assert sum(totals.values()) == 0


@pytest.mark.asyncio
async def test_a_partially_written_posting_is_completed_not_left_broken(monkeypatch):
    """A crash between two line inserts must not leave the ledger unbalanced."""
    posting = LedgerPosting(idempotency_key="pay-1", order_id="o1", payment_id="p1")
    posting.add(EntryType.CHARGE, PartyType.CONSUMER, -3150, party_id="c1")
    posting.add(EntryType.CHARGE, PartyType.PLATFORM, 3150, party_id=PLATFORM_PARTY_ID)

    orphan = SimpleNamespace(
        posting_id="post-orphan",
        idempotency_key="pay-1",
        entry_type=EntryType.CHARGE,
        party_type=PartyType.CONSUMER,
        party_id="c1",
        amount_minor=-3150,
        currency="USD",
    )
    rows = _install(monkeypatch, [orphan])

    written = await LedgerService.post(posting)
    assert LedgerService.residual(written) == 0
    assert len(rows) == 2
    # The completed line joins the original posting rather than starting a new one.
    assert rows[-1].posting_id == "post-orphan"


@pytest.mark.asyncio
async def test_a_concurrent_duplicate_line_is_absorbed(monkeypatch):
    from pymongo.errors import DuplicateKeyError

    rows = _install(monkeypatch)

    import app.finance.ledger as ledger_module

    real_entry = ledger_module.LedgerEntry
    calls = {"n": 0}

    class Clashing(real_entry):
        async def insert(self):
            calls["n"] += 1
            if calls["n"] == 2:
                raise DuplicateKeyError("ledger_posting_line_unique")
            return await real_entry.insert(self)

    monkeypatch.setattr(ledger_module, "LedgerEntry", Clashing)

    posting = LedgerPosting(idempotency_key="pay-2")
    posting.add(EntryType.CHARGE, PartyType.CONSUMER, -1000, party_id="c1")
    posting.add(EntryType.CHARGE, PartyType.PLATFORM, 1000, party_id=PLATFORM_PARTY_ID)

    written = await LedgerService.post(posting)
    # The losing line is not written twice and does not raise.
    assert len(written) == 1
    assert len(rows) == 1
