from motor.motor_asyncio import AsyncIOMotorClient
from beanie import init_beanie
from app.config import settings

from app.auth.models import User
from app.order.models import Order
from app.dispatch.models import Dispatch
from app.catalog.models import Restaurant
from app.catalog.promotion_models import Promotion
from app.payment.models import Payment
from app.finance.models import DriverEarning
from app.rating.models import Review
from app.chat.models import ChatMessage

# Held so the readiness probe can ping the same connection the app uses,
# instead of opening a second client on every probe.
_client: "AsyncIOMotorClient | None" = None


async def ping_database() -> bool:
    """True when MongoDB answers a ping. Used by GET /ready."""
    client = _client or AsyncIOMotorClient(settings.MONGODB_URL)
    await client.admin.command("ping")
    return True


async def init_db():
    global _client
    client = AsyncIOMotorClient(settings.MONGODB_URL)
    _client = client
    await init_beanie(
        database=client[settings.MONGODB_DB_NAME],
        document_models=[
            User,
            Order,
            Dispatch,
            Restaurant,
            Promotion,
            Payment,
            DriverEarning,
            Review,
            ChatMessage,
        ]
    )
