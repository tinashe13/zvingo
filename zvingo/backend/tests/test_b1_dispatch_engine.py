"""The dispatch engine: how drivers are scored, offered work, and given up on.

Covers the three properties an order must have to never get lost:
  * it is offered to one driver at a time, and never to two at once;
  * an unanswered offer times out and moves on, skipping who has already seen it;
  * when nobody will take it, it dead-letters to ops instead of hanging forever.
"""

from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.order.state_machine import OrderState
from app.time_utils import utc_now


class RedisDouble:
    """The handful of Redis commands dispatch actually issues."""

    def __init__(self, candidates=None, hashes=None):
        self.candidates = candidates or []
        self.hashes = hashes or {}
        self.published = []

    async def geosearch(self, *_args, **_kwargs):
        return list(self.candidates)

    async def hgetall(self, key):
        return dict(self.hashes.get(key, {}))

    async def hset(self, key, field=None, value=None, mapping=None):
        bucket = self.hashes.setdefault(key, {})
        if mapping:
            bucket.update({k: str(v) for k, v in mapping.items()})
        elif field is not None:
            bucket[field] = str(value)

    async def hincrby(self, key, field, amount=1):
        bucket = self.hashes.setdefault(key, {})
        bucket[field] = str(int(bucket.get(field, 0)) + amount)
        return int(bucket[field])

    async def geoadd(self, *_args, **_kwargs):
        return 1

    async def publish(self, channel, payload):
        self.published.append((channel, payload))


def make_service(monkeypatch, redis, loads=None, ratings=None):
    """A DispatchService wired to doubles, with no database behind it."""
    import app.dispatch.service as module
    import app.order.service as order_service

    service = module.DispatchService()
    service.redis = redis
    monkeypatch.setattr(
        order_service.OrderService, "active_load", AsyncMock(return_value=loads or {})
    )
    monkeypatch.setattr(
        module.DispatchService, "_driver_ratings", AsyncMock(return_value=ratings or {})
    )
    return service


def online(**stats):
    base = {"status": "ONLINE"}
    base.update({k: str(v) for k, v in stats.items()})
    return base


# ── Scoring ─────────────────────────────────────────────────────────


def test_scoring_components_are_normalised():
    import app.dispatch.service as module

    assert module.proximity_score(0) == 1.0
    assert module.proximity_score(module.SEARCH_RADIUS_KM) == 0.0
    assert 0 < module.proximity_score(module.SEARCH_RADIUS_KM / 2) < 1

    assert module.rating_score(5.0) == 1.0
    assert module.rating_score(1.0) == 0.0
    # An unrated driver gets a neutral prior, not a zero that buries them.
    assert module.rating_score(None) == module.DEFAULT_RATING_SCORE

    assert module.load_score(0) == 1.0
    assert module.load_score(module.MAX_CONCURRENT_DELIVERIES) == 0.0

    assert module.fairness_score(None) == 1.0
    assert module.fairness_score(0) == 0.0
    assert module.fairness_score(module.FAIRNESS_WINDOW_SECONDS * 2) == 1.0

    assert module.connectivity_score(100, 0) == 1.0
    assert module.connectivity_score(0, 10_000) == 0.0


def test_weights_sum_to_one_so_a_score_is_a_fraction():
    import app.dispatch.service as module

    total = (
        module.W_PROXIMITY
        + module.W_ACCEPTANCE
        + module.W_RATING
        + module.W_LOAD
        + module.W_FAIRNESS
        + module.W_CONNECTIVITY
    )
    assert total == pytest.approx(1.0)
    perfect = module.combined_score(
        proximity=1, acceptance=1, rating=1, load=1, fairness=1, connectivity=1
    )
    assert perfect == pytest.approx(1.0)


