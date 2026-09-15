from contextlib import asynccontextmanager
import asyncio
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException
from app.config import settings
from app.db.session import init_db
from app.observability.logging import configure_logging
from app.observability.middleware import (
    REQUEST_ID_HEADER,
    RequestContextMiddleware,
    SecurityHeadersMiddleware,
)
import structlog

configure_logging()
logger = structlog.get_logger()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Starting up Zvingo Backend...", environment=settings.ENVIRONMENT)
    if settings.PAYMENT_MOCK_MODE:
        logger.warning(
            "PAYMENT_MOCK_MODE is ENABLED — payments are simulated and auto-approve. "
            "Never run production with this flag on."
        )
    if settings.SMS_MOCK_MODE:
        logger.warning(
            "SMS_MOCK_MODE is ENABLED — SMS messages are mocked, not delivered."
        )
    await init_db()

    # Initialize Firebase for push notifications
    from app.notification.fcm import init_firebase
    init_firebase()

    # Start BinProto servers here (Task 1)
    # UDP Server
    from app.binproto.udp_server import start_udp_server
    udp_transport = await start_udp_server()
    logger.info("BinProto UDP Server started")

    # TCP Server (run as background task)
    from app.binproto.tcp_server import start_tcp_server
    tcp_task = asyncio.create_task(start_tcp_server())
    logger.info("BinProto TCP Server started")

    # Start order retry service (re-dispatch stuck orders every 2 minutes)
    from app.dispatch.retry_service import retry_service
    await retry_service.start()
    logger.info("Order retry service started")

    # Release scheduled orders into dispatch as their slot approaches
    from app.dispatch.scheduler_service import scheduled_order_service
    await scheduled_order_service.start()

    # Watch for stuck orders, failed payments, and dispatch exhaustion
    from app.observability.alerts import alert_service
    await alert_service.start()

    # Backfill restaurant locations for existing data
    from app.catalog.maintenance import backfill_restaurant_locations
    await backfill_restaurant_locations(force_all=False)
    logger.info("Restaurant location backfill finished")

    yield

    # Shutdown
    if udp_transport:
        udp_transport.close()
    tcp_task.cancel()
    await retry_service.stop()
    await scheduled_order_service.stop()
    await alert_service.stop()
    try:
        await tcp_task
    except asyncio.CancelledError:
        pass
    logger.info("Shutting down...")

app = FastAPI(
    title=settings.PROJECT_NAME,
    lifespan=lifespan,
    openapi_url=f"{settings.API_V1_STR}/openapi.json"
)

app.add_middleware(GZipMiddleware, minimum_size=1000)
# Security headers sit inside the request-context middleware so that even a
# response produced by an error handler carries them.
app.add_middleware(
    SecurityHeadersMiddleware,
    hsts_max_age=settings.HSTS_MAX_AGE_SECONDS,
    enabled=settings.SECURITY_HEADERS_ENABLED,
)
# Outermost middleware: every request gets a correlation id, latency log,
# and an entry in the HTTP metrics — including ones that error out.
app.add_middleware(RequestContextMiddleware)

from fastapi.middleware.cors import CORSMiddleware

# Origins come from the CORS_ORIGINS setting (comma-separated).
# Defaults to "*" only in development; in production Settings refuses to build
# with a wildcard at all, and the filter below is the second line of defence —
# `allow_origins=["*"]` together with `allow_credentials=True` is a
# cross-site request-forgery primitive, so it must be impossible in production.
_cors_origins = [o for o in settings.cors_origins if not (settings.is_production and o == "*")]
if settings.is_production and "*" in settings.cors_origins:
    raise RuntimeError(
        "CORS_ORIGINS must not be '*' in production — set it to the exact "
        "browser origins that may call this API."
    )
if not _cors_origins:
    logger.warning(
        "CORS_ORIGINS is empty — browser clients will be blocked. "
        "Set CORS_ORIGINS to a comma-separated list of allowed origins."
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=[REQUEST_ID_HEADER],
)


