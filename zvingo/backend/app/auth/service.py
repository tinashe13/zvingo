from datetime import datetime, timedelta
from app.time_utils import utc_now
from typing import Optional, Union
from jose import jwt
import bcrypt
from app.config import settings
from app.auth.schemas import UserCreate
from app.auth.models import User
import secrets
import structlog

logger = structlog.get_logger()


class AuthService:
    @staticmethod
    def verify_password(plain_password: str, hashed_password: str) -> bool:
        return bcrypt.checkpw(
            plain_password.encode('utf-8'),
            hashed_password.encode('utf-8')
        )

    @staticmethod
    def get_password_hash(password: str) -> str:
        salt = bcrypt.gensalt()
        return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')


    @staticmethod
    def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
        to_encode = data.copy()
        if expires_delta:
            expire = utc_now() + expires_delta
        else:
            expire = utc_now() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        to_encode.update({"exp": expire})
        encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
        return encoded_jwt

    @staticmethod
    async def create_user(user_in: UserCreate) -> User:
        user = User(
            email=user_in.email,
            phone=user_in.phone,
            hashed_password=AuthService.get_password_hash(user_in.password),
            full_name=user_in.full_name,
            role=user_in.role
        )
        await user.insert()
        return user

    @staticmethod
    async def authenticate_user(login_identifier: str, password: str) -> Optional[User]:
        # Try finding by email first, then phone
        user = await User.find_one(User.email == login_identifier)
        if not user:
            user = await User.find_one(User.phone == login_identifier)
            
        if not user:
            return None
        if not AuthService.verify_password(password, user.hashed_password):
            return None
        return user

    @staticmethod
    async def create_otp(phone: str) -> str:
        import redis.asyncio as aioredis
        otp = "".join([str(secrets.randbelow(10)) for _ in range(6)])
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        try:
            await r.setex(f"otp:{phone}", 300, otp)  # 5 minute TTL
            logger.info("OTP stored", phone=phone)
        finally:
            await r.close()
        return otp

    @staticmethod
    async def verify_otp(phone: str, code: str) -> bool:
        import redis.asyncio as aioredis
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        try:
            stored = await r.get(f"otp:{phone}")
            if stored and stored == code:
                await r.delete(f"otp:{phone}")
                return True
            return False
        finally:
            await r.close()

    @staticmethod
    async def create_password_reset_token(phone: str) -> str:
        import redis.asyncio as aioredis
        token = secrets.token_urlsafe(32)
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        try:
            await r.setex(f"reset:{token}", 1800, phone)  # 30 minute TTL
            return token
        finally:
            await r.close()

    @staticmethod
    async def verify_reset_token(token: str) -> Optional[str]:
        import redis.asyncio as aioredis
        r = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        try:
            phone = await r.get(f"reset:{token}")
            if phone:
                await r.delete(f"reset:{token}")
            return phone
        finally:
            await r.close()
