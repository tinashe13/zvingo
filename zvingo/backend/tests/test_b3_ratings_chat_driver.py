"""Reviews, driver summary, in-app chat, and the driver profile contract."""

from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.order.models import OrderEvent
from app.order.state_machine import OrderState
from app.rating.schemas import ReviewCreate
from app.rating.service import ON_TIME_SLA_MINUTES, fold_average
from app.time_utils import utc_now


class Query:
    def __init__(self, values=None, count=None):
        self.values = list(values or [])
        self.count_value = len(self.values) if count is None else count
        self.skip_value = None
        self.limit_value = None
        self.update_arg = None

    def sort(self, *args):
        return self

    def skip(self, value):
        self.skip_value = value
        return self

    def limit(self, value):
        self.limit_value = value
        return self

    async def to_list(self):
        return self.values

    async def count(self):
        return self.count_value

    async def update(self, arg):
        self.update_arg = arg
        return SimpleNamespace(modified_count=len(self.values))


def user(id="consumer-1", role="consumer", **overrides):
    values = {"id": id, "role": role, "save": AsyncMock()}
    values.update(overrides)
    return SimpleNamespace(**values)


def order(**overrides):
    values = {
        "id": "order-1",
        "consumer_id": "consumer-1",
        "driver_id": "driver-1",
        "merchant_id": "restaurant-1",
        "state": OrderState.DELIVERED,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


# ── Review submission rules ─────────────────────────────────────────


def fake_review_class(existing=None):
    class FakeReview:
        order_id = SimpleNamespace(__eq__=lambda self, other: ("eq", other))
        restaurant_id = SimpleNamespace(__eq__=lambda self, other: ("eq", other))
        driver_id = SimpleNamespace(__eq__=lambda self, other: ("eq", other))
        find_one = AsyncMock(return_value=existing)
        inserted = []

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "review-1"
            self.created_at = utc_now()
            self.insert = AsyncMock(side_effect=lambda: FakeReview.inserted.append(self))

        @classmethod
        def find(cls, *args, **kwargs):
            return Query(cls.inserted)

    return FakeReview


@pytest.mark.asyncio
async def test_only_the_ordering_consumer_may_review(monkeypatch):
    import app.rating.router as module

    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order())))
    monkeypatch.setattr(module, "Review", fake_review_class())

    with pytest.raises(HTTPException) as exc:
        await module.create_review("order-1", ReviewCreate(restaurant_rating=5), user("driver-1"))
    assert exc.value.status_code == 403

    with pytest.raises(HTTPException) as exc:
        await module.create_review("order-1", ReviewCreate(restaurant_rating=5), user("stranger"))
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_only_a_delivered_order_may_be_reviewed(monkeypatch):
    import app.rating.router as module

    monkeypatch.setattr(module, "Review", fake_review_class())
    for state in (OrderState.CREATED, OrderState.PICKED_UP, OrderState.CANCELLED):
        monkeypatch.setattr(
            module, "Order", SimpleNamespace(get=AsyncMock(return_value=order(state=state)))
        )
        with pytest.raises(HTTPException) as exc:
            await module.create_review("order-1", ReviewCreate(restaurant_rating=5), user())
        assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_an_order_can_only_be_reviewed_once(monkeypatch):
    import app.rating.router as module

    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order())))
    monkeypatch.setattr(module, "Review", fake_review_class(existing=SimpleNamespace(id="r0")))

    with pytest.raises(HTTPException) as exc:
        await module.create_review("order-1", ReviewCreate(restaurant_rating=5), user())
    assert exc.value.status_code == 400
    assert "already been reviewed" in exc.value.detail