@pytest.mark.asyncio
async def test_offline_and_excluded_drivers_are_never_candidates(monkeypatch):
    redis = RedisDouble(
        candidates=[("busy", 0.2), ("seen-it", 0.3), ("free", 1.0)],
        hashes={
            "driver:busy": {"status": "BUSY"},
            "driver:seen-it": online(),
            "driver:free": online(),
        },
    )
    service = make_service(monkeypatch, redis)

    ranked = await service.score_candidates(-17.8, 31.0, exclude={"seen-it"})

    assert [c["driver_id"] for c in ranked] == ["free"]


@pytest.mark.asyncio
async def test_a_driver_at_capacity_is_dropped_entirely(monkeypatch):
    import app.dispatch.service as module

    redis = RedisDouble(
        candidates=[("maxed", 0.1), ("spare", 3.0)],
        hashes={"driver:maxed": online(), "driver:spare": online()},
    )
    service = make_service(
        monkeypatch,
        redis,
        loads={"maxed": module.MAX_CONCURRENT_DELIVERIES, "spare": 0},
    )

    ranked = await service.score_candidates(-17.8, 31.0)

    assert [c["driver_id"] for c in ranked] == ["spare"]


@pytest.mark.asyncio
async def test_load_and_rating_can_outweigh_being_marginally_closer(monkeypatch):
    """Scoring is not "nearest wins": a loaded, poorly rated driver can lose."""
    redis = RedisDouble(
        candidates=[("loaded", 1.0), ("idle", 1.4)],
        hashes={
            "driver:loaded": online(offers_sent=10, offers_accepted=3),
            "driver:idle": online(offers_sent=10, offers_accepted=10),
        },
    )
    service = make_service(
        monkeypatch,
        redis,
        loads={"loaded": 1},
        ratings={"loaded": 2.0, "idle": 5.0},
    )

    ranked = await service.score_candidates(-17.8, 31.0)

    assert [c["driver_id"] for c in ranked] == ["idle", "loaded"]
    assert ranked[0]["components"]["load"] == 1.0
    assert ranked[1]["components"]["acceptance"] == pytest.approx(0.3)


@pytest.mark.asyncio
async def test_fairness_lifts_a_driver_who_has_been_waiting(monkeypatch):
    import app.dispatch.service as module

    now = utc_now().timestamp()
    redis = RedisDouble(
        candidates=[("hoarder", 1.0), ("waiting", 1.2)],
        hashes={
            # Just offered something a moment ago.
            "driver:hoarder": online(last_offer_at=now),
            # Has not been offered anything for the whole fairness window.
            "driver:waiting": online(
                last_offer_at=now - module.FAIRNESS_WINDOW_SECONDS * 2
            ),
        },
    )
    service = make_service(monkeypatch, redis)

    ranked = await service.score_candidates(-17.8, 31.0)
    by_id = {c["driver_id"]: c for c in ranked}

    assert by_id["waiting"]["components"]["fairness"] == 1.0
    assert by_id["hoarder"]["components"]["fairness"] == pytest.approx(0.0, abs=0.01)
    assert [c["driver_id"] for c in ranked] == ["waiting", "hoarder"]


# ── Offering ────────────────────────────────────────────────────────


