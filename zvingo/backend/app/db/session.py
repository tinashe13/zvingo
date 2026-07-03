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

async def init_db():
    client = AsyncIOMotorClient(settings.MONGODB_URL)
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
        ]
    )
