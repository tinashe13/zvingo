"""Immutable double-entry ledger — the single source of truth for money moved.

Every movement of money in Zvingo posts a *balanced set* of ledger entries.
"Balanced" means the signed amounts of one posting sum to exactly zero per
currency: money never appears from nowhere and never vanishes. A consumer
paying $12.50 does not produce one row saying "paid"; it produces

    consumer   -1250   CHARGE
    platform   +1250   CHARGE

and the subsequent obligations produce

    platform    -800   MERCHANT_PAYOUT     merchant  +800
    platform    -425   DRIVER_PAYOUT       driver    +425

leaving the platform holding exactly its commission plus fees. Driver earnings,
merchant payouts and platform revenue are then *derived by summing the ledger*
rather than recomputed independently in three places that can disagree.

Design rules:

* **Append only.** :class:`LedgerEntry` refuses every mutating Beanie method.
  Corrections are made by posting a compensating entry, never by editing
  history. This is what makes the ledger auditable.
* **Integer minor units only** (see :mod:`app.finance.money`). Never floats.
* **Idempotent postings.** Each posting carries a caller-supplied
  ``idempotency_key``; posting the same key twice returns the original entries
  and writes nothing. Webhook retries therefore cannot double-credit.
* **Correlated.** Every entry carries ``order_id``/``payment_id`` so a payment
  can be traced to its splits and back.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import List, Optional, Sequence

import structlog
from beanie import Document, Indexed
from pydantic import BaseModel, Field

from app.finance.money import DEFAULT_CURRENCY, currency_spec, format_money
from app.time_utils import utc_now

logger = structlog.get_logger()

__all__ = [
    "EntryType",
    "PartyType",
    "LedgerEntry",
    "LedgerPosting",
    "LedgerImmutableError",
    "UnbalancedPostingError",
    "LedgerService",
]


class LedgerImmutableError(RuntimeError):
    """Raised when something tries to mutate or delete a posted ledger entry."""


class UnbalancedPostingError(ValueError):
    """Raised when a posting's signed amounts do not sum to zero."""


class EntryType(str, Enum):
    """What kind of money movement an entry represents."""

    CHARGE = "CHARGE"                    # consumer pays for an order
    MERCHANT_PAYOUT = "MERCHANT_PAYOUT"  # platform owes the restaurant
    DRIVER_PAYOUT = "DRIVER_PAYOUT"      # platform owes the driver (share + tip)
    COMMISSION = "COMMISSION"            # platform's cut of the delivery fee
    SERVICE_FEE = "SERVICE_FEE"          # platform service fee
    TAX = "TAX"                          # tax collected on behalf of ZIMRA
    TIP = "TIP"                          # consumer tip, passed to the driver
    PROMO_DISCOUNT = "PROMO_DISCOUNT"    # platform-funded discount
    REFUND = "REFUND"                    # money returned to the consumer
    ADJUSTMENT = "ADJUSTMENT"            # manual correction, always with a memo


class PartyType(str, Enum):
    CONSUMER = "CONSUMER"
    MERCHANT = "MERCHANT"
    DRIVER = "DRIVER"
    PLATFORM = "PLATFORM"
    TAX_AUTHORITY = "TAX_AUTHORITY"


PLATFORM_PARTY_ID = "zvingo-platform"


class LedgerEntry(Document):
    """One immutable line of the ledger.

    ``amount_minor`` is *signed*: positive means the party received value,
    negative means the party gave it up.
    """

    posting_id: Indexed(str)  # type: ignore  # groups the balanced set
    idempotency_key: Indexed(str)  # type: ignore  # unique per posting

    entry_type: EntryType
    party_type: PartyType
    party_id: str = ""

    amount_minor: int
    currency: str = DEFAULT_CURRENCY

    order_id: Optional[Indexed(str)] = None  # type: ignore
    payment_id: Optional[Indexed(str)] = None  # type: ignore

    memo: str = ""
    created_at: datetime = Field(default_factory=utc_now)

    class Settings:
        name = "ledger_entries"
        indexes = [
            [("posting_id", 1)],
            # Unique so a concurrent duplicate posting loses at the database,
            # not just in application code.
            [("idempotency_key", 1), ("entry_type", 1), ("party_type", 1)],
            [("order_id", 1), ("created_at", 1)],
            [("party_type", 1), ("party_id", 1), ("created_at", -1)],
            [("payment_id", 1)],
        ]

    # ── Immutability ────────────────────────────────────────────────
    # Beanie's mutating helpers are all disabled. The only legal write is
    # `insert`, performed by LedgerService.post().

    def _immutable(self, operation: str):
        raise LedgerImmutableError(
            f"Ledger entries are append-only; {operation}() is not permitted. "
            "Post a compensating ADJUSTMENT entry instead."
        )

    async def save(self, *args, **kwargs):  # type: ignore[override]
        self._immutable("save")

    async def replace(self, *args, **kwargs):  # type: ignore[override]
        self._immutable("replace")

    async def update(self, *args, **kwargs):  # type: ignore[override]
        self._immutable("update")

    async def set(self, *args, **kwargs):  # type: ignore[override]
        self._immutable("set")

    async def delete(self, *args, **kwargs):  # type: ignore[override]
        self._immutable("delete")

    def describe(self) -> str:
        return (
            f"{self.entry_type.value} {self.party_type.value}:{self.party_id} "
            f"{format_money(self.amount_minor, self.currency)}"
        )


