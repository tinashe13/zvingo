import asyncio
import json
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.dispatch.schemas import DriverLocationUpdate
from app.order.schemas import OrderCreate, OrderItem
from app.order.state_machine import InvalidStateTransition, OrderState
from app.location.models import Location
from app.payment.models import PaymentMethod, PaymentStatus


class Field:
    def __eq__(self, other):
        return ("eq", other)


class QueryResult:
    def __init__(self, values):
        self.values = values

    def sort(self, *_args):
        return self

    def skip(self, *_args):
        return self

    def limit(self, *_args):
        return self

    async def to_list(self):
        return self.values


class RedisDouble:
    def __init__(self):
        self.closed = False
        self.values = {}
        self.hashes = {}
        self.geo_candidates = []
        self.published = []
        self.setex_values = []

    async def get(self, key):
        return self.values.get(key)

    async def close(self):
        self.closed = True

    async def geoadd(self, *args):
        self.geoadd_args = args

    async def hset(self, *args, **kwargs):
        self.hset_args = (args, kwargs)

    async def publish(self, channel, payload):
        self.published.append((channel, payload))

    async def setex(self, key, ttl, value):
        self.setex_values.append((key, ttl, value))

    async def geosearch(self, *_args, **_kwargs):
        return self.geo_candidates

    async def hgetall(self, key):
        return self.hashes.get(key, {})


def order_input(**overrides):
    values = {
        "merchant_id": "merchant",
        "consumer_id": "consumer",
        "items": [OrderItem(name="Burger", quantity=1, price=10)],
        "total_amount": 15,
        "pickup_lat": -17.8,
        "pickup_lng": 31.0,
        "dropoff_lat": -17.9,
        "dropoff_lng": 31.1,
    }
    values.update(overrides)
    return OrderCreate(**values)


@pytest.mark.asyncio
async def test_order_creation_idempotency_locations_fees_and_side_effects(monkeypatch):
    import app.catalog.models as catalog_models
    import app.dispatch.service as dispatch_module
    import app.notification.service as notification_module
    import app.order.service as module

    existing = object()

    class FakeOrder:
        idempotency_key = Field()
        find_one = AsyncMock(return_value=existing)
        instances = []

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "order-123456"
            self.delivery_fee = 0
            self.insert = AsyncMock()
            FakeOrder.instances.append(self)

    monkeypatch.setattr(module, "Order", FakeOrder)
    assert await module.OrderService.create_order(order_input(idempotency_key="key")) is existing

    FakeOrder.find_one.return_value = None
    monkeypatch.setattr(notification_module.notification_service, "notify_merchant", AsyncMock())
    monkeypatch.setattr(dispatch_module.dispatch_service, "dispatch_order", AsyncMock())
    created_coroutines = []

    def consume_task(coro):
        created_coroutines.append(coro)
        coro.close()
        return MagicMock()

    monkeypatch.setattr(module.asyncio, "create_task", consume_task)
    created = await module.OrderService.create_order(order_input())
    assert created.delivery_fee > 0
    created.insert.assert_awaited_once()
    notification_module.notification_service.notify_merchant.assert_awaited_once_with(
        "merchant", "order-123456"
    )
    assert len(created_coroutines) == 1

    provided = await module.OrderService.create_order(order_input(delivery_fee=7.5))
    assert provided.delivery_fee == 7.5

    restaurant = SimpleNamespace(
        id="r1",
        name="Restaurant",
        location=Location.from_lat_lng(-17.7, 31.2),
    )
    class FakeRestaurant:
        merchant_id = Field()
        get = AsyncMock(return_value=None)
        find_one = AsyncMock(return_value=restaurant)

    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    resolved = await module.OrderService.create_order(
        order_input(pickup_lat=0, pickup_lng=0)
    )
    assert resolved.pickup_location.coordinates == [31.2, -17.7]

    # Unresolved dropoff (null island) is rejected even with a valid pickup.
    with pytest.raises(ValueError, match="Dropoff location unresolved"):
        await module.OrderService.create_order(
            order_input(pickup_lat=0, pickup_lng=0, dropoff_lat=0, dropoff_lng=0)
        )

    FakeRestaurant.get.side_effect = RuntimeError("db")
    with pytest.raises(ValueError, match="Pickup location unresolved"):
        await module.OrderService.create_order(order_input(pickup_lat=0, pickup_lng=0))
    FakeRestaurant.get.side_effect = None
    FakeRestaurant.get.return_value = SimpleNamespace(location=None)
    with pytest.raises(ValueError, match="Pickup location unresolved"):
        await module.OrderService.create_order(order_input(pickup_lat=0, pickup_lng=0))