@pytest.fixture
def offer_harness(monkeypatch):
    """A dispatch service whose order writes land in a dict we can inspect."""
    import app.dispatch.service as module
    import app.notification.service as notification_module
    import app.order.service as order_service

    state = {
        "snapshot": {
            "state": OrderState.CREATED,
            "driver_id": None,
            "offered_to": [],
            "declined_by": [],
            "offered_driver_id": None,
            "offer_expires_at": None,
        },
        "offers": [],
        "transitions": [],
        "cleared": [],
        "resets": [],
        "declines": [],
    }

    async def record_offer(order_id, driver_id, expires_at):
        state["offers"].append((order_id, driver_id, expires_at))
        state["snapshot"]["offered_to"].append(driver_id)
        state["snapshot"]["offered_driver_id"] = driver_id
        state["snapshot"]["offer_expires_at"] = expires_at

    async def transition(order_id, new_state, **kwargs):
        state["transitions"].append((order_id, new_state, kwargs))
        state["snapshot"]["state"] = new_state
        return SimpleNamespace(id=order_id, consumer_id="consumer-1")

    async def clear(order_id):
        state["cleared"].append(order_id)
        state["snapshot"]["offered_driver_id"] = None
        state["snapshot"]["offer_expires_at"] = None

    async def reset(order_id):
        state["resets"].append(order_id)
        state["snapshot"]["offered_to"] = []

    async def decline(order_id, driver_id):
        state["declines"].append((order_id, driver_id))
        state["snapshot"]["declined_by"].append(driver_id)
        state["snapshot"]["offered_driver_id"] = None

    monkeypatch.setattr(order_service.OrderService, "record_offer", record_offer)
    monkeypatch.setattr(order_service.OrderService, "transition_state", transition)
    monkeypatch.setattr(order_service.OrderService, "clear_expired_offer", clear)
    monkeypatch.setattr(order_service.OrderService, "reset_offer_history", reset)
    monkeypatch.setattr(order_service.OrderService, "record_decline", decline)
    monkeypatch.setattr(
        notification_module.notification_service, "send_offer", AsyncMock()
    )
    monkeypatch.setattr(
        module.DispatchService,
        "_order_snapshot",
        staticmethod(AsyncMock(side_effect=lambda _id: dict(state["snapshot"]))),
    )
    state["send_offer"] = notification_module.notification_service.send_offer
    return state


@pytest.mark.asyncio
async def test_an_order_is_offered_to_one_driver_at_a_time(monkeypatch, offer_harness):
    redis = RedisDouble(
        candidates=[("best", 0.5), ("second", 1.0), ("third", 2.0)],
        hashes={f"driver:{d}": online() for d in ("best", "second", "third")},
    )
    service = make_service(monkeypatch, redis)

    await service.dispatch_order("order-1", -17.8, 31.0)

    assert offer_harness["send_offer"].await_count == 1
    assert [d for _, d, _ in offer_harness["offers"]] == ["best"]
    # The order was moved into OFFERED, once.
    assert [s for _, s, _ in offer_harness["transitions"]] == [OrderState.OFFERED]
    # The offer has an expiry, so it can never be held forever.
    assert offer_harness["offers"][0][2] > utc_now()


@pytest.mark.asyncio
async def test_an_outstanding_offer_is_not_re_offered(monkeypatch, offer_harness):
    redis = RedisDouble(
        candidates=[("best", 0.5), ("second", 1.0)],
        hashes={f"driver:{d}": online() for d in ("best", "second")},
    )
    service = make_service(monkeypatch, redis)

    offer_harness["snapshot"].update(
        {
            "state": OrderState.OFFERED,
            "offered_to": ["best"],
            "offered_driver_id": "best",
            "offer_expires_at": utc_now() + timedelta(seconds=30),
        }
    )

    await service.dispatch_order("order-1", -17.8, 31.0)

    assert offer_harness["send_offer"].await_count == 0, (
        "a second driver must not see an order someone is still deciding on"
    )


@pytest.mark.asyncio
async def test_a_lapsed_offer_moves_to_the_next_driver(monkeypatch, offer_harness):
    redis = RedisDouble(
        candidates=[("best", 0.5), ("second", 1.0)],
        hashes={f"driver:{d}": online() for d in ("best", "second")},
    )
    service = make_service(monkeypatch, redis)

    offer_harness["snapshot"].update(
        {
            "state": OrderState.OFFERED,
            "offered_to": ["best"],
            "offered_driver_id": "best",
            "offer_expires_at": utc_now() - timedelta(seconds=1),
        }
    )

    await service.dispatch_order("order-1", -17.8, 31.0)

    assert offer_harness["cleared"] == ["order-1"]
    assert [d for _, d, _ in offer_harness["offers"]] == ["second"]
    # Already OFFERED, so no redundant state change.
    assert offer_harness["transitions"] == []
    # The driver who ignored it is recorded as having timed out.
    assert redis.hashes["driver:best"]["offers_timed_out"] == "1"


