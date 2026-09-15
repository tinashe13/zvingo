"""Driver dispatch: deciding who gets offered which order, and when.

Offer model
-----------
An order is offered to **one driver at a time**. The driver holding the offer is
recorded on the order itself (`offered_driver_id` / `offer_expires_at`), not only
in Redis, so a backend restart cannot hand the same order to a second driver
while the first is still deciding. When the offer lapses unanswered, the sweep in
`OrderRetryService` clears it and dispatch moves to the next best driver. Drivers
who have already seen the order (`offered_to`) or declined it (`declined_by`) are
skipped, so the pool is walked fairly instead of hammering whoever is nearest.

`DISPATCH_OFFER_FANOUT` raises the number of drivers offered simultaneously if a
market ever needs a race-to-accept model; acceptance is atomic either way, so a
wider fan-out can never double-assign an order — it only means more drivers see
an offer that one of them will lose.

Scoring
-------
Candidates come from a Redis geo search around the pickup point and are scored on
six normalised (0..1) signals, combined with weights that sum to 1:

    proximity     0.35   1 − distance/radius. Closest driver, but not at any cost.
    acceptance    0.20   accepted ÷ offered. Drivers who actually take work.
    rating        0.15   (rating − 1)/4 from the driver's review average.
    load          0.15   1 − active_deliveries/capacity. Spreads work out, and
                         drivers already at capacity are dropped entirely.
    fairness      0.10   time since this driver's last offer, over a 15-minute
                         window. Stops one well-rated driver near the busiest
                         restaurant from absorbing every order while others idle.
    connectivity  0.05   battery level and how fresh the last GPS ping is — a
                         driver whose phone is about to die is a poor bet.

Unknown signals use neutral defaults rather than zero, so a brand-new driver with
no history is competitive instead of permanently buried. Ties break on distance.
"""

import asyncio
from datetime import timedelta
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import redis.asyncio as redis
import structlog

from app.config import settings
from app.dispatch.schemas import DriverLocationUpdate
from app.observability import metrics
from app.order.state_machine import (
    ACTIVE_DRIVER_STATES,
    DISPATCHABLE_STATES,
    OrderState,
    coerce_state,
    is_dispatchable,
)
from app.time_utils import utc_now

logger = structlog.get_logger()


def _setting(name: str, default):
    """Read a dispatch setting, falling back to a safe module default.

    The tuning knobs below are being added to `Settings`; until they are all
    declared there this keeps dispatch running on sane values instead of failing
    at import time.
    """
    value = getattr(settings, name, None)
    return default if value is None else value


# ── Tunables ────────────────────────────────────────────────────────
#: How long a driver has to answer an offer before it moves on.
OFFER_TIMEOUT_SECONDS: int = _setting("DISPATCH_OFFER_TIMEOUT_SECONDS", 45)
#: How many drivers see one order at the same time. 1 = strictly sequential.
OFFER_FANOUT: int = max(1, int(_setting("DISPATCH_OFFER_FANOUT", 1)))
#: Radius of the driver geo search around the pickup point.
SEARCH_RADIUS_KM: float = float(_setting("DISPATCH_SEARCH_RADIUS_KM", 5.0))
#: Upper bound on candidates pulled from Redis in one search.
MAX_CANDIDATES: int = int(_setting("DISPATCH_MAX_CANDIDATES", 50))
#: Deliveries a driver may hold at once before dispatch stops offering them work.
MAX_CONCURRENT_DELIVERIES: int = int(_setting("DISPATCH_MAX_CONCURRENT_DELIVERIES", 2))
#: A driver who has not been offered anything for this long scores maximum fairness.
FAIRNESS_WINDOW_SECONDS: int = int(_setting("DISPATCH_FAIRNESS_WINDOW_SECONDS", 900))
#: A GPS ping older than this makes the driver look unreachable.
LOCATION_STALE_SECONDS: int = int(_setting("DISPATCH_LOCATION_STALE_SECONDS", 120))

# Scoring weights — keep these summing to 1.0 so a score is always in 0..1.
W_PROXIMITY = 0.35
W_ACCEPTANCE = 0.20
W_RATING = 0.15
W_LOAD = 0.15
W_FAIRNESS = 0.10
W_CONNECTIVITY = 0.05

# Neutral priors for drivers with no history yet.
DEFAULT_ACCEPTANCE = 0.7
DEFAULT_RATING_SCORE = 0.6
DEFAULT_CONNECTIVITY = 0.5