@pytest.mark.asyncio
async def test_a_duplicate_insert_race_is_reported_as_already_reviewed(monkeypatch):
    """The unique index, not the read-before-write, is the real guard."""
    import app.rating.router as module

    FakeReview = fake_review_class()

    def exploding(**kwargs):
        instance = SimpleNamespace(**kwargs)
        instance.insert = AsyncMock(
            side_effect=RuntimeError("E11000 duplicate key error")
        )
        return instance

    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order())))
    monkeypatch.setattr(module, "Review", exploding)
    monkeypatch.setattr(
        module.Review, "find_one", AsyncMock(return_value=None), raising=False
    )
    monkeypatch.setattr(module, "Review", type("R", (), {
        "order_id": SimpleNamespace(__eq__=lambda self, other: ("eq", other)),
        "find_one": AsyncMock(return_value=None),
        "__new__": lambda cls, **kw: exploding(**kw),
    }))

    with pytest.raises(HTTPException) as exc:
        await module.create_review("order-1", ReviewCreate(restaurant_rating=5), user())
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_a_pickup_order_cannot_be_given_a_driver_rating(monkeypatch):
    import app.rating.router as module

    monkeypatch.setattr(
        module, "Order", SimpleNamespace(get=AsyncMock(return_value=order(driver_id=None)))
    )
    monkeypatch.setattr(module, "Review", fake_review_class())

    with pytest.raises(HTTPException) as exc:
        await module.create_review(
            "order-1", ReviewCreate(restaurant_rating=5, driver_rating=5), user()
        )
    assert exc.value.status_code == 400


def test_star_bounds_are_rejected_at_the_schema_not_the_database():
    for bad in (0, 6, -1):
        with pytest.raises(ValidationError):
            ReviewCreate(restaurant_rating=bad)
        with pytest.raises(ValidationError):
            ReviewCreate(restaurant_rating=5, driver_rating=bad)


@pytest.mark.asyncio
async def test_restaurant_and_driver_aggregates_move_separately(monkeypatch):
    import app.rating.router as module

    monkeypatch.setattr(module, "Order", SimpleNamespace(get=AsyncMock(return_value=order())))
    monkeypatch.setattr(module, "Review", fake_review_class())
    restaurant_rating, driver_rating = AsyncMock(), AsyncMock()
    monkeypatch.setattr(module, "apply_restaurant_rating", restaurant_rating)
    monkeypatch.setattr(module, "apply_driver_rating", driver_rating)

    created = await module.create_review(
        "order-1",
        ReviewCreate(restaurant_rating=5, driver_rating=3, tags=["Hot food"]),
        user(),
    )
    restaurant_rating.assert_awaited_once_with("restaurant-1", 5)
    driver_rating.assert_awaited_once_with("driver-1", 3)
    assert created.tags == ["Hot food"]

    # Restaurant-only review leaves the driver aggregate untouched.
    driver_rating.reset_mock()
    await module.create_review("order-1", ReviewCreate(restaurant_rating=4), user())
    driver_rating.assert_not_awaited()


# ── Aggregates are folded, never recomputed ─────────────────────────


def test_fold_average_is_incremental():
    assert fold_average(None, 0, 5) == (5.0, 1)
    assert fold_average(4.0, 1, 5) == (4.5, 2)
    assert fold_average(4.5, 2, 3) == (4.0, 3)
    # A stored count with no stored average still starts cleanly.
    assert fold_average(None, 7, 4) == (4.0, 1)


@pytest.mark.asyncio
async def test_restaurant_aggregate_is_resolved_by_merchant_id_too(monkeypatch):
    """Orders carry merchant_id; a review must still land on the restaurant."""
    import app.catalog.models as catalog_models
    from app.rating.service import apply_restaurant_rating

    shop = SimpleNamespace(rating=4.0, review_count=1, save=AsyncMock())

    class FakeRestaurant:
        merchant_id = SimpleNamespace(__eq__=lambda self, other: ("eq", other))
        get = AsyncMock(return_value=None)
        find_one = AsyncMock(return_value=shop)

    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    await apply_restaurant_rating("merchant-1", 5)
    assert shop.review_count == 2
    assert shop.rating == 4.5
    shop.save.assert_awaited_once()


@pytest.mark.asyncio
async def test_review_listings_are_paginated(monkeypatch):
    import app.rating.router as module

    reviews = [
        SimpleNamespace(
            id=f"r{i}", order_id=f"o{i}", consumer_id="c", restaurant_id="restaurant-1",
            driver_id="driver-1", restaurant_rating=5, driver_rating=5, comment=None,
            tags=[], created_at=utc_now(),
        )
        for i in range(5)
    ]
    query = Query(reviews)
    monkeypatch.setattr(module, "Review", SimpleNamespace(
        restaurant_id=SimpleNamespace(__eq__=lambda self, other: ("eq", other)),
        driver_id=SimpleNamespace(__eq__=lambda self, other: ("eq", other)),
        find=lambda *a: query,
    ))

    await module.list_restaurant_reviews("restaurant-1", offset=10, limit=5)
    assert (query.skip_value, query.limit_value) == (10, 5)

    await module.list_driver_reviews("driver-1")
    assert query.limit_value == module.DEFAULT_PAGE_SIZE