@pytest.mark.asyncio
async def test_the_candidate_pool_is_reset_rather_than_abandoned(monkeypatch, offer_harness):
    """Once everyone nearby has seen the order, start a fresh round."""
    redis = RedisDouble(
        candidates=[("only-driver", 0.5)],
        hashes={"driver:only-driver": online()},
    )
    service = make_service(monkeypatch, redis)

    offer_harness["snapshot"].update(
        {"state": OrderState.OFFERED, "offered_to": ["only-driver"]}
    )

    await service.dispatch_order("order-1", -17.8, 31.0)

    assert offer_harness["resets"] == ["order-1"]
    assert [d for _, d, _ in offer_harness["offers"]] == ["only-driver"]


@pytest.mark.asyncio
async def test_a_driver_who_declined_is_not_offered_again(monkeypatch, offer_harness):
    redis = RedisDouble(
        candidates=[("refuser", 0.5)],
        hashes={"driver:refuser": online()},
    )
    service = make_service(monkeypatch, redis)

    offer_harness["snapshot"].update(
        {
            "state": OrderState.OFFERED,
            "offered_to": ["refuser"],
            "declined_by": ["refuser"],
        }
    )

    await service.dispatch_order("order-1", -17.8, 31.0)

    assert offer_harness["send_offer"].await_count == 0
    assert offer_harness["resets"] == ["order-1"], "the pool was reset..."
    assert offer_harness["offers"] == [], "...but a decline is still honoured"


@pytest.mark.asyncio
async def test_dispatch_stops_once_the_order_is_taken_or_cancelled(monkeypatch, offer_harness):
    redis = RedisDouble(
        candidates=[("anyone", 0.5)], hashes={"driver:anyone": online()}
    )
    service = make_service(monkeypatch, redis)

    for snapshot in (
        {"state": OrderState.ACCEPTED, "driver_id": "driver-a"},
        {"state": OrderState.CANCELLED, "driver_id": None},
        {"state": OrderState.DELIVERED, "driver_id": "driver-a"},
        {"state": OrderState.PICKED_UP, "driver_id": "driver-a"},
    ):
        offer_harness["snapshot"].update(snapshot)
        await service.dispatch_order("order-1", -17.8, 31.0)

    assert offer_harness["send_offer"].await_count == 0


@pytest.mark.asyncio
async def test_a_merchant_confirmed_order_with_no_driver_is_still_dispatched(
    monkeypatch, offer_harness
):
    """The bug this guards: merchant "Accept" used to orphan the order.

    The dashboard confirms an order by moving it to ACCEPTED. With no driver on
    it that is a kitchen confirmation, not an assignment — dispatch has to keep
    working on it or the consumer waits forever for a driver who is never asked.
    """
    redis = RedisDouble(
        candidates=[("free", 0.5)], hashes={"driver:free": online()}
    )
    service = make_service(monkeypatch, redis)

    offer_harness["snapshot"].update(
        {"state": OrderState.ACCEPTED, "driver_id": None}
    )

    await service.dispatch_order("order-1", -17.8, 31.0)

    assert [d for _, d, _ in offer_harness["offers"]] == ["free"]
    # The merchant's confirmation is left alone: dispatch does not shove the
    # order back to OFFERED, it just keeps hunting for a driver.
    assert offer_harness["transitions"] == []


@pytest.mark.asyncio
async def test_null_island_pickups_are_never_dispatched(monkeypatch, offer_harness):
    redis = RedisDouble(candidates=[("free", 0.1)], hashes={"driver:free": online()})
    service = make_service(monkeypatch, redis)

    assert await service.dispatch_order("order-1", 0.0, 0.0) is None
    assert offer_harness["send_offer"].await_count == 0


@pytest.mark.asyncio
async def test_no_drivers_in_range_records_the_miss(monkeypatch, offer_harness):
    import app.dispatch.service as module

    redis = RedisDouble(candidates=[])
    service = make_service(monkeypatch, redis)
    before = module.metrics.dispatch_no_driver_total.value()

    await service.dispatch_order("order-1", -17.8, 31.0)

    assert module.metrics.dispatch_no_driver_total.value() == before + 1
    assert offer_harness["transitions"] == [], "an unoffered order stays put"