@pytest.mark.asyncio
async def test_order_transitions(monkeypatch):
    import app.notification.service as notification_module
    import app.order.service as module

    monkeypatch.setattr(module.Order, "get", AsyncMock(return_value=None))
    assert await module.OrderService.transition_state("missing", OrderState.ACCEPTED) is None

    invalid = SimpleNamespace(state=OrderState.CREATED)
    module.Order.get.return_value = invalid
    monkeypatch.setattr(module, "validate_transition", MagicMock(side_effect=InvalidStateTransition("bad")))
    with pytest.raises(InvalidStateTransition):
        await module.OrderService.transition_state("1", OrderState.DELIVERED)

    monkeypatch.setattr(module, "validate_transition", MagicMock())
    order = SimpleNamespace(
        state=OrderState.OFFERED,
        driver_id=None,
        events=[],
        consumer_id="consumer",
        save=AsyncMock(),
    )
    module.Order.get.return_value = order
    notify = AsyncMock()
    monkeypatch.setattr(notification_module.notification_service, "notify_consumer", notify)
    tasks = []
    monkeypatch.setattr(
        module.asyncio,
        "create_task",
        lambda coro: (tasks.append(coro), coro.close())[0],
    )
    result = await module.OrderService.transition_state(
        "1", OrderState.ACCEPTED, actor_id="driver", driver_id="driver"
    )
    assert result is order and order.driver_id == "driver"
    assert order.events[-1].actor_id == "driver"
    order.save.assert_awaited_once()
    assert len(tasks) == 1

    # A transition without an explicit driver_id must NOT assign a driver.
    order.driver_id = None
    order.state = OrderState.OFFERED
    await module.OrderService.transition_state("1", OrderState.ACCEPTED, actor_id="merchant")
    assert order.driver_id is None

    order.consumer_id = None
    order.state = OrderState.ACCEPTED
    await module.OrderService.transition_state("1", OrderState.ARRIVED_AT_MERCHANT)


@pytest.mark.asyncio
async def test_dispatch_location_scoring_and_workflows(monkeypatch):
    import app.dispatch.models as dispatch_models
    import app.dispatch.service as module
    import app.notification.service as notification_module
    import app.order.models as order_models
    import app.order.service as order_service

    redis = RedisDouble()
    service = module.DispatchService()
    service.redis = redis
    update = DriverLocationUpdate(
        driver_id="d1", lat=-17.8, lng=31.0, battery=80, timestamp=datetime.now()
    )
    await service.update_location(update)
    assert redis.geoadd_args[0] == "driver_locations"
    assert redis.published[0][0] == "driver_loc_d1"

    redis.geo_candidates = [("offline", 0.5), ("d1", 2.0), ("d2", 1.0)]
    redis.hashes = {
        "driver:offline": {"status": "BUSY"},
        "driver:d1": {
            "status": "ONLINE",
            "accept_rate": "0.5",
            "rating": "5",
            "connectivity_bonus": "1",
        },
        "driver:d2": {"status": "ONLINE"},
    }
    drivers = await service.find_drivers_for_order(-17.8, 31.0)
    # Offline/busy drivers are never candidates. Ranking is no longer
    # distance-only: d2 is closer and carries neutral priors, which beats d1's
    # perfect rating dragged down by a 0.5 acceptance rate.
    assert [driver[0] for driver in drivers] == ["d2", "d1"]

    # dispatch_order ranks with score_candidates (it logs the winning score);
    # find_drivers_for_order is the thin (driver_id, distance) view of it.
    def candidate(driver_id, distance_km, score):
        return {
            "driver_id": driver_id,
            "distance_km": distance_km,
            "score": score,
            "components": {},
        }

    find = AsyncMock(return_value=[])
    monkeypatch.setattr(service, "score_candidates", find)
    assert await service.dispatch_order("order", 0, 0) is None
    assert await service.dispatch_order("order", -17.8, 31.0) is None

    find.return_value = [candidate("d1", 1.2, 0.9), candidate("d2", 2.3, 0.4)]
    transition = AsyncMock()
    send_offer = AsyncMock()
    monkeypatch.setattr(order_service.OrderService, "transition_state", transition)
    monkeypatch.setattr(notification_module.notification_service, "send_offer", send_offer)
    await service.dispatch_order("order", -17.8, 31.0)
    # An order is offered to one driver at a time (DISPATCH_OFFER_FANOUT), so
    # only the best candidate is contacted in this round.
    assert send_offer.await_count == 1
    transition.side_effect = RuntimeError("already offered")
    await service.dispatch_order("order", -17.8, 31.0)

    transition.side_effect = None
    transition.return_value = None
    assert await service.accept_offer("d1", "order") is None
    order = SimpleNamespace(consumer_id="consumer")
    transition.return_value = order

    inserted = AsyncMock()

    class FakeDispatch:
        def __init__(self, **kwargs):
            self.kwargs = kwargs
            self.insert = inserted

    monkeypatch.setattr(dispatch_models, "Dispatch", FakeDispatch)
    notify = AsyncMock()
    monkeypatch.setattr(notification_module.notification_service, "notify_consumer", notify)
    assert await service.accept_offer("d1", "order") is order
    inserted.assert_awaited_once()
    # The consumer notification belongs to the state transition, so accepting no
    # longer sends a second, identical push of its own.
    notify.assert_not_awaited()
    assert await service.decline_offer("d1", "order") == {"status": "declined"}

    active = object()
    monkeypatch.setattr(order_models.Order, "find_one", AsyncMock(return_value=active))
    redis.hashes["driver:d1"] = {"status": "ONLINE"}
    state = await service.get_driver_state("d1")
    assert state == {"status": "ONLINE", "active_order": active}
    redis.hashes["driver:d2"] = {}
    assert (await service.get_driver_state("d2"))["status"] == "OFFLINE"