def _clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def _as_float(value, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def proximity_score(distance_km: float, radius_km: float = SEARCH_RADIUS_KM) -> float:
    """1 at the pickup point, decaying linearly to 0 at the search radius."""
    if radius_km <= 0:
        return 0.0
    return _clamp(1.0 - (max(distance_km, 0.0) / radius_km))


def rating_score(rating: Optional[float]) -> float:
    """Map a 1..5 star average onto 0..1; unrated drivers get a neutral prior."""
    if rating is None or rating <= 0:
        return DEFAULT_RATING_SCORE
    return _clamp((rating - 1.0) / 4.0)


def load_score(active_deliveries: int, capacity: int = MAX_CONCURRENT_DELIVERIES) -> float:
    """1 when idle, 0 when at capacity."""
    if capacity <= 0:
        return 0.0
    return _clamp(1.0 - (max(active_deliveries, 0) / capacity))


def fairness_score(seconds_since_last_offer: Optional[float]) -> float:
    """1 for a driver who has not been offered anything in a long while."""
    if seconds_since_last_offer is None:
        return 1.0
    if FAIRNESS_WINDOW_SECONDS <= 0:
        return 1.0
    return _clamp(seconds_since_last_offer / FAIRNESS_WINDOW_SECONDS)


def connectivity_score(battery: Optional[float], seconds_since_ping: Optional[float]) -> float:
    """Blend battery level with how fresh the driver's last GPS ping is."""
    if battery is None and seconds_since_ping is None:
        return DEFAULT_CONNECTIVITY
    battery_part = _clamp((battery or 0.0) / 100.0) if battery is not None else DEFAULT_CONNECTIVITY
    if seconds_since_ping is None:
        freshness = DEFAULT_CONNECTIVITY
    elif LOCATION_STALE_SECONDS <= 0:
        freshness = 1.0
    else:
        freshness = _clamp(1.0 - (seconds_since_ping / LOCATION_STALE_SECONDS))
    return _clamp(0.5 * battery_part + 0.5 * freshness)


def combined_score(
    *,
    proximity: float,
    acceptance: float,
    rating: float,
    load: float,
    fairness: float,
    connectivity: float,
) -> float:
    """The weighted driver score. Every input is already normalised to 0..1."""
    return (
        W_PROXIMITY * _clamp(proximity)
        + W_ACCEPTANCE * _clamp(acceptance)
        + W_RATING * _clamp(rating)
        + W_LOAD * _clamp(load)
        + W_FAIRNESS * _clamp(fairness)
        + W_CONNECTIVITY * _clamp(connectivity)
    )


class DispatchService:
    def __init__(self):
        self.redis = redis.from_url(settings.REDIS_URL, decode_responses=True)

    # ── Driver presence ────────────────────────────────────────────

    async def update_location(self, update: DriverLocationUpdate):
        """Record a driver's position and liveness, and fan it out to watchers."""
        import json

        # GEOADD key longitude latitude member
        await self.redis.geoadd("driver_locations", [update.lng, update.lat, update.driver_id])

        # Store metadata in hash
        await self.redis.hset(f"driver:{update.driver_id}", mapping={
            "status": update.status,
            "battery": str(update.battery or 0),
            "last_seen": str(update.timestamp.timestamp())
        })

        logger.debug("Location updated", driver_id=update.driver_id, lat=update.lat, lng=update.lng, status=update.status)

        # Anyone tracking this driver (the consumer watching their order) gets
        # the new position immediately.
        await self.redis.publish(f"driver_loc_{update.driver_id}", json.dumps({
            "lat": update.lat,
            "lng": update.lng,
            "ts": str(update.timestamp),
        }))

    # ── Candidate scoring ──────────────────────────────────────────

    async def _driver_stats(self, driver_ids: Sequence[str]) -> Dict[str, dict]:
        """Every candidate's Redis stat hash, fetched concurrently."""
        if not driver_ids:
            return {}
        results = await asyncio.gather(
            *(self.redis.hgetall(f"driver:{d}") for d in driver_ids),
            return_exceptions=True,
        )
        stats: Dict[str, dict] = {}
        for driver_id, result in zip(driver_ids, results):
            stats[driver_id] = result if isinstance(result, dict) else {}
        return stats

    @staticmethod
    async def _driver_ratings(driver_ids: Sequence[str]) -> Dict[str, Optional[float]]:
        """Review averages for the candidate set — one query, never one per driver."""
        if not driver_ids:
            return {}
        try:
            from bson import ObjectId

            from app.auth.models import User

            object_ids = []
            for driver_id in driver_ids:
                try:
                    object_ids.append(ObjectId(str(driver_id)))
                except Exception:
                    continue
            if not object_ids:
                return {}
            users = await User.find({"_id": {"$in": object_ids}}).to_list()
        except Exception as e:
            logger.debug("Driver rating lookup unavailable", error=str(e))
            return {}
        return {str(user.id): getattr(user, "driver_rating", None) for user in users}

    async def score_candidates(
        self,
        pickup_lat: float,
        pickup_lng: float,
        radius_km: float = SEARCH_RADIUS_KM,
        exclude: Optional[Iterable[str]] = None,
    ) -> List[dict]:
        """Rank nearby online drivers for a pickup, best first.

        Each entry is ``{"driver_id", "distance_km", "score", "components"}``.
        See the module docstring for what the score means.
        """
        excluded = {str(d) for d in (exclude or ()) if d}

        candidates = await self.redis.geosearch(
            "driver_locations",
            longitude=pickup_lng,
            latitude=pickup_lat,
            radius=radius_km,
            unit="km",
            withdist=True,
            sort="ASC",
            count=MAX_CANDIDATES,
        )

        nearby = [
            (str(member), _as_float(dist))
            for member, dist in (candidates or [])
            if str(member) not in excluded
        ]
        if not nearby:
            logger.info(
                "No drivers in range",
                pickup_lat=pickup_lat,
                pickup_lng=pickup_lng,
                radius_km=radius_km,
                excluded=len(excluded),
            )
            return []

        driver_ids = [driver_id for driver_id, _ in nearby]
        stats = await self._driver_stats(driver_ids)

        online = [
            (driver_id, dist)
            for driver_id, dist in nearby
            if (stats.get(driver_id) or {}).get("status") == "ONLINE"
        ]
        if not online:
            return []

        online_ids = [driver_id for driver_id, _ in online]

        from app.order.service import OrderService

        loads = await OrderService.active_load(online_ids)
        ratings = await self._driver_ratings(online_ids)

        now_ts = utc_now().timestamp()
        scored: List[dict] = []
        for driver_id, distance_km in online:
            stat = stats.get(driver_id) or {}

            offered = _as_float(stat.get("offers_sent"), 0.0)
            accepted = _as_float(stat.get("offers_accepted"), 0.0)
            if offered >= 1:
                acceptance = _clamp(accepted / offered)
            else:
                acceptance = _clamp(_as_float(stat.get("accept_rate"), DEFAULT_ACCEPTANCE))

            active = int(loads.get(driver_id, 0))
            if active >= MAX_CONCURRENT_DELIVERIES:
                logger.debug("Driver at capacity, skipping", driver_id=driver_id, active=active)
                continue

            last_offer = stat.get("last_offer_at")
            since_offer = now_ts - _as_float(last_offer) if last_offer else None

            last_seen = stat.get("last_seen")
            since_ping = now_ts - _as_float(last_seen) if last_seen else None

            battery = _as_float(stat.get("battery"), -1.0)
            components = {
                "proximity": proximity_score(distance_km, radius_km),
                "acceptance": acceptance,
                "rating": rating_score(ratings.get(driver_id)),
                "load": load_score(active),
                "fairness": fairness_score(since_offer),
                "connectivity": (
                    _clamp(_as_float(stat["connectivity_bonus"]))
                    if "connectivity_bonus" in stat
                    else connectivity_score(battery if battery >= 0 else None, since_ping)
                ),
            }
            score = combined_score(**components)
            scored.append(
                {
                    "driver_id": driver_id,
                    "distance_km": distance_km,
                    "score": round(score, 6),
                    "components": components,
                }
            )

        # Best score first; the closer driver wins a tie.
        scored.sort(key=lambda c: (-c["score"], c["distance_km"]))
        logger.info(
            "Scored dispatch candidates",
            count=len(scored),
            best=scored[0]["driver_id"] if scored else None,
        )
        return scored

    async def find_drivers_for_order(
        self,
        pickup_lat: float,
        pickup_lng: float,
        radius_km: float = SEARCH_RADIUS_KM,
        exclude: Optional[Iterable[str]] = None,
    ) -> List[Tuple[str, float]]:
        """Ranked (driver_id, distance_km) pairs for a pickup point."""
        scored = await self.score_candidates(pickup_lat, pickup_lng, radius_km, exclude)
        return [(c["driver_id"], c["distance_km"]) for c in scored]

    # ── Offering ───────────────────────────────────────────────────

    @staticmethod
    async def _order_snapshot(order_id: str) -> Optional[dict]:
        """What dispatch needs to know about an order, or None if unreadable."""
        try:
            from app.order.models import Order

            order = await Order.get(order_id)
        except Exception as e:
            logger.debug("Order snapshot unavailable", order_id=str(order_id), error=str(e))
            return None
        if order is None:
            return None
        try:
            state = coerce_state(order.state)
        except Exception:
            return None
        return {
            "state": state,
            "driver_id": getattr(order, "driver_id", None),
            "offered_to": list(getattr(order, "offered_to", None) or []),
            "declined_by": list(getattr(order, "declined_by", None) or []),
            "offered_driver_id": getattr(order, "offered_driver_id", None),
            "offer_expires_at": getattr(order, "offer_expires_at", None),
        }

    async def _bump_driver_stat(self, driver_id: str, field: str, amount: int = 1) -> None:
        """Best-effort counter bump. Analytics must never break a dispatch."""
        try:
            await self.redis.hincrby(f"driver:{driver_id}", field, amount)
        except Exception as e:
            logger.debug("Driver stat bump skipped", driver_id=driver_id, field=field, error=str(e))

    async def _mark_offered(self, driver_id: str) -> None:
        """Remember when this driver last saw an offer, for the fairness term."""
        try:
            await self.redis.hset(
                f"driver:{driver_id}", "last_offer_at", str(utc_now().timestamp())
            )
        except Exception as e:
            logger.debug("Could not record offer time", driver_id=driver_id, error=str(e))

    async def dispatch_order(self, order_id: str, pickup_lat: float, pickup_lng: float):
        """Offer an order to the best available driver(s).

        Returns None always; dispatch is fire-and-forget. Re-entrant and safe to
        call repeatedly: an order with an offer still outstanding is left alone,
        and an order that has already been accepted or cancelled is dropped.
        """
        # Guard: refuse to dispatch if pickup location wasn't resolved (0,0 is Null Island)
        if abs(pickup_lat) < 0.01 and abs(pickup_lng) < 0.01:
            logger.error(
                "Cannot dispatch: pickup location is (0,0). Restaurant location not resolved.",
                order_id=order_id
            )
            return None

        from app.order.service import OrderService

        snapshot = await self._order_snapshot(order_id)
        exclude: set = set()
        # Only a CREATED order needs moving into OFFERED. An order that is
        # already OFFERED is simply being re-offered, and one a merchant has
        # confirmed into ACCEPTED (with no driver) keeps that state while
        # dispatch keeps looking — pushing it back to OFFERED would fight the
        # merchant's confirmation.
        needs_offer_transition = True

        if snapshot is not None:
            if not is_dispatchable(snapshot["state"], snapshot["driver_id"]):
                logger.info(
                    "Skipping dispatch: order is no longer dispatchable",
                    order_id=order_id,
                    state=snapshot["state"].value,
                    driver_id=snapshot["driver_id"],
                )
                return None

            holder = snapshot["offered_driver_id"]
            expires = snapshot["offer_expires_at"]
            if holder and expires and expires > utc_now():
                logger.info(
                    "Offer still outstanding, not re-offering",
                    order_id=order_id,
                    driver_id=holder,
                )
                return None
            if holder:
                # The offer lapsed unanswered — release it and move on.
                await OrderService.clear_expired_offer(order_id)
                await self._bump_driver_stat(holder, "offers_timed_out")

            exclude = set(snapshot["offered_to"]) | set(snapshot["declined_by"])
            needs_offer_transition = snapshot["state"] is OrderState.CREATED

        candidates = await self.score_candidates(
            pickup_lat, pickup_lng, exclude=exclude
        )

        if not candidates and exclude:
            # Everyone nearby has already seen this order. Start a fresh round
            # rather than never offering it again; declines are still honoured.
            await OrderService.reset_offer_history(order_id)
            declined = set(snapshot["declined_by"]) if snapshot else set()
            candidates = await self.score_candidates(
                pickup_lat, pickup_lng, exclude=declined
            )

        if not candidates:
            logger.warning("No drivers found for order", order_id=order_id)
            metrics.dispatch_no_driver_total.inc()
            return None

        if needs_offer_transition:
            try:
                await OrderService.transition_state(
                    order_id,
                    OrderState.OFFERED,
                    actor_id="system",
                    reason="dispatch_offered",
                    expected_states={OrderState.CREATED},
                )
                logger.info("Order transitioned to OFFERED", order_id=order_id)
            except Exception as e:
                # A conflict here means the order moved on (accepted or
                # cancelled) between the snapshot and now. When we know that for
                # certain, stop; otherwise log and continue offering.
                logger.warning(
                    "Failed to transition order to OFFERED",
                    order_id=order_id,
                    error=str(e),
                )
                if snapshot is not None:
                    return None

        expires_at = utc_now() + timedelta(seconds=OFFER_TIMEOUT_SECONDS)
        offered = candidates[:OFFER_FANOUT]

        from app.notification.service import notification_service

        for candidate in offered:
            driver_id = candidate["driver_id"]
            await OrderService.record_offer(order_id, driver_id, expires_at)
            await notification_service.send_offer(
                driver_id, order_id, driver_dist_km=candidate["distance_km"]
            )
            await self._bump_driver_stat(driver_id, "offers_sent")
            await self._mark_offered(driver_id)
            metrics.dispatch_offers_total.inc()
            logger.info(
                "Offer sent",
                order_id=order_id,
                driver_id=driver_id,
                score=candidate["score"],
                distance_km=candidate["distance_km"],
                expires_at=expires_at.isoformat(),
            )

        return None

    # ── Driver responses ───────────────────────────────────────────

    async def accept_offer(self, driver_id: str, order_id: str):
        """Claim an offer for a driver.

        The claim is a single conditional update: the order must still be
        unassigned and still in a dispatchable state. Exactly one of two drivers
        racing on the same order wins; the loser gets an
        :class:`~app.order.state_machine.OrderConflict`.
        """
        from app.order.service import OrderService
        from app.order.state_machine import OrderState

        order = await OrderService.transition_state(
            order_id,
            OrderState.ACCEPTED,
            actor_id=driver_id,
            driver_id=driver_id,
            reason="driver_accepted",
            # CREATED/OFFERED are the normal cases; ACCEPTED covers an order the
            # merchant has already confirmed but no driver has claimed yet.
            expected_states=DISPATCHABLE_STATES,
        )
        if not order:
            return None

        # Record dispatch assignment
        from app.dispatch.models import Dispatch

        dispatch = Dispatch(
            order_id=order_id,
            driver_id=driver_id,
            status="ASSIGNED",
        )
        await dispatch.insert()

        await self._bump_driver_stat(driver_id, "offers_accepted")

        # The consumer is told by `transition_state`, which publishes
        # `order_accepted` (with the driver id) for every ACCEPTED transition.
        # Announcing it again here sent the consumer two identical pushes.

        logger.info("Offer accepted", driver_id=driver_id, order_id=order_id)
        return order

    async def decline_offer(self, driver_id: str, order_id: str):
        """Record a decline and immediately look for the next best driver."""
        from app.order.service import OrderService

        await OrderService.record_decline(order_id, driver_id)
        await self._bump_driver_stat(driver_id, "offers_declined")
        logger.info("Offer declined", driver_id=driver_id, order_id=order_id)

        await self._redispatch(order_id)
        return {"status": "declined"}

    async def _redispatch(self, order_id: str) -> None:
        """Re-run dispatch for an order using its own pickup point."""
        try:
            from app.order.models import Order

            order = await Order.get(order_id)
        except Exception as e:
            logger.debug("Re-dispatch skipped", order_id=str(order_id), error=str(e))
            return
        if order is None or not order.pickup_location:
            return
        await self.dispatch_order(
            str(order_id), order.pickup_location.lat, order.pickup_location.lng
        )

    async def release_order(
        self, driver_id: str, order_id: str, reason: str = "driver_released"
    ):
        """Hand a pre-pickup order back to the pool and re-offer it."""
        from app.order.service import OrderService

        order = await OrderService.release_driver(order_id, driver_id, reason=reason)
        if order is None:
            return None
        await self._redispatch(order_id)
        return order

    # ── Driver state ───────────────────────────────────────────────

    async def get_driver_state(self, driver_id: str):
        """Get the current state of a driver (status + active order)."""
        from app.order.models import Order

        # 1. Get status from Redis
        stats = await self.redis.hgetall(f"driver:{driver_id}")
        status = stats.get("status", "OFFLINE")

        # 2. The one order this driver is currently working, if any.
        active_order = await Order.find_one({
            "driver_id": driver_id,
            "state": {"$in": [s.value for s in ACTIVE_DRIVER_STATES]},
        })

        return {
            "status": status,
            "active_order": active_order
        }


dispatch_service = DispatchService()
