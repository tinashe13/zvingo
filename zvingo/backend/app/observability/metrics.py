"""A tiny, dependency-free Prometheus-compatible metrics registry.

The backend only needs counters, gauges, and histograms exposed over a text
endpoint, so the exposition format is implemented directly rather than pulling
in `prometheus_client`. Metric objects are process-local; a multi-worker
deployment should scrape each worker (or run one worker per container, as the
shipped compose stack does).
"""

from __future__ import annotations

import threading
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

# Buckets tuned for HTTP latency in seconds.
DEFAULT_BUCKETS: Tuple[float, ...] = (
    0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
)

LabelKey = Tuple[str, ...]


def _escape(value: str) -> str:
    """Escape a label value per the Prometheus text exposition format."""
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def _format_labels(names: Sequence[str], values: LabelKey, extra: str = "") -> str:
    parts = [f'{name}="{_escape(value)}"' for name, value in zip(names, values)]
    if extra:
        parts.append(extra)
    return "{" + ",".join(parts) + "}" if parts else ""


def _format_number(value: float) -> str:
    """Render a sample value, keeping whole numbers integral for readability."""
    if value == int(value):
        return str(int(value))
    return repr(value)


class _Metric:
    def __init__(self, name: str, documentation: str, labelnames: Sequence[str] = ()):
        self.name = name
        self.documentation = documentation
        self.labelnames = tuple(labelnames)
        self._lock = threading.Lock()

    def _key(self, labels: Dict[str, str]) -> LabelKey:
        missing = set(self.labelnames) - set(labels)
        if missing:
            raise ValueError(
                f"{self.name} requires labels {sorted(self.labelnames)}, "
                f"missing {sorted(missing)}"
            )
        return tuple(str(labels[name]) for name in self.labelnames)

    def _header(self, metric_type: str) -> List[str]:
        return [
            f"# HELP {self.name} {self.documentation}",
            f"# TYPE {self.name} {metric_type}",
        ]

    def render(self) -> List[str]:
        raise NotImplementedError


class _SampleMetric(_Metric):
    """Shared rendering for single-sample metrics (counter / gauge)."""

    metric_type = "untyped"

    def __init__(self, name: str, documentation: str, labelnames: Sequence[str] = ()):
        super().__init__(name, documentation, labelnames)
        self._values: Dict[LabelKey, float] = {}

    def value(self, **labels: str) -> float:
        return self._values.get(self._key(labels), 0.0)

    def render(self) -> List[str]:
        lines = self._header(self.metric_type)
        if not self._values and not self.labelnames:
            # An unlabelled metric should still expose a zero sample.
            lines.append(f"{self.name} 0")
        for key, value in sorted(self._values.items()):
            labels = _format_labels(self.labelnames, key)
            lines.append(f"{self.name}{labels} {_format_number(value)}")
        return lines


class Counter(_SampleMetric):
    """A monotonically increasing counter."""

    metric_type = "counter"

    def inc(self, amount: float = 1.0, **labels: str) -> None:
        key = self._key(labels)
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) + amount


class Gauge(_SampleMetric):
    """A value that can go up or down."""

    metric_type = "gauge"

    def set(self, value: float, **labels: str) -> None:
        key = self._key(labels)
        with self._lock:
            self._values[key] = float(value)

    def inc(self, amount: float = 1.0, **labels: str) -> None:
        key = self._key(labels)
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) + amount

    def dec(self, amount: float = 1.0, **labels: str) -> None:
        self.inc(-amount, **labels)


