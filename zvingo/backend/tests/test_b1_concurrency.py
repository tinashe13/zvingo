"""Concurrency guarantees for the order lifecycle.

These tests run the *real* `OrderService.transition_state` against an in-memory
stand-in for MongoDB that implements `find_one_and_update` with the same
atomicity Mongo gives it: matching and updating one document happens with no
suspension point in between, so two coroutines cannot both win. Everything else
(reads) yields, which is what makes the races below real races rather than
theatre.

What must hold:
  * two drivers accepting the same offer produce exactly one assignment;
  * a cancel racing an accept ends in one state, not a corrupt half-state;
  * a terminal order never moves again, whoever asks;
  * a driver cannot advance an order that is not theirs.
"""

import asyncio
from types import SimpleNamespace

import pytest

from app.order.state_machine import (
    InvalidStateTransition,
    OrderConflict,
    OrderState,
)


# ── In-memory Mongo stand-in ────────────────────────────────────────


def matches(doc: dict, criteria: dict) -> bool:
    """The subset of Mongo query operators the order service actually uses."""
    for key, condition in criteria.items():
        if key == "$or":
            if not any(matches(doc, branch) for branch in condition):
                return False
            continue
        value = doc.get(key)
        if isinstance(condition, dict):
            for op, operand in condition.items():
                if op == "$in":
                    if value not in operand:
                        return False
                elif op == "$ne":
                    if value == operand:
                        return False
                elif op == "$exists":
                    if (key in doc) is not operand:
                        return False
                elif op == "$lt":
                    if value is None or not value < operand:
                        return False
                else:  # pragma: no cover - guards against silent test drift
                    raise AssertionError(f"Unsupported query operator: {op}")
        elif value != condition:
            return False
    return True


def apply_update(doc: dict, update: dict) -> None:
    for key, value in (update.get("$set") or {}).items():
        doc[key] = value
    for key, value in (update.get("$push") or {}).items():
        doc.setdefault(key, []).append(value)
    for key, value in (update.get("$addToSet") or {}).items():
        bucket = doc.setdefault(key, [])
        if value not in bucket:
            bucket.append(value)


class FakeCollection:
    """`find_one_and_update` with Mongo's single-document atomicity.

    The match-and-write below contains no `await`, so once a coroutine starts it
    the event loop cannot run the competing one until it finishes — exactly the
    property the production code relies on.
    """

    def __init__(self, documents):
        self.documents = documents
        self.update_calls = 0

    async def find_one_and_update(self, criteria, update):
        self.update_calls += 1
        for doc in self.documents:
            if matches(doc, criteria):
                apply_update(doc, update)
                return dict(doc)
        return None

    async def update_one(self, criteria, update):
        for doc in self.documents:
            if matches(doc, criteria):
                apply_update(doc, update)
                return SimpleNamespace(modified_count=1)
        return SimpleNamespace(modified_count=0)


class FakeOrderDocument:
    """Just enough of a Beanie document for the service to work with."""

    def __init__(self, store: dict):
        self._store = store
        self.id = store["_id"]
        self.state = store["state"]
        self.driver_id = store.get("driver_id")
        self.consumer_id = store.get("consumer_id")
        self.merchant_id = store.get("merchant_id")
        self.events = list(store.get("events") or [])
        self.updated_at = store.get("updated_at")
        self.offered_driver_id = store.get("offered_driver_id")
        self.offer_expires_at = store.get("offer_expires_at")
        self.dispatch_escalated = store.get("dispatch_escalated", False)
        self.dispatch_escalated_at = store.get("dispatch_escalated_at")

    async def save(self):  # pragma: no cover - only the fallback path uses it
        self._store["state"] = self.state
        self._store["driver_id"] = self.driver_id


def install_order_store(monkeypatch, documents):
    """Point `OrderService` at an in-memory store and return the collection."""
    import app.order.service as service

    collection = FakeCollection(documents)

    class FakeOrder:
        @staticmethod
        async def get(order_id):
            # Reading yields, so competing coroutines really do observe the same
            # pre-race state. Without this the "race" would be serialised.
            await asyncio.sleep(0)
            for doc in documents:
                if doc["_id"] == str(order_id):
                    return FakeOrderDocument(doc)
            return None

    monkeypatch.setattr(service, "Order", FakeOrder)
    monkeypatch.setattr(service, "_order_collection", lambda: collection)
    monkeypatch.setattr(service, "_document_id", lambda order_id: str(order_id))
    # Notifications are exercised elsewhere; here they would only add noise.
    monkeypatch.setattr(service.OrderService, "_notify_consumer", staticmethod(lambda *a, **k: None))
    return collection


def order_document(**overrides) -> dict:
    document = {
        "_id": "order-1",
        "state": OrderState.OFFERED.value,
        "driver_id": None,
        "consumer_id": "consumer-1",
        "merchant_id": "restaurant-1",
        "events": [],
    }
    document.update(overrides)
    return document


# ── Two drivers, one order ──────────────────────────────────────────


