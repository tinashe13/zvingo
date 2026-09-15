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


# Response headers applied to every request. Values that never vary live here
# so the middleware does no per-request string building.
BASE_SECURITY_HEADERS = {
    # Never let a browser second-guess a declared content type. This is what
    # stops an uploaded image from being re-interpreted as HTML or script.
    "X-Content-Type-Options": "nosniff",
    # This API has no UI worth framing, and framing it only enables clickjacking.
    "X-Frame-Options": "DENY",
    # Paths and ids live in our URLs; do not leak them to third parties.
    "Referrer-Policy": "no-referrer",
    # No API response needs a camera, a microphone or a location fix.
    "Permissions-Policy": "geolocation=(), microphone=(), camera=(), payment=()",
    # Belt to CORS' braces for scripted cross-origin reads.
    "Cross-Origin-Opener-Policy": "same-origin",
}

# JSON APIs load nothing, so the safest possible policy is also the correct
# one: no default source at all, and nothing may frame or re-base the page.
API_CSP = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"

# /static serves user-uploaded images. `sandbox` strips script execution and
# same-origin privileges even if something non-image ever slipped past the
# upload validator, which makes stored XSS unexploitable rather than merely
# unlikely.
STATIC_CSP = (
    "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; "
    "frame-ancestors 'none'; base-uri 'none'; sandbox"
)

# Swagger UI / ReDoc pull their bundle from jsDelivr.
DOCS_CSP = (
    "default-src 'none'; script-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; "
    "style-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; "
    "img-src 'self' data: https://fastapi.tiangolo.com; font-src 'self' https://cdn.jsdelivr.net; "
    "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"
)

DOCS_PATHS = ("/docs", "/redoc")


def csp_for(path: str) -> str:
    """The Content-Security-Policy appropriate to this path."""
    if path.startswith("/static"):
        return STATIC_CSP
    if path.startswith(DOCS_PATHS):
        return DOCS_CSP
    return API_CSP


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Attach the standard security headers to every response.

    HSTS is only sent when the request arrived over TLS (directly or via the
    ``X-Forwarded-Proto`` header nginx sets). Sending it over plaintext is
    ignored by browsers anyway, and sending it in local development would pin
    ``http://localhost`` to HTTPS in the developer's browser for a year.
    """

    def __init__(self, app, hsts_max_age: int = 31536000, enabled: bool = True):
        super().__init__(app)
        self.hsts_value = f"max-age={hsts_max_age}; includeSubDomains"
        self.enabled = enabled

    @staticmethod
    def _is_secure(request: Request) -> bool:
        forwarded = request.headers.get("x-forwarded-proto", "")
        if forwarded:
            return forwarded.split(",")[0].strip().lower() == "https"
        return request.url.scheme == "https"

    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        if not self.enabled:
            return response
        for header, value in BASE_SECURITY_HEADERS.items():
            response.headers.setdefault(header, value)
        response.headers.setdefault("Content-Security-Policy", csp_for(request.url.path))
        if request.url.path.startswith("/static"):
            # Mobile apps and the merchant dashboard load these images from a
            # different origin, so CORP must stay permissive here.
            response.headers.setdefault("Cross-Origin-Resource-Policy", "cross-origin")
        else:
            response.headers.setdefault("Cross-Origin-Resource-Policy", "same-origin")
        if self._is_secure(request):
            response.headers.setdefault("Strict-Transport-Security", self.hsts_value)
        return response