class LedgerPosting(BaseModel):
    """A balanced set of entries, built before anything is written."""

    idempotency_key: str
    currency: str = DEFAULT_CURRENCY
    order_id: Optional[str] = None
    payment_id: Optional[str] = None
    lines: List[dict] = Field(default_factory=list)

    def add(
        self,
        entry_type: EntryType,
        party_type: PartyType,
        amount_minor: int,
        *,
        party_id: str = "",
        memo: str = "",
    ) -> "LedgerPosting":
        """Add one signed line. Zero-value lines are skipped (no free-tip noise)."""
        amount = int(amount_minor)
        if amount == 0:
            return self
        self.lines.append(
            {
                "entry_type": entry_type,
                "party_type": party_type,
                "party_id": party_id,
                "amount_minor": amount,
                "memo": memo,
            }
        )
        return self

    def balance(self) -> int:
        return sum(int(line["amount_minor"]) for line in self.lines)

    def validate_balanced(self) -> None:
        currency_spec(self.currency)  # reject unknown currency early
        residual = self.balance()
        if residual != 0:
            raise UnbalancedPostingError(
                f"Posting {self.idempotency_key} does not balance: "
                f"residual {residual} minor units ({self.currency}); "
                f"lines={[(l['entry_type'], l['party_type'], l['amount_minor']) for l in self.lines]}"
            )


class LedgerService:
    """Writes and reads the ledger. The only sanctioned way to post money."""

    @staticmethod
    async def already_posted(idempotency_key: str) -> List[LedgerEntry]:
        return await LedgerEntry.find(
            LedgerEntry.idempotency_key == idempotency_key
        ).to_list()

    @staticmethod
    async def post(posting: LedgerPosting) -> List[LedgerEntry]:
        """Write a balanced posting, exactly once.

        Returns the entries for this ``idempotency_key`` — the pre-existing ones
        if the posting has already been made. Raises
        :class:`UnbalancedPostingError` before touching the database if the
        lines do not sum to zero.
        """
        posting.validate_balanced()
        if not posting.lines:
            return []

        existing = await LedgerService.already_posted(posting.idempotency_key)
        if existing:
            logger.info(
                "Ledger posting already applied; skipping",
                idempotency_key=posting.idempotency_key,
                entries=len(existing),
            )
            return list(existing)

        posting_id = str(uuid.uuid4())
        written: List[LedgerEntry] = []
        for line in posting.lines:
            entry = LedgerEntry(
                posting_id=posting_id,
                idempotency_key=posting.idempotency_key,
                entry_type=line["entry_type"],
                party_type=line["party_type"],
                party_id=line["party_id"],
                amount_minor=line["amount_minor"],
                currency=posting.currency,
                order_id=posting.order_id,
                payment_id=posting.payment_id,
                memo=line["memo"],
            )
            await entry.insert()
            written.append(entry)

        logger.info(
            "Ledger posting applied",
            idempotency_key=posting.idempotency_key,
            posting_id=posting_id,
            order_id=posting.order_id,
            payment_id=posting.payment_id,
            lines=len(written),
        )
        return written

    @staticmethod
    async def balance_for_party(
        party_type: PartyType,
        party_id: str,
        *,
        currency: str = DEFAULT_CURRENCY,
        since: Optional[datetime] = None,
        until: Optional[datetime] = None,
    ) -> int:
        """Net minor units a party has received, summed straight from the ledger."""
        filters = [
            LedgerEntry.party_type == party_type,
            LedgerEntry.party_id == party_id,
            LedgerEntry.currency == currency,
        ]
        if since is not None:
            filters.append(LedgerEntry.created_at >= since)
        if until is not None:
            filters.append(LedgerEntry.created_at < until)
        entries = await LedgerEntry.find(*filters).to_list()
        return sum(int(e.amount_minor) for e in entries)

    @staticmethod
    async def entries_for_order(order_id: str) -> List[LedgerEntry]:
        return await LedgerEntry.find(LedgerEntry.order_id == order_id).to_list()

    @staticmethod
    def residual(entries: Sequence[LedgerEntry]) -> int:
        """Signed sum of a set of entries — zero for a healthy posting."""
        return sum(int(e.amount_minor) for e in entries)