@pytest.mark.asyncio
async def test_payment_exchange_initiation_and_completion(monkeypatch):
    import app.payment.service as module

    redis = RedisDouble()
    # Rate resolution lives in app.finance.exchange now (auditable + pinnable),
    # so that is where the Redis connection is opened.
    monkeypatch.setattr(module.exchange.aioredis, "from_url", lambda *_a, **_k: redis)
    redis.values["exchange_rate:ZIG"] = "14"
    assert await module.PaymentService.get_exchange_rate("zig") == 14
    assert await module.PaymentService.get_exchange_rate("ZAR") == 18.5
    assert await module.PaymentService.get_exchange_rate("other") == 1
    assert redis.closed

    class FakePayment:
        paynow_reference = Field()
        order_id = Field()
        instances = []
        get = AsyncMock()
        find_one = AsyncMock()

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "payment-12345678"
            self.poll_url = None
            self.paynow_reference = None
            self.insert = AsyncMock()
            self.save = AsyncMock()
            FakePayment.instances.append(self)

    monkeypatch.setattr(module, "Payment", FakePayment)
    monkeypatch.setattr(module.PaymentService, "get_exchange_rate", AsyncMock(return_value=2))
    monkeypatch.setattr(
        module.paynow_client,
        "send_mobile",
        AsyncMock(return_value=SimpleNamespace(success=True, poll_url="mock://poll", reference="ref")),
    )
    tasks = []
    monkeypatch.setattr(
        module.asyncio,
        "create_task",
        lambda coro: (tasks.append(coro), coro.close())[0],
    )
    monkeypatch.setattr(settings := module.settings, "PAYMENT_MOCK_MODE", True)
    payment = await module.PaymentService.initiate_payment(
        "order", "consumer", 10, PaymentMethod.ECOCASH, "+263", "ZIG"
    )
    # Amounts are integer minor units: $10.00 at 2.0 ZIG/USD is 2000 ZIG cents.
    assert payment.amount_local_cents == 2000
    assert payment.amount_usd_cents == 1000
    assert payment.status == PaymentStatus.AWAITING_DELIVERY
    assert len(tasks) == 1

    module.paynow_client.send_mobile.return_value = SimpleNamespace(
        success=False, error="declined"
    )
    failed = await module.PaymentService.initiate_payment(
        "order", "consumer", 10, PaymentMethod.ECOCASH, "+263", "USD"
    )
    assert failed.amount_local_cents == 1000 and failed.status == PaymentStatus.FAILED

    monkeypatch.setattr(module.asyncio, "sleep", AsyncMock())
    FakePayment.get.return_value = None
    await module.PaymentService._mock_auto_complete("missing")
    awaiting = SimpleNamespace(
        status=PaymentStatus.AWAITING_DELIVERY,
        updated_at=None,
        save=AsyncMock(),
    )
    FakePayment.get.return_value = awaiting
    success_hook = AsyncMock()
    monkeypatch.setattr(module.PaymentService, "_on_payment_success", success_hook)
    await module.PaymentService._mock_auto_complete("payment")
    assert awaiting.status == PaymentStatus.PAID
    success_hook.assert_awaited_once_with(awaiting)
    awaiting.status = PaymentStatus.FAILED
    await module.PaymentService._mock_auto_complete("payment")