class Histogram(_Metric):
    """Cumulative buckets plus sum/count, as Prometheus expects."""

    def __init__(
        self,
        name: str,
        documentation: str,
        labelnames: Sequence[str] = (),
        buckets: Sequence[float] = DEFAULT_BUCKETS,
    ):
        super().__init__(name, documentation, labelnames)
        self.buckets = tuple(buckets)
        self._counts: Dict[LabelKey, List[int]] = {}
        self._sums: Dict[LabelKey, float] = {}

    def observe(self, value: float, **labels: str) -> None:
        key = self._key(labels)
        with self._lock:
            counts = self._counts.setdefault(key, [0] * (len(self.buckets) + 1))
            self._sums[key] = self._sums.get(key, 0.0) + value
            # Per-bucket tallies stay exclusive; render() accumulates them.
            for index, bound in enumerate(self.buckets):
                if value <= bound:
                    counts[index] += 1
                    break
            counts[-1] += 1  # the +Inf bucket doubles as the total count

    def count(self, **labels: str) -> int:
        counts = self._counts.get(self._key(labels))
        return counts[-1] if counts else 0

    def render(self) -> List[str]:
        lines = self._header("histogram")
        for key, counts in sorted(self._counts.items()):
            cumulative = 0
            for index, bound in enumerate(self.buckets):
                cumulative += counts[index]
                bucket_labels = _format_labels(self.labelnames, key, f'le="{bound}"')
                lines.append(f"{self.name}_bucket{bucket_labels} {cumulative}")
            total = counts[-1]
            inf_labels = _format_labels(self.labelnames, key, 'le="+Inf"')
            lines.append(f"{self.name}_bucket{inf_labels} {total}")
            base = _format_labels(self.labelnames, key)
            lines.append(f"{self.name}_sum{base} {_format_number(self._sums[key])}")
            lines.append(f"{self.name}_count{base} {total}")
        return lines


class Registry:
    """Holds every metric and renders the exposition payload."""

    def __init__(self) -> None:
        self._metrics: Dict[str, _Metric] = {}

    def register(self, metric: _Metric) -> _Metric:
        self._metrics[metric.name] = metric
        return metric

    def get(self, name: str) -> Optional[_Metric]:
        return self._metrics.get(name)

    def metrics(self) -> Iterable[_Metric]:
        return list(self._metrics.values())

    def render(self) -> str:
        lines: List[str] = []
        for metric in self._metrics.values():
            lines.extend(metric.render())
        return "\n".join(lines) + "\n"


REGISTRY = Registry()

# ── HTTP ────────────────────────────────────────────────────────────
http_requests_total: Counter = REGISTRY.register(
    Counter(
        "zvingo_http_requests_total",
        "HTTP requests handled, by method, route template, and status code.",
        ("method", "route", "status"),
    )
)
http_request_duration_seconds: Histogram = REGISTRY.register(
    Histogram(
        "zvingo_http_request_duration_seconds",
        "HTTP request latency in seconds.",
        ("method", "route"),
    )
)
http_requests_in_flight: Gauge = REGISTRY.register(
    Gauge(
        "zvingo_http_requests_in_flight",
        "HTTP requests currently being served.",
    )
)
http_exceptions_total: Counter = REGISTRY.register(
    Counter(
        "zvingo_http_exceptions_total",
        "Unhandled exceptions raised while serving a request.",
        ("route",),
    )
)

# ── Domain ──────────────────────────────────────────────────────────
orders_total: Counter = REGISTRY.register(
    Counter(
        "zvingo_orders_total",
        "Orders created, by kind (delivery / pickup / scheduled).",
        ("kind",),
    )
)
order_transitions_total: Counter = REGISTRY.register(
    Counter(
        "zvingo_order_transitions_total",
        "Order state transitions, by resulting state.",
        ("state",),
    )
)
dispatch_offers_total: Counter = REGISTRY.register(
    Counter(
        "zvingo_dispatch_offers_total",
        "Delivery offers sent to drivers.",
    )
)
dispatch_no_driver_total: Counter = REGISTRY.register(
    Counter(
        "zvingo_dispatch_no_driver_total",
        "Dispatch attempts that found no available driver.",
    )
)
dispatch_retry_exhausted_total: Counter = REGISTRY.register(
    Counter(
        "zvingo_dispatch_retry_exhausted_total",
        "Orders that exhausted their dispatch retry budget.",
    )
)
payments_total: Counter = REGISTRY.register(
    Counter(
        "zvingo_payments_total",
        "Payment outcomes, by terminal status.",
        ("status",),
    )
)
alerts_total: Counter = REGISTRY.register(
    Counter(
        "zvingo_alerts_total",
        "Operational alerts raised, by kind.",
        ("kind",),
    )
)


def render() -> str:
    """Render the full registry in Prometheus text exposition format."""
    return REGISTRY.render()
