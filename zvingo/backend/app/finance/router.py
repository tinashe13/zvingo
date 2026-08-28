from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from typing import Dict, Optional, List
from datetime import datetime, timedelta, date
from app.time_utils import utc_now
import redis.asyncio as aioredis
import json
import math

from app.config import settings
from app.order.models import Order
from app.order.state_machine import OrderState
from app.catalog.models import Restaurant
from app.auth.router import get_current_user, get_current_admin
from app.auth.models import User

router = APIRouter()

DEFAULT_RATES = {"ZIG": 13.50, "ZAR": 18.50, "USD": 1.0}


class ExchangeRateResponse(BaseModel):
    base: str = "USD"
    rates: Dict[str, float]


@router.get("/rates", response_model=ExchangeRateResponse)
async def get_exchange_rates():
    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        cached = await r.get("exchange_rates")
        if cached:
            return ExchangeRateResponse(rates=json.loads(cached))
        return ExchangeRateResponse(rates=DEFAULT_RATES)
    finally:
        await r.close()


@router.post("/rates")
async def update_exchange_rate(
    currency: str, rate: float, current_user: User = Depends(get_current_admin)
):
    r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        cached = await r.get("exchange_rates")
        rates = json.loads(cached) if cached else dict(DEFAULT_RATES)
        rates[currency.upper()] = rate
        await r.set("exchange_rates", json.dumps(rates), ex=3600)  # 1 hour TTL
        return {"status": "updated", "rates": rates}
    finally:
        await r.close()


@router.get("/analytics/merchant/{merchant_id}")
async def get_merchant_analytics(merchant_id: str, current_user: User = Depends(get_current_user)):
    # Ownership check: merchants may only view their own analytics
    if merchant_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to view these analytics")
    today_start = utc_now().replace(hour=0, minute=0, second=0, microsecond=0)

    # Delivered orders today
    today_delivered = await Order.find(
        Order.merchant_id == merchant_id,
        Order.state == OrderState.DELIVERED,
        Order.updated_at >= today_start,
    ).to_list()

    today_orders = len(today_delivered)
    today_gmv = sum(o.total_amount for o in today_delivered)

    # All-time delivered
    all_delivered = await Order.find(
        Order.merchant_id == merchant_id,
        Order.state == OrderState.DELIVERED,
    ).count()

    all_gmv_orders = await Order.find(
        Order.merchant_id == merchant_id,
        Order.state == OrderState.DELIVERED,
    ).to_list()
    total_gmv = sum(o.total_amount for o in all_gmv_orders)

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
        "today_gmv": round(today_gmv, 2),
        "total_orders": all_delivered,
        "total_gmv": round(total_gmv, 2),
        "active_items": active_items,
        "avg_prep_time": avg_prep_time,
    }


@router.get("/earnings/driver/{driver_id}")
async def get_driver_earnings(driver_id: str, current_user: User = Depends(get_current_user)):
    """Get driver earnings summary (today + this week) from the earnings ledger."""
    # Ownership check: drivers may only view their own earnings
    if driver_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to view these earnings")
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

    return {
        "today_deliveries": len(today_records),
        "today_earnings_cents": today_earnings_cents,
        "today_tip_cents": today_tip_cents,
        "week_deliveries": len(week_records),
        "week_earnings_cents": week_earnings_cents,
        "week_tip_cents": week_tip_cents,
        "cash_on_hand_cents": cash_on_hand_cents,
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
    and creates a DriverEarning document.
    """
    # Ownership: a driver may only record their own earnings.
    if driver_id != str(current_user.id):
        raise HTTPException(
            status_code=403, detail="Cannot record earnings for another driver"
        )

    from app.finance.models import DriverEarning, mask_address
    from app.finance.fee_calculator import (
        calculate_delivery_fee_from_coords,
        DRIVER_SHARE_RATIO,
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
    try:
        restaurant = await Restaurant.find_one(
            Restaurant.merchant_id == order.merchant_id
        )
        if not restaurant:
            restaurant = await Restaurant.get(order.merchant_id)
        if restaurant:
            merchant_name = restaurant.name
    except Exception:
        pass

    # Coordinates
    pickup_lng, pickup_lat = (
        order.pickup_location.lng if order.pickup_location else 0,
        order.pickup_location.lat if order.pickup_location else 0,
    )
    dropoff_lng, dropoff_lat = (
        order.dropoff_location.lng if order.dropoff_location else 0,
        order.dropoff_location.lat if order.dropoff_location else 0,
    )

    # Calculate delivery fee if not set on the order
    if order.delivery_fee and order.delivery_fee > 0:
        gross_fee = order.delivery_fee
        from app.finance.fee_calculator import haversine_km
        dist_km = haversine_km(pickup_lat, pickup_lng, dropoff_lat, dropoff_lng)
    else:
        gross_fee, _, dist_km = calculate_delivery_fee_from_coords(
            pickup_lat, pickup_lng, dropoff_lat, dropoff_lng
        )

    gross_cents = int(gross_fee * 100)
    driver_cents = int(round(gross_fee * DRIVER_SHARE_RATIO, 2) * 100)
    tip_cents = int(order.tip_amount * 100) if order.tip_amount else 0
    total_cents = driver_cents + tip_cents

    # Masked addresses
    pickup_area = mask_address(order.delivery_instructions or "")
    # Use delivery_instructions for dropoff if set; otherwise try to build from coords
    dropoff_addr = order.delivery_instructions or ""
    dropoff_area = mask_address(dropoff_addr)

    # Try to get better pickup address from restaurant
    try:
        if restaurant and hasattr(restaurant, 'address') and restaurant.address:
            pickup_area = mask_address(restaurant.address)
    except Exception:
        pass

    # Payment method
    payment_method = "cash"
    try:
        from app.payment.models import Payment
        payment = await Payment.find_one(Payment.order_id == order_id)
        if payment:
            pm = payment.method
            if hasattr(pm, 'value'):
                pm = pm.value
            payment_method = str(pm).lower()
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
        distance_km=round(dist_km, 2),
        completed_at=utc_now(),
        created_date=date.today().isoformat(),
    )
    await earning.insert()

    return {
        "status": "recorded",
        "earning_id": str(earning.id),
        "total_earning_cents": total_cents,
        "driver_earning_cents": driver_cents,
        "tip_cents": tip_cents,
    }


@router.get("/earnings/driver/{driver_id}/daily")
async def get_daily_breakdown(
    driver_id: str,
    days: int = Query(default=30, le=90),
    current_user: User = Depends(get_current_user),
):
    """Get daily earnings aggregation for the last N days."""
    # Ownership check: drivers may only view their own earnings
    if driver_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to view these earnings")
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
    # Ownership check: drivers may only view their own history
    if driver_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to view this history")
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

    # Text-based filters use regex
    query = DriverEarning.find(*filters)

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

