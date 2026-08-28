"""Tests for the observability stack: metrics, logging, tracing, alerting."""

import asyncio
import logging
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.observability import metrics
from app.observability.metrics import (
    Counter,
    Gauge,
    Histogram,
    Registry,
    _escape,
    _format_number,
    render,
)


class Query:
    def __init__(self, values=None, count=None):
        self.values = list(values or [])
        self.count_value = len(self.values) if count is None else count

    def sort(self, *args):
        return self

    def skip(self, *args):
        return self

    def limit(self, *args):
        return self

    async def to_list(self):
        return self.values

    async def count(self):
        return self.count_value


# ── metrics primitives ──────────────────────────────────────────────


def test_counter_accumulates_and_renders():
    counter = Counter("test_counter", "A counter.", ("route",))
    counter.inc(route="/a")
    counter.inc(2, route="/a")
    counter.inc(route="/b")

    assert counter.value(route="/a") == 3
    assert counter.value(route="/missing") == 0
    lines = counter.render()
    assert "# TYPE test_counter counter" in lines
    assert 'test_counter{route="/a"} 3' in lines
    assert 'test_counter{route="/b"} 1' in lines


def test_unlabelled_counter_renders_a_zero_sample():
    counter = Counter("bare_counter", "No labels.")
    assert counter.render()[-1] == "bare_counter 0"
    counter.inc()
    assert counter.render()[-1] == "bare_counter 1"


def test_counter_rejects_missing_labels():
    counter = Counter("strict_counter", "Needs labels.", ("route", "method"))
    with pytest.raises(ValueError) as exc:
        counter.inc(route="/a")
    assert "method" in str(exc.value)


def test_gauge_set_inc_and_dec():
    gauge = Gauge("test_gauge", "A gauge.")
    gauge.set(5)
    gauge.inc()
    gauge.dec(2)
    assert gauge.value() == 4
    assert "# TYPE test_gauge gauge" in gauge.render()


def test_histogram_buckets_are_cumulative():
    histogram = Histogram(
        "test_histogram", "A histogram.", ("route",), buckets=(0.1, 1.0)
    )
    histogram.observe(0.05, route="/a")
    histogram.observe(0.5, route="/a")
    histogram.observe(5.0, route="/a")

    assert histogram.count(route="/a") == 3
    assert histogram.count(route="/none") == 0

    lines = histogram.render()
    assert 'test_histogram_bucket{route="/a",le="0.1"} 1' in lines
    assert 'test_histogram_bucket{route="/a",le="1.0"} 2' in lines
    assert 'test_histogram_bucket{route="/a",le="+Inf"} 3' in lines
    assert 'test_histogram_count{route="/a"} 3' in lines
    assert 'test_histogram_sum{route="/a"} 5.55' in lines


def test_empty_histogram_renders_header_only():
    assert Histogram("empty_histogram", "Nothing observed.").render() == [
        "# HELP empty_histogram Nothing observed.",
        "# TYPE empty_histogram histogram",
    ]


def test_label_escaping_and_number_formatting():
    assert _escape('a"b\\c\nd') == 'a\\"b\\\\c\\nd'
    assert _format_number(3.0) == "3"
    assert _format_number(3.5) == "3.5"


def test_registry_registers_gets_and_renders():
    registry = Registry()
    counter = registry.register(Counter("registry_counter", "Counter."))
    assert registry.get("registry_counter") is counter
    assert registry.get("nope") is None
    assert list(registry.metrics()) == [counter]
    assert registry.render().endswith("\n")


def test_base_metric_render_is_abstract():
    from app.observability.metrics import _Metric

    with pytest.raises(NotImplementedError):
        _Metric("abstract", "doc").render()


def test_module_render_includes_registered_metrics():
    metrics.orders_total.inc(kind="delivery")
    output = render()
    assert "zvingo_orders_total" in output
    assert "zvingo_http_requests_in_flight" in output


# ── logging ─────────────────────────────────────────────────────────


