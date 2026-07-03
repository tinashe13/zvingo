import msgpack
import time
from datetime import datetime
from typing import List
import redis.asyncio as aioredis
from app.sync.schemas import SyncRequest, SyncResponse
from app.order.models import Order
from app.auth.models import User
from app.order.state_machine import OrderState
from app.config import settings
import structlog

logger = structlog.get_logger()


class SyncService:
    @staticmethod
    async def get_deltas(driver_id: str, last_version: int) -> bytes:
        """
        Delta sync: use Redis timestamps to track last sync per driver.
        last_version is treated as a Unix timestamp (seconds).
        Only returns orders modified since that timestamp.
        """
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        now_ts = int(time.time())

        # If last_version is 0, this is a full sync - use epoch
        since = datetime.utcfromtimestamp(last_version) if last_version > 0 else datetime.min

        # 1. Assigned orders modified since last sync
        assigned_orders = await Order.find(
            Order.driver_id == driver_id,
            Order.state != OrderState.DELIVERED,
            Order.state != OrderState.CANCELLED,
            Order.updated_at >= since,
        ).to_list()

        # 2. Offered orders (always include so driver sees new offers)
        offered_orders = await Order.find(
            Order.state == OrderState.OFFERED,
            Order.updated_at >= since,
        ).to_list()

        combined_orders = assigned_orders + offered_orders

        # Deduplicate by order id
        seen = set()
        unique_orders = []
        for o in combined_orders:
            oid = str(o.id)
            if oid not in seen:
                seen.add(oid)
                unique_orders.append(o)

        def order_to_dict(o):
            return {
                "id": str(o.id),
                "state": o.state.value,
                "total": o.total_amount,
                "pickup": o.pickup_location,
                "dropoff": o.dropoff_location,
                "items": [i.model_dump() for i in o.items],
            }

        data = {"orders": [order_to_dict(o) for o in unique_orders]}

        response = SyncResponse(new_version=now_ts, data=data)

        # Record last sync timestamp in Redis
        await r.set(f"sync_ts:{driver_id}", str(now_ts))

        return msgpack.packb(response.model_dump(mode="json"))


sync_service = SyncService()
