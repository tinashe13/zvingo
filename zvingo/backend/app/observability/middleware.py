"""Request-scoped tracing: correlation IDs, latency logging, HTTP metrics."""

import time
import uuid

import structlog
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.observability import metrics

logger = structlog.get_logger()

REQUEST_ID_HEADER = "X-Request-ID"
RESPONSE_TIME_HEADER = "X-Response-Time-Ms"

# Paths that would otherwise flood the logs with no diagnostic value.
QUIET_PATHS = {"/health", "/metrics"}


def new_request_id() -> str:
    return uuid.uuid4().hex


def route_template(request: Request) -> str:
    """The matched route's path template, or a low-cardinality placeholder.

    Using the template (``/orders/{order_id}``) instead of the concrete path
    keeps the metric label set bounded no matter how many orders exist.
    """
    route = request.scope.get("route")
    path = getattr(route, "path", None)
    if path:
        return path
    return "unmatched"


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Bind a request ID to the log context and record timing for every call.

    The incoming ``X-Request-ID`` is honoured when present so a trace survives
    across the nginx front end and the mobile clients; otherwise a new one is
    minted. The id is echoed back on the response for client-side correlation.
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        request_id = request.headers.get(REQUEST_ID_HEADER) or new_request_id()
        request.state.request_id = request_id

        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(
            request_id=request_id,
            method=request.method,
            path=request.url.path,
        )

        metrics.http_requests_in_flight.inc()
        started = time.perf_counter()
        try:
            response = await call_next(request)

            duration = time.perf_counter() - started
            route = route_template(request)
            metrics.http_request_duration_seconds.observe(
                duration, method=request.method, route=route
            )
            metrics.http_requests_total.inc(
                method=request.method, route=route, status=str(response.status_code)
            )

            response.headers[REQUEST_ID_HEADER] = request_id
            response.headers[RESPONSE_TIME_HEADER] = f"{duration * 1000:.2f}"

            if request.url.path not in QUIET_PATHS:
                logger.info(
                    "request_completed",
                    route=route,
                    status_code=response.status_code,
                    duration_ms=round(duration * 1000, 2),
                )
            return response
        except Exception as exc:
            duration = time.perf_counter() - started
            route = route_template(request)
            metrics.http_exceptions_total.inc(route=route)
            metrics.http_request_duration_seconds.observe(
                duration, method=request.method, route=route
            )
            metrics.http_requests_total.inc(
                method=request.method, route=route, status="500"
            )
            logger.error(
                "request_failed",
                route=route,
                duration_ms=round(duration * 1000, 2),
                error=str(exc),
                error_type=type(exc).__name__,
            )
            raise
        finally:
            metrics.http_requests_in_flight.dec()
            structlog.contextvars.clear_contextvars()
