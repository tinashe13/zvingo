"""Credential handling: passwords, OTPs, password-reset tokens, JWTs.

Two rules shape everything here:

1. **Nothing that can be replayed is stored in the clear.** OTPs and
   password-reset tokens are kept as SHA-256 digests, so a Redis snapshot —
   or a leaked ``KEYS``/``GET`` — yields nothing usable. Comparison is
   constant-time.
2. **Every one-shot credential is genuinely one-shot.** An OTP or reset token
   is deleted the moment it is accepted, and burned after a small number of
   wrong guesses, so a six-digit code cannot be walked.
"""

from datetime import timedelta
from typing import Optional
import hashlib
import json
import secrets

import bcrypt
import structlog

from app.auth.models import User
from app.auth.schemas import UserCreate
from app.auth import tokens as token_service
from app.config import settings
from app.db.redis import redis_client
from app.time_utils import epoch_seconds

logger = structlog.get_logger()

OTP_KEY_PREFIX = "otp:"
RESET_KEY_PREFIX = "auth:reset:"


def _digest(value: str, *, salt: str = "") -> str:
    """SHA-256 of a one-shot credential.

    A plain digest is right here (unlike for passwords): the inputs are
    high-entropy and short-lived, so the slow-hash argument does not apply,
    while the fast path matters because these are checked on every attempt.
    """
    return hashlib.sha256(f"{salt}:{value}".encode("utf-8")).hexdigest()


class AuthService:
    @staticmethod
    def verify_password(plain_password: str, hashed_password: str) -> bool:
        try:
            return bcrypt.checkpw(
                plain_password.encode('utf-8'),
                hashed_password.encode('utf-8')
            )
        except (ValueError, TypeError):
            # A malformed stored hash must read as "wrong password", never as
            # a 500 that tells the caller this account is special.
            return False

    @staticmethod
    def get_password_hash(password: str) -> str:
        salt = bcrypt.gensalt()
        return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

    @staticmethod
    def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
        """Mint an access token. See :mod:`app.auth.tokens` for the claim set."""
        return token_service.create_access_token(data, expires_delta)

    @staticmethod
    async def issue_token_pair(user: User) -> dict:
        """Access + refresh pair for a freshly authenticated user.

        The refresh token's id is recorded in Redis; it is consumed on first
        use (rotation) and can be revoked without waiting for expiry.
        """
        user_id = str(user.id)
        access_token = token_service.create_access_token(
            {"sub": user_id}, role=getattr(user, "role", None)
        )
        refresh_token, jti, ttl = token_service.create_refresh_token(
            user_id, role=getattr(user, "role", None)
        )
        try:
            await token_service.remember_refresh_token(user_id, jti, ttl)
        except Exception as exc:
            # Without the registry entry the refresh token cannot be honoured,
            # so hand back an access-only session rather than a token that
            # will mysteriously fail later.
            logger.error("refresh_token_registry_unavailable", user_id=user_id, error=str(exc))
            return {
                "access_token": access_token,
                "token_type": "bearer",
                "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            }
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "refresh_token": refresh_token,
            "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        }

    @staticmethod
    async def create_user(user_in: UserCreate) -> User:
        user = User(
            email=user_in.email,
            phone=user_in.phone,
            hashed_password=AuthService.get_password_hash(user_in.password),
            full_name=user_in.full_name,
            role=user_in.role,
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

    # --- OTP ------------------------------------------------------------------

    @staticmethod
    async def create_otp(phone: str) -> str:
        """Generate, store (hashed) and return a one-time code.

        The stored record carries its own expiry and attempt counter so a
        wrong guess can be recorded without extending the code's life.
        """
        otp = "".join([str(secrets.randbelow(10)) for _ in range(6)])
        record = json.dumps(
            {
                "hash": _digest(otp, salt=phone),
                "exp": epoch_seconds() + settings.OTP_TTL_SECONDS,
                "attempts": 0,
            }
        )
        async with redis_client() as r:
            await r.setex(f"{OTP_KEY_PREFIX}{phone}", settings.OTP_TTL_SECONDS, record)
        logger.info("otp_issued", phone=phone)  # never log the code itself
        return otp

    @staticmethod
    async def verify_otp(phone: str, code: str) -> bool:
        """Check a code. Consumes it on success; burns it after too many misses."""
        key = f"{OTP_KEY_PREFIX}{phone}"
        async with redis_client() as r:
            raw = await r.get(key)
            if not raw:
                return False

            try:
                record = json.loads(raw)
                stored_hash = record["hash"]
                expires_at = int(record["exp"])
                attempts = int(record.get("attempts", 0))
            except (ValueError, TypeError, KeyError):
                await r.delete(key)
                return False

            now = epoch_seconds()
            if now >= expires_at:
                await r.delete(key)
                return False

            if secrets.compare_digest(stored_hash, _digest(code, salt=phone)):
                await r.delete(key)  # single use
                return True

            attempts += 1
            if attempts >= settings.OTP_MAX_ATTEMPTS:
                await r.delete(key)
                logger.warning("otp_burned_after_failed_attempts", phone=phone, attempts=attempts)
                return False

            record["attempts"] = attempts
            # Re-store with the *remaining* lifetime so guessing cannot keep
            # the code alive.
            await r.setex(key, max(1, expires_at - now), json.dumps(record))
            return False

    # --- Password reset -------------------------------------------------------

    @staticmethod
    async def create_password_reset_token(phone: str) -> str:
        """Issue a reset token. Only its digest is stored.

        The returned value must be delivered out-of-band (SMS) and never
        echoed in an HTTP response — anything that can read the response can
        already reset the account.
        """
        token = secrets.token_urlsafe(32)
        async with redis_client() as r:
            await r.setex(
                f"{RESET_KEY_PREFIX}{_digest(token)}",
                settings.PASSWORD_RESET_TTL_SECONDS,
                phone,
            )
        logger.info("password_reset_token_issued", phone=phone)
        return token

    @staticmethod
    async def verify_reset_token(token: str) -> Optional[str]:
        """Consume a reset token and return the phone it belongs to, or None."""
        if not token:
            return None
        key = f"{RESET_KEY_PREFIX}{_digest(token)}"
        async with redis_client() as r:
            phone = await r.get(key)
            if phone:
                await r.delete(key)  # single use
            return phone