@pytest.mark.asyncio
async def test_declining_hands_the_order_straight_to_the_next_driver(monkeypatch, offer_harness):
    redis = RedisDouble(
        candidates=[("refuser", 0.5), ("next-up", 1.0)],
        hashes={f"driver:{d}": online() for d in ("refuser", "next-up")},
    )
    service = make_service(monkeypatch, redis)

    offer_harness["snapshot"].update(
        {
            "state": OrderState.OFFERED,
            "offered_to": ["refuser"],
            "offered_driver_id": "refuser",
            "offer_expires_at": utc_now() + timedelta(seconds=30),
        }
    )

    redispatched = []
    monkeypatch.setattr(
        service, "_redispatch", AsyncMock(side_effect=lambda oid: redispatched.append(oid))
    )

    result = await service.decline_offer("refuser", "order-1")

    assert result == {"status": "declined"}
    assert offer_harness["declines"] == [("order-1", "refuser")]
    assert redispatched == ["order-1"]
    assert redis.hashes["driver:refuser"]["offers_declined"] == "1"


@pytest.mark.asyncio
async def test_accepting_records_the_assignment_once(monkeypatch, offer_harness):
    import app.dispatch.models as dispatch_models
    import app.notification.service as notification_module

    redis = RedisDouble()
    service = make_service(monkeypatch, redis)

    inserted = AsyncMock()

    class FakeDispatch:
        def __init__(self, **kwargs):
            self.kwargs = kwargs
            self.insert = inserted

    monkeypatch.setattr(dispatch_models, "Dispatch", FakeDispatch)
    notify = AsyncMock()
    monkeypatch.setattr(notification_module.notification_service, "notify_consumer", notify)

    order = await service.accept_offer("driver-a", "order-1")

    assert order is not None
    inserted.assert_awaited_once()
    # One acceptance, one consumer notification — sent by the state transition,
    # not duplicated here.
    notify.assert_not_awaited()
    assert redis.hashes["driver:driver-a"]["offers_accepted"] == "1"
    _, target, kwargs = offer_harness["transitions"][0]
    assert target is OrderState.ACCEPTED
    assert kwargs["driver_id"] == "driver-a"
    assert kwargs["reason"] == "driver_accepted"


# ── Order snapshot ──────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_order_snapshot_reads_the_dispatch_fields(monkeypatch):
    import app.dispatch.service as module
    import app.order.models as order_models

    expires = utc_now()
    stored = SimpleNamespace(
        state="OrderState.OFFERED",
        driver_id=None,
        offered_to=["a"],
        declined_by=["b"],
        offered_driver_id="a",
        offer_expires_at=expires,
    )
    monkeypatch.setattr(order_models.Order, "get", AsyncMock(return_value=stored))

    snapshot = await module.DispatchService._order_snapshot("order-1")

    assert snapshot == {
        "state": OrderState.OFFERED,
        "driver_id": None,
        "offered_to": ["a"],
        "declined_by": ["b"],
        "offered_driver_id": "a",
        "offer_expires_at": expires,
    }

    # An unreadable order must not crash dispatch.
    monkeypatch.setattr(
        order_models.Order, "get", AsyncMock(side_effect=RuntimeError("no db"))
    )
    assert await module.DispatchService._order_snapshot("order-1") is None
    monkeypatch.setattr(order_models.Order, "get", AsyncMock(return_value=None))
    assert await module.DispatchService._order_snapshot("order-1") is None