@pytest.mark.asyncio
async def test_payment_status_webhooks_and_refunds(monkeypatch):
    import app.order.service as order_service
    import app.payment.service as module

    payment = SimpleNamespace(
        id="p1",
        order_id="o1",
        consumer_id="c1",
        # Only a Paynow-hosted poll URL is ever followed; a webhook cannot
        # redirect us at an endpoint of its own choosing.
        poll_url="https://www.paynow.co.zw/interface/poll/abc123",
        paynow_reference="ref",
        amount_usd_cents=1000,
        amount_local_cents=1000,
        currency="USD",
        charge_amount_minor=1000,
        charge_currency="USD",
        breakdown=None,
        fx_rate_micros=None,
        refund_request_id=None,
        status=PaymentStatus.AWAITING_DELIVERY,
        updated_at=None,
        save=AsyncMock(),
    )
    class FakePayment:
        paynow_reference = Field()
        order_id = Field()
        get = AsyncMock(return_value=None)
        find_one = AsyncMock(return_value=None)

    class FakeRefundRequest:
        created = []

        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.id = "refund-1"
            self.external_reference = None
            self.resolved_by = None
            self.resolved_at = None
            self.resolution_note = ""
            self.ledger_posted = False
            self.updated_at = None
            FakeRefundRequest.created.append(self)

        async def insert(self):
            return self

        async def save(self):
            return self

        @classmethod
        async def find_one(cls, *args):
            return None

    monkeypatch.setattr(module, "Payment", FakePayment)
    monkeypatch.setattr(module, "RefundRequest", FakeRefundRequest)
    assert await module.PaymentService.check_payment_status("missing") is None
    FakePayment.get.return_value = SimpleNamespace(poll_url=None)
    assert (await module.PaymentService.check_payment_status("p")).poll_url is None
    payment.status = PaymentStatus.PAID
    FakePayment.get.return_value = payment
    assert await module.PaymentService.check_payment_status("p") is payment

    success_hook = AsyncMock()
    monkeypatch.setattr(module.PaymentService, "_on_payment_success", success_hook)
    payment.status = PaymentStatus.AWAITING_DELIVERY
    monkeypatch.setattr(
        module.paynow_client,
        "check_status",
        AsyncMock(return_value=SimpleNamespace(paid=True, status="Paid")),
    )
    await module.PaymentService.check_payment_status("p")
    assert payment.status == PaymentStatus.PAID
    payment.status = PaymentStatus.AWAITING_DELIVERY
    module.paynow_client.check_status.return_value = SimpleNamespace(
        paid=False, status="Cancelled"
    )
    await module.PaymentService.check_payment_status("p")
    # A cancellation is now recorded as CANCELLED, not lumped in with FAILED.
    assert payment.status == PaymentStatus.CANCELLED
    payment.status = PaymentStatus.AWAITING_DELIVERY
    module.paynow_client.check_status.return_value = SimpleNamespace(
        paid=False, status="Pending"
    )
    assert await module.PaymentService.check_payment_status("p") is payment

    transition = AsyncMock(return_value=object())
    monkeypatch.setattr(order_service.OrderService, "transition_state", transition)
    await module.PaymentService._on_payment_success(payment)
    transition.return_value = None
    await module.PaymentService._on_payment_success(payment)

    assert await module.PaymentService.handle_webhook("unknown", "paid", "poll") is None
    FakePayment.find_one.return_value = payment
    payment.status = PaymentStatus.AWAITING_DELIVERY
    await module.PaymentService.handle_webhook("ref", "delivered", "poll")
    assert payment.status == PaymentStatus.PAID
    # PAID -> FAILED is not a legal transition: a late "failed" notification on
    # a settled payment is an anomaly for an operator, never a silent unwind.
    await module.PaymentService.handle_webhook("ref", "failed", "poll")
    assert payment.status == PaymentStatus.PAID
    # A replayed "paid" notification does not re-run settlement.
    assert await module.PaymentService.handle_webhook("ref", "paid", "poll") is payment
    assert payment.status == PaymentStatus.PAID
    assert await module.PaymentService.handle_webhook("ref", "pending", "poll") is payment
    assert await module.PaymentService.get_payment_for_order("o1") is payment

    FakePayment.get.return_value = None
    assert await module.PaymentService.refund_payment("missing") is None
    payment.status = PaymentStatus.FAILED
    FakePayment.get.return_value = payment
    assert await module.PaymentService.refund_payment("p") is payment
    payment.status = PaymentStatus.PAID
    await module.PaymentService.refund_payment("p")
    # Mock mode is the only path on which the provider reports a settled
    # refund, so the request closes out as COMPLETED with the money booked.
    assert payment.status == PaymentStatus.REFUNDED
    assert FakeRefundRequest.created[-1].status.value == "COMPLETED"
    assert FakeRefundRequest.created[-1].amount_minor == 1000