# ── Driver summary, for the driver app's ratings screen ─────────────


@pytest.mark.asyncio
async def test_driver_summary_returns_everything_the_ratings_screen_needs(monkeypatch):
    import app.rating.router as module
    import app.rating.service as service

    driver = SimpleNamespace(
        driver_rating=4.7, driver_review_count=3, full_name="Jane Doe"
    )
    reviews = [
        SimpleNamespace(
            driver_rating=5, comment="Very fast", tags=["Polite"],
            consumer_id="consumer-1", created_at=utc_now(),
        ),
        SimpleNamespace(
            driver_rating=4, comment="", tags=[],
            consumer_id="consumer-2", created_at=utc_now(),
        ),
        SimpleNamespace(
            driver_rating=None, comment="restaurant only", tags=[],
            consumer_id="consumer-3", created_at=utc_now(),
        ),
    ]
    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=driver))
    monkeypatch.setattr(module, "Review", SimpleNamespace(
        driver_id=SimpleNamespace(__eq__=lambda self, other: ("eq", other)),
        find=lambda *a: Query(reviews),
    ))
    monkeypatch.setattr(
        module,
        "driver_performance",
        AsyncMock(
            return_value={
                "lifetime_deliveries": 156,
                "window_days": 30,
                "deliveries_in_window": 42,
                "completion_rate": 98.0,
                "on_time_rate": 95.0,
                "acceptance_rate": 92.0,
                "offers_in_window": 46,
            }
        ),
    )

    summary = await module.driver_rating_summary("driver-1")

    assert summary["driver_rating"] == 4.7
    assert summary["rated_reviews"] == 2
    assert summary["breakdown"] == {"1": 0, "2": 0, "3": 0, "4": 1, "5": 1}
    assert summary["lifetime_deliveries"] == 156
    assert summary["acceptance_rate"] == 92.0
    assert summary["completion_rate"] == 98.0
    assert summary["on_time_rate"] == 95.0
    assert summary["on_time_sla_minutes"] == ON_TIME_SLA_MINUTES

    # Recent feedback carries a masked name — drivers never see a full surname.
    assert [f["customer_name"] for f in summary["recent_feedback"]] == [
        "Jane D.",
        "Jane D.",
    ]
    assert summary["recent_feedback"][0]["comment"] == "Very fast"