# ── Dead letter ─────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_exhausted_orders_page_ops_and_tell_the_consumer(monkeypatch):
    import app.dispatch.retry_service as module
    import app.notification.service as notification_module
    import app.observability.alerts as alerts
    import app.order.service as order_service

    order = SimpleNamespace(
        id="order-1",
        state=OrderState.OFFERED,
        merchant_id="restaurant-1",
        consumer_id="consumer-1",
        dispatch_escalated=False,
        retry_count=module.MAX_RETRY_ATTEMPTS,
    )

    marked = AsyncMock(return_value=True)
    monkeypatch.setattr(order_service.OrderService, "mark_dispatch_escalated", marked)
    raise_alert = AsyncMock(return_value={})
    monkeypatch.setattr(alerts.alert_service, "raise_alert", raise_alert)
    notify = AsyncMock()
    monkeypatch.setattr(notification_module.notification_service, "notify_consumer", notify)

    await module.OrderRetryService._escalate(order, module.MAX_RETRY_ATTEMPTS)

    marked.assert_awaited_once_with("order-1")
    assert raise_alert.await_args.args[0] == "dispatch_dead_letter"
    assert raise_alert.await_args.kwargs["order_id"] == "order-1"
    assert notify.await_args.args[2] == "dispatch_delayed"

    # Second pass: the flag has already been claimed, so nobody is paged twice.
    marked.return_value = False
    raise_alert.reset_mock()
    notify.reset_mock()
    await module.OrderRetryService._escalate(order, module.MAX_RETRY_ATTEMPTS)
    raise_alert.assert_not_awaited()
    notify.assert_not_awaited()


@pytest.mark.asyncio
async def test_a_dead_lettered_order_is_left_alone_by_the_retry_loop(monkeypatch):
    import app.dispatch.retry_service as module

    captured = {}

    class Query:
        def __init__(self, values):
            self.values = values

        def limit(self, *_args):
            return self

        async def to_list(self):
            return self.values

    def find(criteria):
        captured["criteria"] = criteria
        return Query([])

    monkeypatch.setattr(module.Order, "find", find)
    await module.OrderRetryService._process_stuck_orders()

    assert captured["criteria"]["dispatch_escalated"] == {"$ne": True}


@pytest.mark.asyncio
async def test_the_offer_sweep_redispatches_lapsed_offers(monkeypatch):
    import app.dispatch.retry_service as module
    from app.location.models import Location

    lapsed = SimpleNamespace(
        id="order-1",
        offered_driver_id="slow-driver",
        pickup_location=Location.from_lat_lng(-17.8, 31.0),
    )
    no_pickup = SimpleNamespace(
        id="order-2", offered_driver_id="slow-driver", pickup_location=None,
        merchant_id="restaurant-1",
    )

    class Query:
        def __init__(self, values):
            self.values = values

        def limit(self, *_args):
            return self

        async def to_list(self):
            return self.values

    captured = {}

    def find(criteria):
        captured["criteria"] = criteria
        return Query([lapsed, no_pickup])

    monkeypatch.setattr(module.Order, "find", find)
    monkeypatch.setattr(module.OrderService, "_resolve_pickup", AsyncMock(
        side_effect=[lapsed.pickup_location, None]
    ))
    cleared = AsyncMock()
    monkeypatch.setattr(module.OrderService, "clear_expired_offer", cleared)
    dispatch = AsyncMock()
    monkeypatch.setattr(module.dispatch_service, "dispatch_order", dispatch)

    handled = await module.OrderRetryService.sweep_expired_offers()

    assert handled == 1
    dispatch.assert_awaited_once_with("order-1", -17.8, 31.0)
    # The one with no pickup point is not left holding a dead offer.
    cleared.assert_awaited_once_with("order-2")
    assert captured["criteria"]["state"] == OrderState.OFFERED.value
    assert captured["criteria"]["driver_id"] is None


@pytest.mark.asyncio
async def test_the_offer_sweep_survives_a_broken_query(monkeypatch):
    import app.dispatch.retry_service as module

    monkeypatch.setattr(
        module.Order, "find", lambda *_a, **_k: (_ for _ in ()).throw(RuntimeError("db down"))
    )
    assert await module.OrderRetryService.sweep_expired_offers() == 0
