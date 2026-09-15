"""Finance HTTP surface: exchange rates, analytics, driver earnings, reconciliation.

Two things are load-bearing here and easy to get wrong:

* **Authorisation.** Earnings and analytics are private financial records. Every
  ``/earnings/*`` and ``/analytics/*`` route checks that the caller *is* the
  driver or merchant in the path, or an admin. A driver reading another
  driver's earnings is a privacy breach, not a rounding error.
* **Rates.** ``POST /rates`` is admin-only and now writes an auditable
  :class:`~app.finance.exchange.ExchangeRate` record — who set what, when it
  became effective, and where it came from — before the cache is touched.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from typing import Any, Dict, Optional
from datetime import datetime, timedelta, date
from app.time_utils import utc_now
import redis.asyncio as aioredis
import json

import structlog

from app.config import settings
from app.finance import exchange
from app.finance.money import MoneyError, format_money, minor_to_float, to_minor
from app.order.models import Order
from app.order.state_machine import OrderState
from app.catalog.models import Restaurant
from app.auth.router import get_current_user, get_current_admin
from app.auth.models import User

logger = structlog.get_logger()

router = APIRouter()

DEFAULT_RATES = {"ZIG": 13.50, "ZAR": 18.50, "USD": 1.0}


def _is_admin(user: User) -> bool:
    return getattr(user, "role", "") == "admin"


def _assert_self_or_admin(subject_id: str, user: User, detail: str) -> None:
    """Allow the subject of a financial record, or an admin. Nobody else."""
    if subject_id == str(user.id) or _is_admin(user):
        return
    raise HTTPException(status_code=403, detail=detail)


class ExchangeRateResponse(BaseModel):
    base: str = "USD"
    rates: Dict[str, float]
    # Provenance per currency: effective_at, source, age and staleness, so a
    # client can tell a freshly published rate from a stale cached one.
    meta: Dict[str, Any] = {}


@router.get("/rates", response_model=ExchangeRateResponse)
async def get_exchange_rates():
    """Current rates with their provenance.

    ``rates`` keeps the flat ``{currency: float}`` shape existing clients read.
    ``meta`` adds ``effective_at``, ``source`` and ``is_stale`` per currency so
    nothing has to assume a cached number is fresh.
    """
    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        cached = await r.get(exchange.LEGACY_MAP_KEY)
        raw_meta = await r.get(exchange.META_CACHE_KEY)
    finally:
        await r.close()

    try:
        rates = json.loads(cached) if cached else dict(DEFAULT_RATES)
    except (TypeError, ValueError):
        rates = dict(DEFAULT_RATES)
    try:
        meta_payload = json.loads(raw_meta) if raw_meta else {}
    except (TypeError, ValueError):
        meta_payload = {}

    # Provenance is derived from the payload already fetched — one Redis round
    # trip for the whole response rather than one per currency.
    meta: Dict[str, Any] = {
        code: quote.as_dict()
        for code, quote in exchange.quotes_from_cache_payload(rates, meta_payload).items()
    }
    return ExchangeRateResponse(rates=rates, meta=meta)


@router.post("/rates")
async def update_exchange_rate(
    currency: str, rate: float, current_user: User = Depends(get_current_admin)
):
    """Publish a new exchange rate. **Admin only** (``get_current_admin``).

    The audit record is written first, then the cache — so a rate that is in
    use always has a record saying who published it and when it took effect.
    """
    try:
        quote = await exchange.record_rate(
            currency,
            rate,
            source="manual",
            set_by=str(getattr(current_user, "id", "") or ""),
        )
    except (exchange.UnsupportedCurrencyError, MoneyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        cached = await r.get(exchange.LEGACY_MAP_KEY)
    finally:
        await r.close()
    try:
        rates = json.loads(cached) if cached else dict(DEFAULT_RATES)
    except (TypeError, ValueError):
        rates = dict(DEFAULT_RATES)
    rates[quote.currency] = float(quote.rate)

    return {"status": "updated", "rates": rates, "published": quote.as_dict()}


@router.get("/rates/history/{currency}")
async def get_rate_history(
    currency: str,
    limit: int = Query(default=50, le=200),
    current_user: User = Depends(get_current_admin),
):
    """Audit trail of every rate published for a currency. **Admin only.**"""
    try:
        records = await exchange.rate_history(currency, limit=limit)
    except exchange.UnsupportedCurrencyError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return [
        {
            "currency": r.currency,
            "base": r.base,
            "rate": float(r.rate),
            "rate_micros": r.rate_micros,
            "effective_at": r.effective_at.isoformat(),
            "source": r.source,
            "set_by": r.set_by,
            "created_at": r.created_at.isoformat(),
        }
        for r in records
    ]


@router.get("/reconciliation")
async def get_reconciliation(
    stuck_minutes: int = Query(default=30, ge=1, le=1440),
    current_user: User = Depends(get_current_admin),
):
    """Detect money that has gone missing between systems. **Admin only.**

    Reports stuck payments, orders being fulfilled with no settled payment,
    settled payments with no ledger entries, unbalanced ledger postings, and
    refunds still owed.
    """
    from app.finance.reconciliation import run_reconciliation

    return await run_reconciliation(stuck_minutes)


@router.get("/ledger/order/{order_id}")
async def get_order_ledger(order_id: str, current_user: User = Depends(get_current_user)):
    """Every ledger entry for one order, and whether they balance.

    Visible to the order's consumer, merchant and driver, and to admins.
    """
    from app.finance.ledger import LedgerService

    order = await Order.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    viewer = str(current_user.id)
    if not _is_admin(current_user) and viewer not in (
        getattr(order, "consumer_id", None),
        getattr(order, "merchant_id", None),
        getattr(order, "driver_id", None),
    ):
        raise HTTPException(status_code=403, detail="Not authorized to view this ledger")

    entries = await LedgerService.entries_for_order(order_id)
    return {
        "order_id": order_id,
        "balanced": LedgerService.residual(entries) == 0,
        "residual_minor": LedgerService.residual(entries),
        "entries": [
            {
                "id": str(e.id),
                "posting_id": e.posting_id,
                "entry_type": e.entry_type.value,
                "party_type": e.party_type.value,
                "party_id": e.party_id,
                "amount_minor": e.amount_minor,
                "amount": format_money(e.amount_minor, e.currency),
                "currency": e.currency,
                "payment_id": e.payment_id,
                "memo": e.memo,
                "created_at": e.created_at.isoformat(),
            }
            for e in entries
        ],
    }


@router.get("/analytics/merchant/{merchant_id}")
async def get_merchant_analytics(merchant_id: str, current_user: User = Depends(get_current_user)):
    # Ownership check: merchants may only view their own analytics (admins may view any)
    _assert_self_or_admin(
        merchant_id, current_user, "Not authorized to view these analytics"
    )
    today_start = utc_now().replace(hour=0, minute=0, second=0, microsecond=0)

    # Delivered orders today
    today_delivered = await Order.find(
        Order.merchant_id == merchant_id,
        Order.state == OrderState.DELIVERED,
        Order.updated_at >= today_start,
    ).to_list()

    today_orders = len(today_delivered)
    # GMV is money: sum in integer cents, convert once for display.
    today_gmv_minor = sum(to_minor(o.total_amount or 0) for o in today_delivered)

    # All-time delivered
    all_delivered = await Order.find(
        Order.merchant_id == merchant_id,
        Order.state == OrderState.DELIVERED,
    ).count()

    all_gmv_orders = await Order.find(
        Order.merchant_id == merchant_id,
        Order.state == OrderState.DELIVERED,
    ).to_list()
    total_gmv_minor = sum(to_minor(o.total_amount or 0) for o in all_gmv_orders)

    # Active menu items
    restaurant = await Restaurant.find_one(Restaurant.merchant_id == merchant_id)
    active_items = 0
    if restaurant:
        active_items = sum(1 for item in restaurant.menu if item.is_available)

    # Average prep time (time from ACCEPTED to PICKED_UP)
    avg_prep_time = 18  # default fallback
    prep_times = []
    recent_orders = await Order.find(
        Order.merchant_id == merchant_id,
        Order.state == OrderState.DELIVERED,
    ).sort(-Order.created_at).limit(50).to_list()

    for order in recent_orders:
        accepted_at = None
        picked_up_at = None
        for event in order.events:
            if event.state == OrderState.ACCEPTED:
                accepted_at = event.timestamp
            elif event.state == OrderState.PICKED_UP:
                picked_up_at = event.timestamp
        if accepted_at and picked_up_at:
            prep_times.append((picked_up_at - accepted_at).total_seconds() / 60)

    if prep_times:
        avg_prep_time = round(sum(prep_times) / len(prep_times), 1)

    return {
        "today_orders": today_orders,
        "today_gmv": minor_to_float(today_gmv_minor),
        "today_gmv_minor": today_gmv_minor,
        "total_orders": all_delivered,
        "total_gmv": minor_to_float(total_gmv_minor),
        "total_gmv_minor": total_gmv_minor,
        "active_items": active_items,
        "avg_prep_time": avg_prep_time,
    }


async def _ledger_balance_for_driver(driver_id: str, since=None) -> Optional[int]:
    """Driver's net ledger balance, or ``None`` if the ledger is unavailable.

    Reported alongside the ``DriverEarning`` projection so any divergence
    between the two is visible rather than silently trusted.
    """
    try:
        from app.finance.ledger import LedgerService, PartyType

        return await LedgerService.balance_for_party(
            PartyType.DRIVER, driver_id, since=since
        )
    except Exception as exc:
        logger.debug("Driver ledger balance unavailable", error=str(exc))
        return None


@router.get("/earnings/driver/{driver_id}")
async def get_driver_earnings(driver_id: str, current_user: User = Depends(get_current_user)):
    """Get driver earnings summary (today + this week) from the earnings ledger."""
    # Ownership check: drivers may only view their own earnings (admins may view any)
    _assert_self_or_admin(
        driver_id, current_user, "Not authorized to view these earnings"
    )
    from app.finance.models import DriverEarning

    today_start = utc_now().replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today_start - timedelta(days=today_start.weekday())

    today_records = await DriverEarning.find(
        DriverEarning.driver_id == driver_id,
        DriverEarning.completed_at >= today_start,
    ).to_list()

    week_records = await DriverEarning.find(
        DriverEarning.driver_id == driver_id,
        DriverEarning.completed_at >= week_start,
    ).to_list()

    today_earnings_cents = sum(r.total_earning_cents for r in today_records)
    today_tip_cents = sum(r.tip_cents for r in today_records)
    week_earnings_cents = sum(r.total_earning_cents for r in week_records)
    week_tip_cents = sum(r.tip_cents for r in week_records)

    # Cash on hand = sum of cash-payment deliveries today (driver collects from customer)
    cash_on_hand_cents = sum(
        r.total_earning_cents for r in today_records if r.payment_method == "cash"
    )

    ledger_week_minor = await _ledger_balance_for_driver(driver_id, since=week_start)

    return {
        "today_deliveries": len(today_records),
        "today_earnings_cents": today_earnings_cents,
        "today_tip_cents": today_tip_cents,
        "week_deliveries": len(week_records),
        "week_earnings_cents": week_earnings_cents,
        "week_tip_cents": week_tip_cents,
        "cash_on_hand_cents": cash_on_hand_cents,
        # Independent view straight from the immutable ledger. When it is
        # present and differs from week_earnings_cents, something needs looking
        # at — the two are derived from different writes of the same event.
        "ledger_week_earnings_cents": ledger_week_minor,
        "ledger_matches": (
            None if ledger_week_minor is None else ledger_week_minor == week_earnings_cents
        ),
    }


@router.post("/earnings/record")
async def record_earning(
    order_id: str,
    driver_id: str,
    current_user: User = Depends(get_current_user),
):
    """
    Record a driver earning when a delivery is completed.
    Looks up the Order, calculates the driver's share, masks addresses,
    and creates a DriverEarning document plus the matching ledger posting.

    All money here is integer cents; the driver's share is a banker's-rounded
    split of the gross delivery fee, and the tip passes through in full.
    """
    # Ownership: a driver may only record their own earnings (admins may record any).
    _assert_self_or_admin(
        driver_id, current_user, "Cannot record earnings for another driver"
    )

    from app.finance.models import DriverEarning, mask_address
    from app.finance.fee_calculator import (
        delivery_fee_minor_from_coords,
        driver_share_minor,
        haversine_km,
    )
    from app.catalog.models import Restaurant

    # Prevent duplicate recording
    existing = await DriverEarning.find_one(
        DriverEarning.order_id == order_id,
        DriverEarning.driver_id == driver_id,
    )
    if existing:
        return {
            "status": "already_recorded",
            "earning_id": str(existing.id),
            "total_earning_cents": existing.total_earning_cents,
        }

    order = await Order.get(order_id)
    if not order:
        return {"status": "error", "detail": "Order not found"}

    # Resolve merchant name
    merchant_name = "Unknown"
    restaurant = None
    try:
        restaurant = await Restaurant.find_one(
            Restaurant.merchant_id == order.merchant_id
        )
        if not restaurant:
            restaurant = await Restaurant.get(order.merchant_id)
        if restaurant:
            merchant_name = restaurant.name
    except Exception:
        restaurant = None

    # Coordinates
    pickup_lng, pickup_lat = (
        order.pickup_location.lng if order.pickup_location else 0,
        order.pickup_location.lat if order.pickup_location else 0,
    )
    dropoff_lng, dropoff_lat = (
        order.dropoff_location.lng if order.dropoff_location else 0,
        order.dropoff_location.lat if order.dropoff_location else 0,
    )

    # Use the fee actually charged on the order when it has one; only fall back
    # to recomputing from coordinates when the order carries no fee.
    if order.delivery_fee and order.delivery_fee > 0:
        gross_cents = to_minor(order.delivery_fee)
        dist_km = haversine_km(pickup_lat, pickup_lng, dropoff_lat, dropoff_lng)
    else:
        gross_cents, _, dist_km = delivery_fee_minor_from_coords(
            pickup_lat, pickup_lng, dropoff_lat, dropoff_lng
        )

    driver_cents = driver_share_minor(gross_cents)
    tip_cents = to_minor(order.tip_amount) if order.tip_amount else 0
    total_cents = driver_cents + tip_cents

    # Masked addresses
    pickup_area = mask_address(order.delivery_instructions or "")
    # Use delivery_instructions for dropoff if set; otherwise try to build from coords
    dropoff_addr = order.delivery_instructions or ""
    dropoff_area = mask_address(dropoff_addr)

    # Try to get better pickup address from restaurant
    try:
        if restaurant and getattr(restaurant, "address", None):
            pickup_area = mask_address(restaurant.address)
    except Exception:
        pass

    # Payment method
    payment_method = "cash"
    payment_id = None
    try:
        from app.payment.models import Payment
        payment = await Payment.find_one(Payment.order_id == order_id)
        if payment:
            pm = payment.method
            if hasattr(pm, 'value'):
                pm = pm.value
            payment_method = str(pm).lower()
            payment_id = str(payment.id)
    except Exception:
        pass

    earning = DriverEarning(
        driver_id=driver_id,
        order_id=order_id,
        merchant_name=merchant_name,
        pickup_area=pickup_area,
        dropoff_area=dropoff_area,
        delivery_fee_cents=gross_cents,
        driver_earning_cents=driver_cents,
        tip_cents=tip_cents,
        total_earning_cents=total_cents,
        payment_method=payment_method,
        # The driver is owed USD regardless of the currency the customer was
        # charged in; the FX difference is the platform's to carry.
        currency="USD",
        distance_km=round(dist_km, 2),
        completed_at=utc_now(),
        created_date=date.today().isoformat(),
    )
    await earning.insert()

    # Post the immutable ledger entries for the payout. Idempotent by
    # (order, driver), so a retried call cannot pay the driver twice. A ledger
    # outage must not block the driver's earnings record, so it is logged and
    # surfaced by /finance/reconciliation rather than failing the request.
    ledger_posted = False
    try:
        from app.finance.ledger import LedgerService
        from app.finance.postings import build_driver_payout_posting

        posting = build_driver_payout_posting(
            order_id=order_id,
            driver_id=driver_id,
            driver_share_minor=driver_cents,
            tip_minor=tip_cents,
            # The driver's share is denominated in USD regardless of the
            # currency the customer was charged in.
            currency="USD",
            payment_id=payment_id,
        )
        await LedgerService.post(posting)
        earning.ledger_posting_key = posting.idempotency_key
        await earning.save()
        ledger_posted = True
    except Exception as exc:
        logger.error(
            "Driver payout ledger posting failed",
            order_id=order_id,
            driver_id=driver_id,
            error=str(exc),
        )

    return {
        "status": "recorded",
        "earning_id": str(earning.id),
        "total_earning_cents": total_cents,
        "driver_earning_cents": driver_cents,
        "delivery_fee_cents": gross_cents,
        "tip_cents": tip_cents,
        "ledger_posted": ledger_posted,
    }


@router.get("/earnings/driver/{driver_id}/daily")
async def get_daily_breakdown(
    driver_id: str,
    days: int = Query(default=30, le=90),
    current_user: User = Depends(get_current_user),
):
    """Get daily earnings aggregation for the last N days."""
    # Ownership check: drivers may only view their own earnings (admins may view any)
    _assert_self_or_admin(
        driver_id, current_user, "Not authorized to view these earnings"
    )
    from app.finance.models import DriverEarning

    cutoff = utc_now() - timedelta(days=days)
    records = await DriverEarning.find(
        DriverEarning.driver_id == driver_id,
        DriverEarning.completed_at >= cutoff,
    ).sort(-DriverEarning.completed_at).to_list()

    # Aggregate by date
    daily: Dict[str, dict] = {}
    for r in records:
        d = r.created_date
        if d not in daily:
            daily[d] = {
                "date": d,
                "earnings_cents": 0,
                "tip_cents": 0,
                "trip_count": 0,
                "cash_collected_cents": 0,
            }
        daily[d]["earnings_cents"] += r.total_earning_cents
        daily[d]["tip_cents"] += r.tip_cents
        daily[d]["trip_count"] += 1
        if r.payment_method == "cash":
            daily[d]["cash_collected_cents"] += r.total_earning_cents

    # Sort descending by date
    result = sorted(daily.values(), key=lambda x: x["date"], reverse=True)
    return result


@router.get("/earnings/driver/{driver_id}/history")
async def get_earnings_history(
    driver_id: str,
    start_date: Optional[str] = Query(default=None, description="YYYY-MM-DD"),
    end_date: Optional[str] = Query(default=None, description="YYYY-MM-DD"),
    payment_method: Optional[str] = Query(default=None),
    min_amount_cents: Optional[int] = Query(default=None),
    merchant_name: Optional[str] = Query(default=None),
    area: Optional[str] = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, le=100),
    current_user: User = Depends(get_current_user),
):
    """
    Paginated delivery history with filters for driver reconciliation.
    Addresses are already masked at recording time.
    """
    # Ownership check: drivers may only view their own history (admins may view any)
    _assert_self_or_admin(
        driver_id, current_user, "Not authorized to view this history"
    )
    from app.finance.models import DriverEarning

    # Build query filters
    filters = [DriverEarning.driver_id == driver_id]

    if start_date:
        try:
            sd = datetime.fromisoformat(start_date)
            filters.append(DriverEarning.completed_at >= sd)
        except ValueError:
            pass

    if end_date:
        try:
            ed = datetime.fromisoformat(end_date) + timedelta(days=1)
            filters.append(DriverEarning.completed_at < ed)
        except ValueError:
            pass

    if payment_method:
        filters.append(DriverEarning.payment_method == payment_method.lower())

    if min_amount_cents is not None:
        filters.append(DriverEarning.total_earning_cents >= min_amount_cents)

    # For merchant_name and area, do post-query filtering since Beanie
    # doesn't easily support case-insensitive contains on regular fields.
    # In production you'd use MongoDB $regex in raw queries.
    total_count = await DriverEarning.find(*filters).count()
    skip = (page - 1) * page_size

    records = await (
        DriverEarning.find(*filters)
        .sort(-DriverEarning.completed_at)
        .skip(skip)
        .limit(page_size)
        .to_list()
    )

    # Post-filter by merchant_name and area (case-insensitive contains)
    if merchant_name:
        mn_lower = merchant_name.lower()
        records = [r for r in records if mn_lower in r.merchant_name.lower()]

    if area:
        area_lower = area.lower()
        records = [
            r for r in records
            if area_lower in r.pickup_area.lower()
            or area_lower in r.dropoff_area.lower()
        ]

    return {
        "page": page,
        "page_size": page_size,
        "total": total_count,
        "records": [
            {
                "id": str(r.id),
                "order_id": r.order_id,
                "merchant_name": r.merchant_name,
                "pickup_area": r.pickup_area,
                "dropoff_area": r.dropoff_area,
                "delivery_fee_cents": r.delivery_fee_cents,
                "driver_earning_cents": r.driver_earning_cents,
                "tip_cents": r.tip_cents,
                "total_earning_cents": r.total_earning_cents,
                "payment_method": r.payment_method,
                "distance_km": r.distance_km,
                "completed_at": r.completed_at.isoformat(),
            }
            for r in records
        ],
    }
