from contextlib import asynccontextmanager
import asyncio
from fastapi import FastAPI
from fastapi.middleware.gzip import GZipMiddleware
from app.config import settings
from app.db.session import init_db
import structlog

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

from app.upload import router as upload_router
from fastapi.staticfiles import StaticFiles
import os

# Ensure static directory exists
os.makedirs("static/uploads", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")

app.include_router(upload_router.router, prefix="/upload", tags=["upload"])
