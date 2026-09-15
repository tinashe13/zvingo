import structlog
import json
import math
from datetime import datetime
from app.time_utils import utc_now
from typing import Optional
import redis.asyncio as aioredis

from app.config import settings

logger = structlog.get_logger()

# Average driving speed in Harare (km/h) for time estimates
AVG_SPEED_KMH = 25.0


def _offer_timeout_seconds() -> int:
    """How long a driver has to answer an offer.

    Read from the dispatch engine rather than duplicated, so the countdown the
    driver sees always matches the deadline the server actually enforces.
    Imported lazily because dispatch imports notification.
    """
    try:
        from app.dispatch.service import OFFER_TIMEOUT_SECONDS

        return int(OFFER_TIMEOUT_SECONDS)
    except Exception:
        return 45


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Compute distance in km between two lat/lng points."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlng / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def mask_name(full_name: str) -> str:
    """Mask last name: 'John Smith' -> 'John S.'"""
    parts = full_name.strip().split()
    if len(parts) <= 1:
        return full_name
    return f"{parts[0]} {parts[-1][0]}."


class NotificationService:
    @staticmethod
    async def send_offer(driver_id: str, order_id: str, driver_dist_km: float = 0.0):
        """
        Send a rich delivery offer to a driver.
        Looks up order, restaurant, and consumer to build complete offer payload.
        """
        logger.info("Sending Offer", driver_id=driver_id, order_id=order_id, method="FCM+SSE")

        # ── Build enriched payload ────────────────────────────
        offer_data = await NotificationService._build_offer_payload(
            order_id, driver_id, driver_dist_km
        )

        # ── FCM push notification ─────────────────────────────
        from app.auth.models import User
        from app.notification.preferences import should_notify
        user = await User.get(driver_id)
        if user and user.fcm_token and await should_notify(driver_id, "driver_offers"):
            from app.notification.fcm import send_push_notification
            merchant_name = offer_data.get("merchant_name", "A restaurant")
            fee = offer_data.get("delivery_fee_cents", 0) / 100
            await send_push_notification(
                fcm_token=user.fcm_token,
                title=f"New Delivery — ${fee:.2f}",
                body=f"Pickup from {merchant_name}",
                data={"type": "offer", "order_id": order_id,
                      "payload": json.dumps(offer_data)},
            )
        else:
            logger.info("No FCM push for driver, SSE only", driver_id=driver_id)

        # ── Redis: pub/sub + pending-offer cache ─────────────
        # Publish fires the offer to any currently connected WebSocket.
        # setex stores it as a fallback so drivers that connect slightly
        # after the publish (race condition window) can still pick it up.
        # TTL matches the offer timeout so stale offers are never delivered.
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        offer_ttl = offer_data.get("timeout_seconds", _offer_timeout_seconds())
        offer_json = json.dumps({"event": "offer", **offer_data})
        try:
            await r.publish(f"driver_{driver_id}", offer_json)
            await r.setex(f"driver_pending_offer_{driver_id}", offer_ttl, offer_json)
        finally:
            await r.close()

    @staticmethod
    async def _build_offer_payload(order_id: str, driver_id: str, driver_dist_km: float) -> dict:
        """Build a rich offer payload with all details the driver needs."""
        from app.order.models import Order
        from app.catalog.models import Restaurant
        from app.auth.models import User

        order = await Order.get(order_id)
        if not order:
            logger.error("Order not found for offer", order_id=order_id)
            return {"order_id": order_id, "event": "offer"}

        # Restaurant info
        merchant_name = "Unknown Restaurant"
        merchant_address = ""
        try:
            restaurant = await Restaurant.find_one(
                Restaurant.merchant_id == order.merchant_id
            )
            if not restaurant:
                # Fallback: order.merchant_id may be the restaurant's document _id
                restaurant = await Restaurant.get(order.merchant_id)
            if restaurant:
                merchant_name = restaurant.name
                merchant_address = restaurant.address or ""
        except Exception:
            pass

        # Consumer info (masked name)
        customer_name = "Customer"
        try:
            consumer = await User.get(order.consumer_id)
            if consumer and consumer.full_name:
                customer_name = mask_name(consumer.full_name)
        except Exception:
            pass

        # Locations
        pickup_lng, pickup_lat = (
            order.pickup_location.lng if order.pickup_location else 0,
            order.pickup_location.lat if order.pickup_location else 0,
        )
        dropoff_lng, dropoff_lat = (
            order.dropoff_location.lng if order.dropoff_location else 0,
            order.dropoff_location.lat if order.dropoff_location else 0,
        )

        # Delivery distance (pickup → dropoff)
        delivery_dist_km = haversine_km(pickup_lat, pickup_lng, dropoff_lat, dropoff_lng)

        # Pickup distance is passed from dispatch (driver → pickup)
        pickup_dist_km = driver_dist_km if driver_dist_km > 0 else 0

        # Time estimates
        pickup_time_min = max(1, round((pickup_dist_km / AVG_SPEED_KMH) * 60)) if pickup_dist_km > 0 else 0
        delivery_time_min = max(1, round((delivery_dist_km / AVG_SPEED_KMH) * 60))
        total_time_min = pickup_time_min + delivery_time_min + 5  # +5 for pickup wait

        # Items summary
        items = order.items or []
        item_count = sum(
            i.quantity if hasattr(i, 'quantity') else i.get("quantity", 1)
            for i in items
        )
        if items:
            first_item = items[0]
            name = first_item.name if hasattr(first_item, 'name') else first_item.get("name", "item")
            items_summary = f"{name}" + (f" +{item_count - 1} more" if item_count > 1 else "")
        else:
            items_summary = "Order"

        # Delivery fee in cents — auto-calculate if the order has no fee set
        if order.delivery_fee and order.delivery_fee > 0:
            delivery_fee_cents = int(order.delivery_fee * 100)
        else:
            from app.finance.fee_calculator import calculate_delivery_fee
            gross_fee, _ = calculate_delivery_fee(delivery_dist_km)
            delivery_fee_cents = int(gross_fee * 100)

        tip_cents = int(order.tip_amount * 100) if order.tip_amount else 0
        total_cents = int(order.total_amount * 100) if order.total_amount else 0
        order_subtotal_cents = total_cents - delivery_fee_cents - tip_cents
        if order_subtotal_cents < 0:
            order_subtotal_cents = 0

        # Build short ID from order_id
        short_id = f"ZV{str(order_id)[-6:].upper()}"

        return {
            "order_id": str(order_id),
            "short_id": short_id,
            "merchant_name": merchant_name,
            "merchant_address": merchant_address,
            "pickup_lat": pickup_lat,
            "pickup_lng": pickup_lng,
            "customer_name": customer_name,
            "customer_address": order.delivery_instructions or "",
            "delivery_lat": dropoff_lat,
            "delivery_lng": dropoff_lng,
            "delivery_fee_cents": delivery_fee_cents,
            "tip_cents": tip_cents,
            "order_subtotal_cents": order_subtotal_cents,
            "total_cents": total_cents,
            "estimated_distance_km": round(delivery_dist_km + pickup_dist_km, 1),
            "pickup_distance_km": round(pickup_dist_km, 1),
            "estimated_time_minutes": total_time_min,
            "pickup_time_minutes": pickup_time_min,
            "payment_method": 0,  # 0=cash, 1=ecocash — extend later
            "order_type": "delivery",
            "items_summary": items_summary,
            "item_count": item_count,
            "timeout_seconds": _offer_timeout_seconds(),
            "timestamp": utc_now().isoformat(),
        }

    @staticmethod
    async def notify_merchant(merchant_id: str, order_id: str):
        logger.info("Notifying Merchant", merchant_id=merchant_id, order_id=order_id, method="SSE")

        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        try:
            await r.publish(f"merchant_{merchant_id}", json.dumps({
                "event": "new_order",
                "order_id": order_id,
                "timestamp": utc_now().isoformat(),
            }))
        finally:
            await r.close()

    @staticmethod
    async def notify_consumer(consumer_id: str, order_id: str, event: str, data: dict = None):
        logger.info(
            "Notifying Consumer",
            consumer_id=consumer_id,
            order_id=order_id,
            notification_event=event,
        )

        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        try:
            payload = {
                "event": event,
                "order_id": order_id,
                "timestamp": utc_now().isoformat(),
            }
            if data:
                payload.update(data)
            await r.publish(f"consumer_{consumer_id}", json.dumps(payload))
        finally:
            await r.close()

        # Also send FCM push to consumer, subject to their preferences.
        from app.auth.models import User
        from app.notification.preferences import should_notify
        user = await User.get(consumer_id)
        if user and user.fcm_token and await should_notify(consumer_id, "order_updates"):
            from app.notification.fcm import send_push_notification
            titles = {
                "order_accepted": "Driver on the way!",
                "picked_up": "Order picked up!",
                "delivered": "Order delivered!",
            }
            await send_push_notification(
                fcm_token=user.fcm_token,
                title=titles.get(event, "Order Update"),
                body=f"Your order #{order_id[-6:]} has been updated",
                data={"type": event, "order_id": order_id},
            )


notification_service = NotificationService()