def test_logging_configuration_switches_renderer(monkeypatch):
    import app.observability.logging as module

    monkeypatch.setattr(module.settings, "ENVIRONMENT", "production")
    assert module.use_json_logs() is True
    module.configure_logging()

    monkeypatch.setattr(module.settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(module.settings, "LOG_JSON", False)
    assert module.use_json_logs() is False
    module.configure_logging()

    assert logging.getLogger("uvicorn.access").propagate is True


def test_logging_falls_back_to_info_for_a_bad_level(monkeypatch):
    import app.observability.logging as module

    monkeypatch.setattr(module.settings, "LOG_LEVEL", "not-a-level")
    module.configure_logging()
    assert logging.getLogger().level == logging.INFO
    monkeypatch.setattr(module.settings, "LOG_LEVEL", "INFO")
    module.configure_logging()


# ── request middleware ──────────────────────────────────────────────


def _traced_app():
    from app.observability.middleware import RequestContextMiddleware

    app = FastAPI()
    app.add_middleware(RequestContextMiddleware)

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    @app.get("/items/{item_id}")
    async def item(item_id: str):
        return {"item_id": item_id}

    @app.get("/boom")
    async def boom():
        raise RuntimeError("kaboom")

    return app


@pytest.mark.asyncio
async def test_middleware_tags_responses_and_records_metrics():
    from app.observability.middleware import (
        REQUEST_ID_HEADER,
        RESPONSE_TIME_HEADER,
    )

    before = metrics.http_requests_total.value(
        method="GET", route="/items/{item_id}", status="200"
    )

    async with AsyncClient(
        transport=ASGITransport(app=_traced_app()), base_url="http://test"
    ) as client:
        response = await client.get("/items/42")
        assert response.status_code == 200
        assert len(response.headers[REQUEST_ID_HEADER]) == 32
        assert float(response.headers[RESPONSE_TIME_HEADER]) >= 0

        # An inbound request id is honoured so traces span the proxy.
        traced = await client.get("/health", headers={REQUEST_ID_HEADER: "trace-1"})
        assert traced.headers[REQUEST_ID_HEADER] == "trace-1"

    assert (
        metrics.http_requests_total.value(
            method="GET", route="/items/{item_id}", status="200"
        )
        == before + 1
    )
    assert (
        metrics.http_request_duration_seconds.count(
            method="GET", route="/items/{item_id}"
        )
        >= 1
    )


@pytest.mark.asyncio
async def test_middleware_records_and_reraises_failures():
    before = metrics.http_exceptions_total.value(route="/boom")

    async with AsyncClient(
        transport=ASGITransport(app=_traced_app()), base_url="http://test"
    ) as client:
        with pytest.raises(RuntimeError):
            await client.get("/boom")

    assert metrics.http_exceptions_total.value(route="/boom") == before + 1
    assert metrics.http_requests_in_flight.value() == 0


def test_route_template_falls_back_when_unmatched():
    from app.observability.middleware import new_request_id, route_template

    unmatched = SimpleNamespace(scope={})
    assert route_template(unmatched) == "unmatched"
    matched = SimpleNamespace(scope={"route": SimpleNamespace(path="/orders/{id}")})
    assert route_template(matched) == "/orders/{id}"
    assert new_request_id() != new_request_id()


# ── /metrics endpoint ───────────────────────────────────────────────


@pytest.mark.asyncio
async def test_metrics_endpoint_guards(monkeypatch):
    import app.observability.router as module

    body = await module.scrape()
    assert b"zvingo_http_requests_total" in body.body

    monkeypatch.setattr(module.settings, "METRICS_TOKEN", "s3cret")
    with pytest.raises(HTTPException) as exc:
        await module.scrape(authorization="Bearer wrong")
    assert exc.value.status_code == 401
    assert (await module.scrape(authorization="Bearer s3cret")).status_code == 200

    monkeypatch.setattr(module.settings, "METRICS_TOKEN", None)
    monkeypatch.setattr(module.settings, "METRICS_ENABLED", False)
    with pytest.raises(HTTPException) as exc:
        await module.scrape()
    assert exc.value.status_code == 404


# ── alerting ────────────────────────────────────────────────────────


@pytest.fixture
def alerts(monkeypatch):
    import app.observability.alerts as module

    module.alert_service.clear()
    redis = SimpleNamespace(publish=AsyncMock(), close=AsyncMock())
    monkeypatch.setattr(module.aioredis, "from_url", lambda *a, **k: redis)
    return module, redis


@pytest.mark.asyncio
async def test_raise_alert_publishes_records_and_dedupes(alerts):
    module, redis = alerts

    first = await module.alert_service.raise_alert(
        "stuck_order", "Order stuck", "stuck_order:o1", order_id="o1"
    )
    assert first["kind"] == "stuck_order"
    assert first["context"] == {"order_id": "o1"}
    redis.publish.assert_awaited_once()

    # Same dedupe key inside the window is suppressed.
    assert (
        await module.alert_service.raise_alert("stuck_order", "again", "stuck_order:o1")
        is None
    )
    assert len(module.alert_service.history()) == 1

    # Newest first, and the limit is honoured.
    await module.alert_service.raise_alert("other", "Another", "other:1")
    assert [a["kind"] for a in module.alert_service.history()] == ["other", "stuck_order"]
    assert len(module.alert_service.history(limit=1)) == 1


@pytest.mark.asyncio
async def test_raise_alert_survives_redis_failure(alerts, monkeypatch):
    module, _ = alerts
    monkeypatch.setattr(
        module.aioredis, "from_url", MagicMock(side_effect=RuntimeError("down"))
    )
    alert = await module.alert_service.raise_alert("kind", "message", "key")
    assert alert is not None


@pytest.mark.asyncio
async def test_stuck_order_check_raises_one_alert_per_order(alerts, monkeypatch):
    module, _ = alerts
    import app.order.models as order_models

    stuck = [
        SimpleNamespace(
            id="order-1",
            state=SimpleNamespace(value="ACCEPTED"),
            merchant_id="restaurant-1",
            driver_id="driver-1",
        ),
        SimpleNamespace(
            id="order-2", state="OFFERED", merchant_id="restaurant-1", driver_id=None
        ),
    ]
    monkeypatch.setattr(order_models.Order, "find", lambda *a, **k: Query(stuck))

    assert await module.alert_service.check_stuck_orders() == 2
    kinds = [a["kind"] for a in module.alert_service.history()]
    assert kinds == ["stuck_order", "stuck_order"]


@pytest.mark.asyncio
async def test_failed_payment_check_only_alerts_above_threshold(alerts, monkeypatch):
    module, _ = alerts
    import app.payment.models as payment_models

    monkeypatch.setattr(module.settings, "ALERT_FAILED_PAYMENT_THRESHOLD", 3)
    monkeypatch.setattr(
        payment_models.Payment, "find", lambda *a, **k: Query([], count=2)
    )
    assert await module.alert_service.check_failed_payments() == 2
    assert module.alert_service.history() == []

    monkeypatch.setattr(
        payment_models.Payment, "find", lambda *a, **k: Query([], count=7)
    )
    assert await module.alert_service.check_failed_payments() == 7
    assert module.alert_service.history()[0]["context"]["failed_count"] == 7


@pytest.mark.asyncio
async def test_dispatch_exhaustion_check(alerts, monkeypatch):
    module, _ = alerts
    import app.order.models as order_models

    exhausted = [SimpleNamespace(id="order-9", retry_count=10, merchant_id="r1")]
    monkeypatch.setattr(order_models.Order, "find", lambda *a, **k: Query(exhausted))
    assert await module.alert_service.check_dispatch_exhaustion() == 1
    assert module.alert_service.history()[0]["kind"] == "dispatch_exhausted"


@pytest.mark.asyncio
async def test_run_checks_isolates_a_failing_check(alerts, monkeypatch):
    module, _ = alerts
    monkeypatch.setattr(
        module.alert_service, "check_stuck_orders", AsyncMock(return_value=1)
    )
    monkeypatch.setattr(
        module.alert_service,
        "check_failed_payments",
        AsyncMock(side_effect=RuntimeError("db down")),
    )
    monkeypatch.setattr(
        module.alert_service, "check_dispatch_exhaustion", AsyncMock(return_value=0)
    )

    results = await module.alert_service.run_checks()
    assert results == {
        "stuck_orders": 1,
        "failed_payments": None,
        "dispatch_exhausted": 0,
    }


@pytest.mark.asyncio
async def test_alert_monitor_lifecycle_and_loop(alerts, monkeypatch):
    module, _ = alerts

    monkeypatch.setattr(module.settings, "ALERTS_ENABLED", False)
    await module.alert_service.start()
    assert module.alert_service._task is None

    monkeypatch.setattr(module.settings, "ALERTS_ENABLED", True)
    monkeypatch.setattr(module.settings, "ALERT_POLL_INTERVAL_SECONDS", 0)
    ran = asyncio.Event()

    async def run_checks():
        ran.set()
        return {}

    monkeypatch.setattr(module.alert_service, "run_checks", run_checks)
    await module.alert_service.start()
    await module.alert_service.start()  # already running — no second task
    await asyncio.wait_for(ran.wait(), 1)
    await module.alert_service.stop()
    await module.alert_service.stop()  # idempotent


@pytest.mark.asyncio
async def test_alert_loop_continues_after_an_error(monkeypatch):
    import app.observability.alerts as module

    service = module.AlertService()
    monkeypatch.setattr(module.settings, "ALERT_POLL_INTERVAL_SECONDS", 0)
    calls = []
    done = asyncio.Event()

    async def run_checks():
        calls.append(1)
        if len(calls) == 1:
            raise RuntimeError("transient")
        done.set()
        return {}

    monkeypatch.setattr(service, "run_checks", run_checks)
    task = asyncio.create_task(service._loop())
    await asyncio.wait_for(done.wait(), 1)
    task.cancel()
    await asyncio.sleep(0)
    assert len(calls) >= 2
