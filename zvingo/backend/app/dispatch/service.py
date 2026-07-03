import asyncio
import redis.asyncio as redis
from app.config import settings
from app.dispatch.schemas import DriverLocationUpdate
import structlog
import math

logger = structlog.get_logger()

# Weights for driver scoring
X1_DIST = 0.4
X2_ACCEPT = 0.3
X3_RATING = 0.2
X4_CONN = 0.1

class DispatchService:
    def __init__(self):
        self.redis = redis.from_url(settings.REDIS_URL, decode_responses=True)

    async def update_location(self, update: DriverLocationUpdate):
        # GEOADD key longitude latitude member
        await self.redis.geoadd("driver_locations", [update.lng, update.lat, update.driver_id])

        # Store metadata in hash
        await self.redis.hset(f"driver:{update.driver_id}", mapping={
            "status": update.status,
            "battery": str(update.battery or 0),
            "last_seen": str(update.timestamp.timestamp())
        })

        logger.debug("Location updated", driver_id=update.driver_id, lat=update.lat, lng=update.lng, status=update.status)
        
        # Broadcast to tracking channel if driver has active order
        from app.notification.service import notification_service
        import json
        
        r = self.redis
        await r.publish(f"driver_loc_{update.driver_id}", json.dumps({
            "lat": update.lat,
            "lng": update.lng,
            "ts": str(update.timestamp)
        }))
        
    async def find_drivers_for_order(self, pickup_lat: float, pickup_lng: float, radius_km: float = 5.0):
        """Find nearby online drivers, returning (driver_id, distance_km) tuples."""
        logger.info("Searching for drivers", pickup_lat=pickup_lat, pickup_lng=pickup_lng, radius_km=radius_km)

        candidates = await self.redis.geosearch(
            "driver_locations",
            longitude=pickup_lng,
            latitude=pickup_lat,
            radius=radius_km,
            unit="km",
            withdist=True,
            sort="ASC",
            count=50
        )

        logger.info("GEO search results", candidate_count=len(candidates), candidates=candidates)

        scored_drivers = []
        for member, dist in candidates:
            # Get driver stats
            stats = await self.redis.hgetall(f"driver:{member}")
            logger.info("Driver candidate", driver_id=member, dist_km=dist, status=stats.get("status"), stats=stats)
            if stats.get("status") != "ONLINE":
                continue
                
            accept_rate = float(stats.get("accept_rate", 0))
            rating = float(stats.get("rating", 0))
            connectivity_bonus = float(stats.get("connectivity_bonus", 0))
            
            dist_score = 1.0 / max(dist, 0.1) 
            score = (X1_DIST * dist_score) + (X2_ACCEPT * accept_rate) + (X3_RATING * (rating/5.0)) + (X4_CONN * connectivity_bonus)
            
            scored_drivers.append((member, score, dist))
            
        # Sort by score DESC
        scored_drivers.sort(key=lambda x: x[1], reverse=True)
        
        # Return all found drivers (First Come First Serve pool)
        # We still sort them by score so the "best" drivers are arguably notified microseconds earlier in the loop
        return [(d[0], d[2]) for d in scored_drivers]

    async def dispatch_order(self, order_id: str, pickup_lat: float, pickup_lng: float):
        """Find nearby drivers and send each a rich offer with their specific pickup distance."""
        # Guard: refuse to dispatch if pickup location wasn't resolved (0,0 is Null Island)
        if abs(pickup_lat) < 0.01 and abs(pickup_lng) < 0.01:
            logger.error(
                "Cannot dispatch: pickup location is (0,0). Restaurant location not resolved.",
                order_id=order_id
            )
            return

        driver_results = await self.find_drivers_for_order(pickup_lat, pickup_lng)
        driver_ids = [d[0] for d in driver_results]
        logger.info("Dispatching order", order_id=order_id, drivers=driver_ids)

        from app.notification.service import notification_service
        from app.order.service import OrderService
        from app.order.state_machine import OrderState

        # If drivers found, transition order to OFFERED state
        if driver_results:
            try:
                await OrderService.transition_state(order_id, OrderState.OFFERED, actor_id="system")
                logger.info("Order transitioned to OFFERED", order_id=order_id)
            except Exception as e:
                logger.warn("Failed to transition order to OFFERED", order_id=order_id, error=str(e))
        else:
            logger.warn("No drivers found for order", order_id=order_id)
            return

        for driver_id, dist_km in driver_results:
            await notification_service.send_offer(driver_id, order_id, driver_dist_km=dist_km)

        # Wait for acceptance (handled by state machine + timeout task separately)

    async def accept_offer(self, driver_id: str, order_id: str):
        """Driver accepts an offer — transition order state and create dispatch record."""
        from app.order.service import OrderService
        from app.order.state_machine import OrderState
        from app.dispatch.models import Dispatch
        from app.notification.service import notification_service
        
        order = await OrderService.transition_state(order_id, OrderState.ACCEPTED, actor_id=driver_id)
        if not order:
            return None
        
        # Create dispatch record
        dispatch = Dispatch(
            order_id=order_id,
            driver_id=driver_id,
            status="ASSIGNED",
        )
        await dispatch.insert()
        
        # Notify consumer that driver accepted
        await notification_service.notify_consumer(
            order.consumer_id, order_id, "order_accepted",
            data={"driver_id": driver_id}
        )
        
        logger.info("Offer accepted", driver_id=driver_id, order_id=order_id)
        return order

    async def decline_offer(self, driver_id: str, order_id: str):
        """Driver declines an offer — log it for analytics."""
        logger.info("Offer declined", driver_id=driver_id, order_id=order_id)
        # Could update accept_rate stats in Redis here
        return {"status": "declined"}

    async def get_driver_state(self, driver_id: str):
        """Get the current state of a driver (status + active order)."""
        from app.order.models import Order
        from app.order.state_machine import OrderState

        # 1. Get status from Redis
        stats = await self.redis.hgetall(f"driver:{driver_id}")
        status = stats.get("status", "OFFLINE")

        # 2. Check for active order (assigned/picked up/en route)
        # We look for orders where this driver is assigned and state is NOT completed/cancelled
        active_order = await Order.find_one({
            "driver_id": driver_id,
            "state": {"$in": [
                OrderState.ACCEPTED,
                OrderState.ARRIVED_AT_MERCHANT,
                OrderState.READY_FOR_PICKUP,
                OrderState.PICKED_UP,
                OrderState.ARRIVED_AT_CUSTOMER
            ]}
        })

        return {
            "status": status,
            "active_order": active_order
        }

dispatch_service = DispatchService()