@pytest.mark.asyncio
async def test_driver_summary_404s_for_an_unknown_driver(monkeypatch):
    import app.rating.router as module

    monkeypatch.setattr(module.User, "get", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.driver_rating_summary("missing")
    assert exc.value.status_code == 404


@pytest.mark.asyncio
async def test_driver_performance_measures_completion_and_punctuality(monkeypatch):
    import app.order.models as order_models
    import app.rating.service as service

    now = utc_now()

    def delivered(minutes):
        return SimpleNamespace(
            state=OrderState.DELIVERED,
            events=[
                OrderEvent(state=OrderState.ACCEPTED, timestamp=now - timedelta(minutes=minutes)),
                OrderEvent(state=OrderState.DELIVERED, timestamp=now),
            ],
        )

    orders = [delivered(20), delivered(30), delivered(90)]
    orders.append(SimpleNamespace(state=OrderState.CANCELLED, events=[]))

    class FakeOrder:
        @staticmethod
        def find(query):
            if query.get("state") == OrderState.DELIVERED:
                return Query([o for o in orders if o.state == OrderState.DELIVERED])
            return Query(orders)

    monkeypatch.setattr(order_models, "Order", FakeOrder)
    monkeypatch.setattr(
        "app.notification.offer_metrics.offer_stats",
        AsyncMock(return_value={"offers_sent": 8, "offers_accepted": 4}),
    )

    metrics = await service.driver_performance("driver-1")
    assert metrics["lifetime_deliveries"] == 3
    assert metrics["deliveries_in_window"] == 3
    assert metrics["completion_rate"] == 75.0        # 3 delivered of 4 terminal
    assert metrics["on_time_rate"] == pytest.approx(66.7, abs=0.1)  # 2 of 3 within SLA
    assert metrics["acceptance_rate"] == 50.0        # 4 accepted of 8 offered


@pytest.mark.asyncio
async def test_driver_performance_reports_unknown_rather_than_zero(monkeypatch):
    """A brand-new driver shows "—", not an insulting 0%."""
    import app.order.models as order_models
    import app.rating.service as service

    class FakeOrder:
        @staticmethod
        def find(query):
            return Query([])

    monkeypatch.setattr(order_models, "Order", FakeOrder)
    monkeypatch.setattr(
        "app.notification.offer_metrics.offer_stats",
        AsyncMock(return_value={"offers_sent": 0, "offers_accepted": 0}),
    )

    metrics = await service.driver_performance("new-driver")
    assert metrics["completion_rate"] is None
    assert metrics["on_time_rate"] is None
    assert metrics["acceptance_rate"] is None
    assert metrics["lifetime_deliveries"] == 0


# ── Chat ────────────────────────────────────────────────────────────


def fake_chat(monkeypatch, messages=None):
    import app.chat.router as module

    query = Query(messages or [])

    class FakeMessage:
        order_id = SimpleNamespace(__eq__=lambda self, other: ("eq", other))
        created = []

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "m-new"
            self.created_at = utc_now()
            self.insert = AsyncMock(side_effect=lambda: FakeMessage.created.append(self))

        @classmethod
        def find(cls, *args, **kwargs):
            return query

    FakeMessage.created = []
    monkeypatch.setattr(module, "ChatMessage", FakeMessage)
    monkeypatch.setattr(
        module.aioredis,
        "from_url",
        lambda *a, **k: SimpleNamespace(publish=AsyncMock(), close=AsyncMock()),
    )
    return module, FakeMessage, query


@pytest.mark.asyncio
async def test_chat_is_closed_once_the_order_is_finished(monkeypatch):
    import app.chat.schemas as schemas

    module, _, _ = fake_chat(monkeypatch)
    monkeypatch.setattr(module, "_can_participate", AsyncMock(return_value=True))

    for state in (OrderState.DELIVERED, OrderState.CANCELLED):
        monkeypatch.setattr(
            module.Order, "get", AsyncMock(return_value=order(state=state))
        )
        with pytest.raises(HTTPException) as exc:
            await module.send_message(
                "order-1", schemas.ChatMessageCreate(text="hello?"), user()
            )
        assert exc.value.status_code == 409

    # History stays readable after the order closes.
    listed = await module.list_messages("order-1", user())
    assert listed == []


@pytest.mark.asyncio
async def test_chat_allows_messages_while_the_order_is_live(monkeypatch):
    import app.chat.schemas as schemas

    module, FakeMessage, _ = fake_chat(monkeypatch)
    monkeypatch.setattr(module, "_can_participate", AsyncMock(return_value=True))
    monkeypatch.setattr(
        module.Order, "get", AsyncMock(return_value=order(state=OrderState.PICKED_UP))
    )

    sent = await module.send_message(
        "order-1", schemas.ChatMessageCreate(text="  I'm at the gate  "), user()
    )
    assert sent.text == "I'm at the gate"
    # The sender has implicitly read their own message.
    assert sent.read_by == ["consumer-1"]


def test_blank_and_oversized_messages_are_rejected():
    import app.chat.schemas as schemas

    with pytest.raises(ValidationError):
        schemas.ChatMessageCreate(text="   ")
    with pytest.raises(ValidationError):
        schemas.ChatMessageCreate(text="")
    with pytest.raises(ValidationError):
        schemas.ChatMessageCreate(text="x" * (schemas.MAX_MESSAGE_LENGTH + 1))


@pytest.mark.asyncio
async def test_chat_rejects_non_participants(monkeypatch):
    import app.chat.schemas as schemas

    module, _, _ = fake_chat(monkeypatch)
    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "_can_participate", AsyncMock(return_value=False))

    for call in (
        module.list_messages("order-1", user("stranger")),
        module.unread_count("order-1", user("stranger")),
        module.mark_read("order-1", user("stranger")),
    ):
        with pytest.raises(HTTPException) as exc:
            await call
        assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_chat_listing_is_paginated(monkeypatch):
    module, _, query = fake_chat(monkeypatch, messages=[])
    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "_can_participate", AsyncMock(return_value=True))

    await module.list_messages("order-1", user(), offset=20, limit=10)
    assert (query.skip_value, query.limit_value) == (20, 10)

    await module.list_messages("order-1", user())
    assert query.limit_value == module.DEFAULT_PAGE_SIZE