def _request_id(request: Request) -> str:
    return getattr(request.state, "request_id", "") or request.headers.get(
        REQUEST_ID_HEADER, ""
    )


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException):
    """Pass deliberate HTTP errors through, with the correlation id attached."""
    headers = dict(getattr(exc, "headers", None) or {})
    request_id = _request_id(request)
    if request_id:
        headers[REQUEST_ID_HEADER] = request_id
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "request_id": request_id},
        headers=headers,
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """422 without echoing the rejected payload.

    FastAPI's default handler includes the offending `input` value, which for
    a login or password-reset body means the credential lands in the response
    and in any client-side error log that captures it.
    """
    errors = [
        {
            "loc": error.get("loc", []),
            "msg": error.get("msg", "Invalid value"),
            "type": error.get("type", "value_error"),
        }
        for error in exc.errors()
    ]
    return JSONResponse(
        status_code=422,
        content={"detail": errors, "request_id": _request_id(request)},
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Never leak an internal failure to the caller.

    The traceback, the exception type and the route go to the structured log
    (where the request id ties them to the client's report); the client gets a
    generic message and that id. A stack trace in an HTTP response is a map of
    the codebase, the dependency versions and often the file system layout.
    """
    request_id = _request_id(request)
    logger.exception(
        "unhandled_exception",
        path=request.url.path,
        method=request.method,
        request_id=request_id,
        error_type=type(exc).__name__,
    )
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "request_id": request_id,
        },
        headers={REQUEST_ID_HEADER: request_id} if request_id else None,
    )


@app.get("/health")
async def health_check():
    """Liveness probe. Deliberately dependency-free and detail-free.

    Readiness (is MongoDB/Redis reachable?) is a separate probe at GET /ready
    so a dead dependency removes the pod from rotation without also killing it.
    """
    return {"status": "ok"}

from app.observability import router as observability_router
app.include_router(observability_router.router, tags=["observability"])

# Include routers
from app.auth import router as auth_router
app.include_router(auth_router.router, prefix="/auth", tags=["auth"])

from app.order import router as order_router
app.include_router(order_router.router, prefix="/orders", tags=["orders"])

from app.dispatch import router as dispatch_router
app.include_router(dispatch_router.router, prefix="/dispatch", tags=["dispatch"])

from app.dispatch import ws_router as dispatch_ws_router
app.include_router(dispatch_ws_router.router, tags=["dispatch-ws"])

from app.sms import router as sms_router
app.include_router(sms_router.router, prefix="/sms", tags=["sms"])

from app.sync import router as sync_router
app.include_router(sync_router.router, prefix="/sync", tags=["sync"])

from app.finance import router as finance_router
app.include_router(finance_router.router, prefix="/finance", tags=["finance"])

from app.catalog import router as catalog_router
app.include_router(catalog_router.router, prefix="/catalog", tags=["catalog"])

from app.notification import router as notification_router
app.include_router(notification_router.router, prefix="/notification", tags=["notification"])

from app.payment import router as payment_router
app.include_router(payment_router.router, prefix="/payment", tags=["payment"])

from app.location import router as location_router
app.include_router(location_router.router, prefix="/location", tags=["location"])

from app.driver import router as driver_router
app.include_router(driver_router.router, prefix="/driver", tags=["driver"])

from app.rating import router as rating_router
app.include_router(rating_router.router, prefix="/rating", tags=["rating"])

from app.chat import router as chat_router
app.include_router(chat_router.router, prefix="/chat", tags=["chat"])

from app.tracking import ws_router as tracking_ws_router
app.include_router(tracking_ws_router.router, tags=["tracking-ws"])

from app.admin import router as admin_router
app.include_router(admin_router.router, prefix="/admin", tags=["admin"])

from app.upload import router as upload_router
from fastapi.staticfiles import StaticFiles
import os

# Ensure static directory exists
os.makedirs("static/uploads", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")

app.include_router(upload_router.router, prefix="/upload", tags=["upload"])
