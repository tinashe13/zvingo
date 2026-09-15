"""Delta sync for the driver app's offline cache.

The driver app keeps a local copy of the orders it cares about and pulls only
what changed since its last successful sync. `last_version` is the Unix
timestamp of that last pull; the response carries a new one.

Two rules matter here:

* **Scope.** A driver sees the orders assigned to *them* plus the offers made
  *to them*. This used to return every order in ``OFFERED`` on the whole
  platform, which handed every driver the name, address and coordinates of every
  consumer with an open order.
* **Bounds.** Both queries are capped. An unbounded sync is a memory and latency
  hazard the moment the platform has real volume, and a client that falls far
  behind would otherwise try to pull the entire history in one response.
"""

import msgpack
import time
from datetime import datetime
from app.time_utils import utc_from_timestamp
import redis.asyncio as aioredis
from app.sync.schemas import SyncResponse
from app.order.models import Order
from app.order.state_machine import ACTIVE_DRIVER_STATES, OrderState
from app.config import settings
import structlog

logger = structlog.get_logger()

#: Most orders returned by one sync pull, per collection.
MAX_SYNC_ORDERS = 200


def _location(value):
    """A plain {lat, lng} dict for a Location model or raw GeoJSON, else None."""
    if value is None:
        return None
    lat = getattr(value, "lat", None)
    lng = getattr(value, "lng", None)
    if lat is None and isinstance(value, dict):
        coordinates = value.get("coordinates")
        if coordinates and len(coordinates) == 2:
            lng, lat = coordinates[0], coordinates[1]
    if lat is None or lng is None:
        return None
    return {"lat": lat, "lng": lng}


def _item(value) -> dict:
    """Normalize an order item that may be a model or a raw Mongo dict."""
    if isinstance(value, dict):
        source = value
    elif hasattr(value, "model_dump"):
        source = value.model_dump()
    else:
        source = {}
    return {
        "name": source.get("name", ""),
        "quantity": source.get("quantity", 1),
        "price": source.get("price", 0),
        "special_instructions": source.get("special_instructions"),
    }


def order_to_dict(order) -> dict:
    """The wire shape of an order in a sync delta."""
    state = getattr(order.state, "value", order.state)
    return {
        "id": str(order.id),
        "state": str(state),
        "total": order.total_amount,
        "pickup": _location(order.pickup_location),
        "dropoff": _location(order.dropoff_location),
        "items": [_item(i) for i in (order.items or [])],
    }


class SyncService:
    @staticmethod
    async def get_deltas(
        driver_id: str, last_version: int, limit: int = MAX_SYNC_ORDERS
    ) -> bytes:
        """Orders for this driver that changed since `last_version`.

        `last_version` is a Unix timestamp in seconds; 0 means "full sync".
        """
        limit = max(1, min(int(limit or MAX_SYNC_ORDERS), MAX_SYNC_ORDERS))
        now_ts = int(time.time())

        # If last_version is 0, this is a full sync - use epoch
        since = utc_from_timestamp(last_version) if last_version > 0 else datetime.min

        # 1. Orders this driver is carrying, changed since the last pull.
        assigned_orders = await Order.find(
            {
                "driver_id": driver_id,
                "state": {"$in": [s.value for s in ACTIVE_DRIVER_STATES]},
                "updated_at": {"$gte": since},
            }
        ).limit(limit).to_list()

        # 2. Offers addressed to this driver — never the whole platform's.
        offered_orders = await Order.find(
            {
                "state": OrderState.OFFERED.value,
                "offered_to": driver_id,
                "updated_at": {"$gte": since},
            }
        ).limit(limit).to_list()

        combined_orders = assigned_orders + offered_orders

        # Deduplicate by order id
        seen = set()
        unique_orders = []
        for o in combined_orders:
            oid = str(o.id)
            if oid not in seen:
                seen.add(oid)
                unique_orders.append(o)

        data = {"orders": [order_to_dict(o) for o in unique_orders]}
        has_more = (
            len(assigned_orders) >= limit or len(offered_orders) >= limit
        )

        response = SyncResponse(new_version=now_ts, data=data, has_more=has_more)

        # Record last sync timestamp in Redis (best effort — a bookkeeping
        # failure must not cost the driver their delta).
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        try:
            await r.set(f"sync_ts:{driver_id}", str(now_ts))
        except Exception as e:
            logger.warning("Could not record sync timestamp", driver_id=driver_id, error=str(e))
        finally:
            try:
                await r.close()
            except Exception:
                pass

        return msgpack.packb(response.model_dump(mode="json"))


sync_service = SyncService()
