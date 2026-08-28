from contextlib import asynccontextmanager
import asyncio
from fastapi import FastAPI
from fastapi.middleware.gzip import GZipMiddleware
from app.config import settings
from app.db.session import init_db
from app.observability.logging import configure_logging
from app.observability.middleware import RequestContextMiddleware
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
# Outermost middleware: every request gets a correlation id, latency log,
# and an entry in the HTTP metrics — including ones that error out.
app.add_middleware(RequestContextMiddleware)

from fastapi.middleware.cors import CORSMiddleware

# Origins come from the CORS_ORIGINS setting (comma-separated).
# Defaults to "*" only in development; in production an explicit list is required.
_cors_origins = settings.cors_origins
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
)

@app.get("/health")
async def health_check():
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