@pytest.mark.asyncio
async def test_two_drivers_accepting_the_same_offer_produce_one_assignment(monkeypatch):
    from app.order.service import OrderService

    document = order_document()
    install_order_store(monkeypatch, [document])

    async def accept(driver_id):
        return await OrderService.transition_state(
            "order-1",
            OrderState.ACCEPTED,
            actor_id=driver_id,
            driver_id=driver_id,
            reason="driver_accepted",
            expected_states={OrderState.CREATED, OrderState.OFFERED, OrderState.ACCEPTED},
        )

    results = await asyncio.gather(
        accept("driver-a"), accept("driver-b"), return_exceptions=True
    )

    winners = [r for r in results if not isinstance(r, BaseException)]
    losers = [r for r in results if isinstance(r, BaseException)]

    assert len(winners) == 1, "exactly one driver may win the order"
    assert len(losers) == 1
    assert isinstance(losers[0], OrderConflict)

    assert document["state"] == OrderState.ACCEPTED.value
    assert document["driver_id"] in ("driver-a", "driver-b")
    assert document["driver_id"] == winners[0].driver_id
    # One transition, one audit event — not two.
    assert [e["state"] for e in document["events"]] == [OrderState.ACCEPTED.value]
    assert document["events"][0]["actor_id"] == document["driver_id"]
    assert document["events"][0]["reason"] == "driver_accepted"


@pytest.mark.asyncio
async def test_ten_drivers_racing_still_yield_a_single_winner(monkeypatch):
    from app.order.service import OrderService

    document = order_document()
    install_order_store(monkeypatch, [document])

    results = await asyncio.gather(
        *(
            OrderService.transition_state(
                "order-1",
                OrderState.ACCEPTED,
                actor_id=f"driver-{i}",
                driver_id=f"driver-{i}",
                expected_states={OrderState.OFFERED, OrderState.ACCEPTED},
            )
            for i in range(10)
        ),
        return_exceptions=True,
    )

    winners = [r for r in results if not isinstance(r, BaseException)]
    assert len(winners) == 1
    assert all(isinstance(r, OrderConflict) for r in results if isinstance(r, BaseException))
    assert len(document["events"]) == 1


@pytest.mark.asyncio
async def test_retrying_your_own_accept_is_idempotent(monkeypatch):
    """A dropped response must not cost the driver the order they already won."""
    from app.order.service import OrderService

    document = order_document()
    install_order_store(monkeypatch, [document])

    first = await OrderService.transition_state(
        "order-1", OrderState.ACCEPTED, actor_id="driver-a", driver_id="driver-a"
    )
    second = await OrderService.transition_state(
        "order-1", OrderState.ACCEPTED, actor_id="driver-a", driver_id="driver-a"
    )

    assert first.driver_id == second.driver_id == "driver-a"
    assert document["driver_id"] == "driver-a"


# ── Cancel racing accept ────────────────────────────────────────────


@pytest.mark.asyncio
async def test_cancel_racing_an_accept_leaves_one_coherent_state(monkeypatch):
    from app.order.service import OrderService

    document = order_document()
    install_order_store(monkeypatch, [document])

    results = await asyncio.gather(
        OrderService.transition_state(
            "order-1", OrderState.ACCEPTED, actor_id="driver-a", driver_id="driver-a"
        ),
        OrderService.transition_state(
            "order-1", OrderState.CANCELLED, actor_id="consumer-1", reason="consumer_cancelled"
        ),
        return_exceptions=True,
    )

    # Both may legitimately succeed in sequence (OFFERED → ACCEPTED → CANCELLED),
    # but the order must never end up in a state nobody wrote, and the audit
    # trail must explain how it got there.
    assert document["state"] in (OrderState.ACCEPTED.value, OrderState.CANCELLED.value)
    recorded = [e["state"] for e in document["events"]]
    assert recorded, "every applied transition leaves an event"
    assert recorded[-1] == document["state"]
    for result in results:
        if isinstance(result, BaseException):
            assert isinstance(result, InvalidStateTransition)


@pytest.mark.asyncio
async def test_cancelling_after_pickup_is_refused(monkeypatch):
    from app.order.service import OrderService

    document = order_document(state=OrderState.DELIVERED.value, driver_id="driver-a")
    install_order_store(monkeypatch, [document])

    with pytest.raises(InvalidStateTransition):
        await OrderService.transition_state(
            "order-1", OrderState.CANCELLED, actor_id="consumer-1"
        )
    assert document["state"] == OrderState.DELIVERED.value
    assert document["events"] == []


# ── Terminal states ─────────────────────────────────────────────────