@pytest.mark.asyncio
async def test_read_state_is_tracked_per_participant(monkeypatch):
    unread = [
        SimpleNamespace(
            id="m1", order_id="order-1", sender_id="driver-1", sender_role="driver",
            text="Outside", read_by=[], created_at=utc_now(),
        )
    ]
    module, _, query = fake_chat(monkeypatch, messages=unread)
    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=order()))
    monkeypatch.setattr(module, "_can_participate", AsyncMock(return_value=True))

    counted = await module.unread_count("order-1", user())
    assert counted.unread_count == 1

    receipt = await module.mark_read("order-1", user())
    assert receipt.read_count == 1
    # Only messages from *other* people, not yet read by this user, are touched.
    assert query.update_arg == {"$addToSet": {"read_by": "consumer-1"}}


@pytest.mark.asyncio
async def test_chat_stream_alias_authorises_like_the_original(monkeypatch):
    module, _, _ = fake_chat(monkeypatch)
    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=None))

    request = SimpleNamespace(is_disconnected=AsyncMock(return_value=True))
    for call in (
        module.stream_messages(request, "missing", user()),
        module.stream_messages_alias(request, "missing", user()),
    ):
        with pytest.raises(HTTPException) as exc:
            await call
        assert exc.value.status_code == 404


# ── Driver profile ──────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_driver_schedule_persists_and_expands_shift_windows():
    import app.driver.router as module

    driver = user("driver-1", role="driver", schedule=[], vehicle=None)
    saved = await module.save_schedule(
        module.ScheduleUpdate(days=[module.ScheduleDay(day=4, slots=[2])]), driver
    )

    driver.save.assert_awaited_once()
    assert driver.schedule == saved["days"]
    assert saved["days"][0]["windows"] == [
        {"slot": 2, "start": "17:00", "end": "23:00"}
    ]
    assert saved["timezone"] == "Africa/Harare"


@pytest.mark.asyncio
async def test_driver_schedule_accepts_explicit_time_windows():
    import app.driver.router as module

    driver = user("driver-1", role="driver", schedule=[], vehicle=None)
    saved = await module.save_schedule(
        module.ScheduleUpdate(
            days=[
                module.ScheduleDay(
                    day=0, windows=[module.ScheduleSlot(start="05:30", end="09:45")]
                )
            ]
        ),
        driver,
    )
    assert saved["days"][0]["windows"][0]["start"] == "05:30"
    assert saved["days"][0]["windows"][0]["end"] == "09:45"


def test_driver_schedule_rejects_impossible_windows():
    import app.driver.router as module

    with pytest.raises(ValidationError):
        module.ScheduleSlot(start="18:00", end="09:00")
    with pytest.raises(ValidationError):
        module.ScheduleSlot(start="nine-ish", end="10:00")
    with pytest.raises(ValidationError):
        module.ScheduleSlot()
    with pytest.raises(ValidationError):
        module.ScheduleDay(day=9, slots=[0])


@pytest.mark.asyncio
async def test_driver_schedule_is_owner_scoped():
    """The endpoint writes to the caller's own document — never another's."""
    import app.driver.router as module

    driver = user("driver-1", role="driver", schedule=[], vehicle=None)
    other = user("driver-2", role="driver", schedule=[], vehicle=None)

    await module.save_schedule(
        module.ScheduleUpdate(days=[module.ScheduleDay(day=1, slots=[0])]), driver
    )
    assert driver.schedule
    assert other.schedule == []
    other.save.assert_not_awaited()


@pytest.mark.asyncio
async def test_driver_vehicle_merges_and_validates():
    import app.driver.router as module

    driver = user("driver-1", role="driver", schedule=[], vehicle=None)
    await module.save_vehicle(
        module.VehicleUpdate(make="Toyota", vehicle_type="Motorbike"), driver
    )
    result = await module.save_vehicle(module.VehicleUpdate(plate=" abc 123 "), driver)

    assert result["vehicle"] == {
        "make": "Toyota",
        "vehicle_type": "motorbike",
        "plate": "ABC123",
    }
    assert "motorbike" in result["vehicle_types"]

    with pytest.raises(ValidationError):
        module.VehicleUpdate(vehicle_type="helicopter")