@pytest.mark.asyncio
async def test_notification_payloads_delivery_and_push(monkeypatch):
    import app.auth.models as auth_models
    import app.catalog.models as catalog_models
    import app.notification.fcm as fcm
    import app.notification.service as module
    import app.order.models as order_models

    assert module.haversine_km(0, 0, 0, 0) == 0
    assert module.mask_name("Prince") == "Prince"
    assert module.mask_name("John Smith") == "John S."

    redis = RedisDouble()
    monkeypatch.setattr(module.aioredis, "from_url", lambda *_a, **_k: redis)
    class FakeOrder:
        get = AsyncMock(return_value=None)

    monkeypatch.setattr(order_models, "Order", FakeOrder)
    payload = await module.NotificationService._build_offer_payload("missing", "d", 0)
    assert payload == {"order_id": "missing", "event": "offer"}

    items = [SimpleNamespace(name="Burger", quantity=2), {"name": "Fries", "quantity": 1}]
    order = SimpleNamespace(
        merchant_id="merchant",
        consumer_id="consumer",
        pickup_location=Location.from_lat_lng(-17.8, 31.0),
        dropoff_location=Location.from_lat_lng(-17.9, 31.1),
        items=items,
        delivery_fee=0,
        tip_amount=1,
        total_amount=4,
        delivery_instructions="Gate 2",
    )
    FakeOrder.get.return_value = order
    restaurant = SimpleNamespace(name="Cafe", address="Main St")
    class FakeRestaurant:
        merchant_id = Field()
        find_one = AsyncMock(return_value=restaurant)
        get = AsyncMock(return_value=None)

    class FakeUser:
        get = AsyncMock(
            return_value=SimpleNamespace(full_name="Jane Doe", fcm_token="token")
        )

    monkeypatch.setattr(catalog_models, "Restaurant", FakeRestaurant)
    monkeypatch.setattr(auth_models, "User", FakeUser)
    payload = await module.NotificationService._build_offer_payload(
        "abcdef123456", "d", 2.5
    )
    assert payload["merchant_name"] == "Cafe"
    assert payload["customer_name"] == "Jane D."
    assert payload["item_count"] == 3
    assert payload["items_summary"] == "Burger +2 more"
    # Order.total_amount is the basket SUBTOTAL (before fees, tip and discount),
    # so a $4.00 basket is 400 minor units. This previously asserted 0, because
    # the payload subtracted the fee and tip back out of a figure that had never
    # included them and clamped the negative result -- so a driver was shown a
    # $0.00 order value on the offer card they decide from.
    assert payload["order_subtotal_cents"] == 400
    assert payload["tip_cents"] == 100
    # Customer total = subtotal + delivery + service + tax + tip - discount.
    assert payload["total_cents"] == (
        400 + payload["delivery_fee_cents"] + 100
    )
    assert payload["short_id"] == "ZV123456"

    order.items = []
    order.delivery_fee = 6
    order.tip_amount = 0
    order.total_amount = 20
    FakeRestaurant.find_one.return_value = None
    FakeRestaurant.get.return_value = restaurant
    FakeUser.get.return_value = SimpleNamespace(full_name="", fcm_token=None)
    payload = await module.NotificationService._build_offer_payload("123", "d", 0)
    assert payload["items_summary"] == "Order"
    assert payload["delivery_fee_cents"] == 600

    push = AsyncMock(return_value=True)
    monkeypatch.setattr(fcm, "send_push_notification", push)
    FakeUser.get.return_value = SimpleNamespace(fcm_token="token")
    monkeypatch.setattr(
        module.NotificationService,
        "_build_offer_payload",
        AsyncMock(return_value={"merchant_name": "Cafe", "delivery_fee_cents": 500}),
    )
    await module.NotificationService.send_offer("d", "order", 1)
    push.assert_awaited()
    assert redis.published[-1][0] == "driver_d"
    assert redis.setex_values[-1][1] == 45
    FakeUser.get.return_value = None
    await module.NotificationService.send_offer("d", "order", 1)

    await module.NotificationService.notify_merchant("m", "o")
    assert redis.published[-1][0] == "merchant_m"
    FakeUser.get.return_value = SimpleNamespace(fcm_token="consumer-token")
    await module.NotificationService.notify_consumer(
        "c", "order123456", "picked_up", {"driver": "d"}
    )
    assert redis.published[-1][0] == "consumer_c"
    FakeUser.get.return_value = None
    await module.NotificationService.notify_consumer("c", "order", "custom")