@pytest.mark.parametrize("terminal", [OrderState.DELIVERED, OrderState.CANCELLED])
@pytest.mark.parametrize(
    "target",
    [
        OrderState.CREATED,
        OrderState.OFFERED,
        OrderState.ACCEPTED,
        OrderState.ARRIVED_AT_MERCHANT,
        OrderState.READY_FOR_PICKUP,
        OrderState.PICKED_UP,
        OrderState.ARRIVED_AT_CUSTOMER,
        OrderState.DELIVERED,
        OrderState.CANCELLED,
    ],
)
@pytest.mark.asyncio
async def test_terminal_orders_never_move_again(monkeypatch, terminal, target):
    from app.order.service import OrderService

    document = order_document(state=terminal.value, driver_id="driver-a")
    collection = install_order_store(monkeypatch, [document])

    with pytest.raises(InvalidStateTransition):
        await OrderService.transition_state(
            "order-1", target, actor_id="whoever", driver_id="driver-a"
        )

    assert document["state"] == terminal.value
    assert collection.update_calls == 0, "a refused transition must not touch the database"


@pytest.mark.asyncio
async def test_legacy_state_spelling_is_still_guarded(monkeypatch):
    """Documents written as `OrderState.OFFERED` must transition, and race, correctly."""
    from app.order.service import OrderService

    document = order_document(state="OrderState.OFFERED")
    install_order_store(monkeypatch, [document])

    results = await asyncio.gather(
        OrderService.transition_state(
            "order-1", OrderState.ACCEPTED, actor_id="a", driver_id="a"
        ),
        OrderService.transition_state(
            "order-1", OrderState.ACCEPTED, actor_id="b", driver_id="b"
        ),
        return_exceptions=True,
    )
    assert len([r for r in results if not isinstance(r, BaseException)]) == 1
    assert document["state"] == OrderState.ACCEPTED.value


# ── Driver ownership ────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_a_driver_cannot_advance_someone_elses_delivery(monkeypatch):
    from app.order.service import OrderService

    document = order_document(state=OrderState.PICKED_UP.value, driver_id="driver-a")
    collection = install_order_store(monkeypatch, [document])

    with pytest.raises(OrderConflict):
        await OrderService.transition_state(
            "order-1",
            OrderState.DELIVERED,
            actor_id="driver-b",
            require_driver_id="driver-b",
        )
    assert document["state"] == OrderState.PICKED_UP.value
    assert collection.update_calls == 0

    # The assigned driver may.
    await OrderService.transition_state(
        "order-1",
        OrderState.DELIVERED,
        actor_id="driver-a",
        require_driver_id="driver-a",
    )
    assert document["state"] == OrderState.DELIVERED.value


@pytest.mark.asyncio
async def test_expected_states_refuses_a_move_from_the_wrong_state(monkeypatch):
    from app.order.service import OrderService

    document = order_document(state=OrderState.ACCEPTED.value, driver_id="driver-a")
    install_order_store(monkeypatch, [document])

    with pytest.raises(OrderConflict):
        await OrderService.transition_state(
            "order-1",
            OrderState.DELIVERED,
            actor_id="driver-a",
            expected_states={OrderState.PICKED_UP, OrderState.ARRIVED_AT_CUSTOMER},
        )
    assert document["state"] == OrderState.ACCEPTED.value


# ── Releasing a driver ──────────────────────────────────────────────


@pytest.mark.asyncio
async def test_release_returns_a_pre_pickup_order_to_the_pool(monkeypatch):
    from app.order.service import OrderService

    document = order_document(state=OrderState.ACCEPTED.value, driver_id="driver-a")
    install_order_store(monkeypatch, [document])

    released = await OrderService.release_driver("order-1", "driver-a")

    assert released is not None
    assert document["state"] == OrderState.CREATED.value
    assert document["driver_id"] is None
    # The driver who walked away is not offered it again.
    assert document["declined_by"] == ["driver-a"]
    assert document["events"][-1]["reason"] == "driver_released"
    assert document["events"][-1]["metadata"]["from"] == OrderState.ACCEPTED.value


@pytest.mark.asyncio
async def test_release_refuses_once_the_food_is_collected(monkeypatch):
    from app.order.service import OrderService

    document = order_document(state=OrderState.PICKED_UP.value, driver_id="driver-a")
    install_order_store(monkeypatch, [document])

    assert await OrderService.release_driver("order-1", "driver-a") is None
    assert document["state"] == OrderState.PICKED_UP.value
    assert document["driver_id"] == "driver-a"


@pytest.mark.asyncio
async def test_release_refuses_a_driver_who_does_not_hold_the_order(monkeypatch):
    from app.order.service import OrderService

    document = order_document(state=OrderState.ACCEPTED.value, driver_id="driver-a")
    install_order_store(monkeypatch, [document])

    assert await OrderService.release_driver("order-1", "driver-b") is None
    assert document["driver_id"] == "driver-a"


# ── Dead letter ─────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_dead_lettering_an_order_fires_exactly_once(monkeypatch):
    from app.order.service import OrderService

    document = order_document(state=OrderState.OFFERED.value)
    install_order_store(monkeypatch, [document])

    results = await asyncio.gather(
        *(OrderService.mark_dispatch_escalated("order-1") for _ in range(5))
    )

    assert sum(1 for r in results if r) == 1, "ops is paged once, not five times"
    assert document["dispatch_escalated"] is True
    assert document["dispatch_escalated_at"] is not None
    assert document["events"][-1]["reason"] == "dispatch_escalated"