@pytest.mark.asyncio
async def test_retry_service_lifecycle_loop_and_orders(monkeypatch):
    import app.catalog.models as catalog_models
    import app.dispatch.retry_service as module

    module.OrderRetryService._task = None
    task = MagicMock(cancel=MagicMock())
    coro_holder = []

    def create_task(coro):
        coro_holder.append(coro)
        coro.close()
        return task

    monkeypatch.setattr(module.asyncio, "create_task", create_task)
    await module.OrderRetryService.start()
    await module.OrderRetryService.start()
    assert module.OrderRetryService._task is task
    assert module.OrderRetryService._offer_task is task
    await module.OrderRetryService.stop()
    # Two loops now run: the slow retry sweep and the fast offer-expiry sweep.
    assert task.cancel.call_count == 2
    await module.OrderRetryService.stop()

    original_process = module.OrderRetryService._process_stuck_orders.__func__
    process = AsyncMock(side_effect=[RuntimeError("once"), None])
    monkeypatch.setattr(module.OrderRetryService, "_process_stuck_orders", process)
    monkeypatch.setattr(
        module.asyncio,
        "sleep",
        AsyncMock(side_effect=[None, asyncio.CancelledError()]),
    )
    await module.OrderRetryService._retry_loop()

    monkeypatch.setattr(
        module.OrderRetryService,
        "_process_stuck_orders",
        classmethod(original_process),
    )

    monkeypatch.setattr(module.Order, "find", MagicMock(return_value=QueryResult([])))
    await module.OrderRetryService._process_stuck_orders()

    dispatch = AsyncMock()
    monkeypatch.setattr(module.dispatch_service, "dispatch_order", dispatch)
    now = module.utc_now()
    maxed = SimpleNamespace(id="max", retry_count=module.MAX_RETRY_ATTEMPTS)
    recent = SimpleNamespace(
        id="recent", retry_count=0, last_retry_at=now, pickup_location=Location.from_lat_lng(-17, 31)
    )
    good = SimpleNamespace(
        id="good",
        retry_count=0,
        last_retry_at=None,
        pickup_location=Location.from_lat_lng(-17, 31),
        save=AsyncMock(),
    )
    unresolved = SimpleNamespace(
        id="unresolved",
        retry_count=0,
        last_retry_at=None,
        merchant_id="m",
        pickup_location=Location.from_lat_lng(0, 0),
        save=AsyncMock(),
    )
    monkeypatch.setattr(
        module.Order,
        "find",
        MagicMock(return_value=QueryResult([maxed, recent, good, unresolved])),
    )
    restaurant = SimpleNamespace(name="Cafe", location=Location.from_lat_lng(-17, 31))
    monkeypatch.setattr(catalog_models.Restaurant, "get", AsyncMock(return_value=restaurant))
    await module.OrderRetryService._process_stuck_orders()
    assert dispatch.await_count == 2
    assert good.retry_count == 1
    assert unresolved.pickup_location.coordinates == [31, -17]

    catalog_models.Restaurant.get.side_effect = RuntimeError("db")
    unresolved.retry_count = 0
    unresolved.pickup_location = Location.from_lat_lng(0, 0)
    monkeypatch.setattr(
        module.Order, "find", MagicMock(return_value=QueryResult([unresolved]))
    )
    await module.OrderRetryService._process_stuck_orders()

    monkeypatch.setattr(
        module.Order, "find", MagicMock(side_effect=RuntimeError("query"))
    )
    await module.OrderRetryService._process_stuck_orders()
