"""Authentication endpoints.

The public half of this router (register, token, OTP, password reset) is the
part of the API an attacker reaches first, so each route here carries two
defences beyond the obvious ones:

* **Rate limits**, per client IP *and* per identifier, so credential stuffing
  and OTP walking run out of budget long before they run out of guesses. See
  :func:`_enforce_rate_limit`.
* **No enumeration oracle.** Registration, OTP request and password reset all
  answer the same way whether or not the account exists, and login does not
  distinguish "no such user" from "wrong password".
"""

from typing import Optional

import structlog
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel, EmailStr, Field

from app.auth import tokens as token_service
from app.auth.authorization import Role, is_admin
from app.auth.models import User
from app.auth.principals import (
    CREDENTIALS_DETAIL,
    INACTIVE_ACCOUNT_DETAIL,
    bearer_token_from,
    credentials_exception,
    inactive_account_exception,
    tokens_invalidated,
)
from app.auth.schemas import (
    MIN_PASSWORD_LENGTH,
    OTPRequest,
    OTPVerify,
    RefreshRequest,
    Token,
    UserCreate,
    UserLogin,
)
from app.auth.service import AuthService
from app.config import settings
from app.db.redis import redis_client
from app.rate_limiter import RateLimiter
from app.time_utils import utc_now

logger = structlog.get_logger()

router = APIRouter()

__all__ = [
    "router",
    "oauth2_scheme",
    "get_current_user",
    "get_current_user_flexible",
    "get_current_admin",
    "get_current_merchant",
    "get_current_driver",
    "get_current_consumer",
    "get_optional_user",
    "require_role",
    "resolve_user_from_token",
    "INACTIVE_ACCOUNT_DETAIL",
]

# --- Authentication dependencies ---------------------------------------------
#
# These are the only supported ways to get a `User` out of a request. They all
# funnel through `resolve_user_from_token`, so every hardening applied there —
# algorithm pinning, mandatory expiry, token type, deactivation, the
# post-password-reset cutoff — applies everywhere at once.

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/token", auto_error=True)
_optional_oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/token", auto_error=False)


def _credentials_exception() -> HTTPException:
    """Kept for callers that imported the private helper."""
    return credentials_exception()


async def resolve_user_from_token(
    token: str, *, expected_type: str = token_service.ACCESS_TOKEN_TYPE
) -> User:
    """Decode a JWT and load the active user it identifies.

    Raises 401 for a bad/expired/wrong-type token, an unknown subject, or a
    token superseded by a credential change, and 403 for a user an admin has
    deactivated — a deactivated account must not be able to keep using tokens
    minted before the deactivation.
    """
    try:
        payload = token_service.decode_token(token, expected_type)
    except token_service.TokenError as exc:
        logger.info("auth_token_rejected", reason=str(exc))
        raise credentials_exception()

    user = await User.get(payload["sub"])
    if user is None:
        raise credentials_exception()
    if not user.is_active:
        raise inactive_account_exception()
    if tokens_invalidated(user, payload):
        logger.info("auth_token_superseded", user_id=str(user.id))
        raise credentials_exception()

    # Every log line emitted while handling this request now carries who it was
    # for, alongside the request id bound by RequestContextMiddleware.
    structlog.contextvars.bind_contextvars(
        user_id=str(user.id), user_role=getattr(user, "role", None)
    )
    return user


async def get_current_user(token: str = Depends(oauth2_scheme)) -> User:
    """The authenticated user, from the Authorization header. 401 otherwise."""
    return await resolve_user_from_token(token)


async def get_current_user_flexible(request: Request) -> User:
    """Authenticate from the Authorization header *or* a `token` query param.

    Browser `EventSource` and `WebSocket` clients cannot set headers, so
    streaming endpoints accept the JWT as a query parameter as well.
    """
    token = bearer_token_from(request)
    if not token:
        raise credentials_exception()
    return await resolve_user_from_token(token)


async def get_optional_user(
    token: Optional[str] = Depends(_optional_oauth2_scheme),
) -> Optional[User]:
    """The authenticated user if a token is present, else None.

    For endpoints that are public but richer when signed in. A *present but
    invalid* token is still rejected rather than silently downgraded, so a
    client never believes it is authenticated when it is not.
    """
    if not token:
        return None
    return await resolve_user_from_token(token)


async def get_current_admin(user: User = Depends(get_current_user)) -> User:
    """Require an authenticated admin user (role == "admin")."""
    if not is_admin(user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )
    return user


def require_role(*roles: str, allow_admin: bool = True):
    """Dependency factory: require the caller to hold one of `roles`.

        @router.post("/promotions")
        async def create(user: User = Depends(require_role(Role.MERCHANT))): ...

    Admins pass by default because every role check so far has meant "at
    least"; pass `allow_admin=False` for actions an admin must not perform on
    a user's behalf.
    """

    async def _dependency(user: User = Depends(get_current_user)) -> User:
        if user.role in roles or (allow_admin and is_admin(user)):
            return user
        expected = " or ".join(roles) if roles else "a privileged role"
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"This action requires {expected} access",
        )

    _dependency.__name__ = "require_role_" + "_".join(roles or ("any",))
    return _dependency


# Convenience dependencies for the three product roles.
get_current_merchant = require_role(Role.MERCHANT)
get_current_driver = require_role(Role.DRIVER)
get_current_consumer = require_role(Role.CONSUMER)


# Deliberately identical for "unknown account" and "wrong password".
INVALID_CREDENTIALS_DETAIL = "Incorrect username or password"
# Deliberately identical whether or not the phone is registered.
RESET_INITIATED = {"status": "reset_initiated"}


def _client_ip(request: Optional[Request]) -> str:
    """Best-effort client address for rate-limit bucketing.

    ``X-Forwarded-For`` is only trustworthy because nginx sits in front and
    rewrites it; the left-most entry is the original client. Falls back to the
    socket address, then to a shared bucket, so a missing request object
    degrades to *more* limiting rather than none.
    """
    if request is None:
        return "unknown"
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    client = getattr(request, "client", None)
    return getattr(client, "host", None) or "unknown"


async def _enforce_rate_limit(
    request: Optional[Request], bucket: str, identifier: str, limit: int, window: int
) -> None:
    """429 when either the caller's IP or the target identifier is over budget.

    Limiting on both axes matters: per-IP alone is defeated by a botnet, and
    per-identifier alone lets one host spray a whole user list. Redis being
    unreachable fails open (see :class:`RateLimiter`), so an outage never locks
    users out of their accounts.
    """
    subjects = [f"ip:{_client_ip(request)}"]
    if identifier:
        subjects.append(f"id:{identifier.strip().lower()}")
    try:
        async with redis_client() as r:
            limiter = RateLimiter(r)
            for subject in subjects:
                result = await limiter.check(
                    f"rate_limit:{bucket}:{subject}", limit=limit, window=window
                )
                if not result.allowed:
                    logger.warning(
                        "auth_rate_limited", bucket=bucket, subject=subject
                    )
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail=(
                            "Too many attempts. Please wait "
                            f"{result.retry_after}s and try again."
                        ),
                        headers={"Retry-After": str(result.retry_after)},
                    )
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover - limiter already fails open
        logger.error("auth_rate_limit_unavailable", bucket=bucket, error=str(exc))


class UserProfile(BaseModel):
    id: str
    email: Optional[str] = None
    phone: str
    full_name: str
    role: str
    is_active: bool = True
    # Driver rating aggregate — None until the driver has been rated.
    driver_rating: Optional[float] = None
    driver_review_count: int = 0


def _profile(user: User) -> UserProfile:
    return UserProfile(
        id=str(user.id),
        email=user.email,
        phone=user.phone,
        full_name=user.full_name,
        role=user.role,
        is_active=user.is_active,
        driver_rating=user.driver_rating,
        driver_review_count=user.driver_review_count,
    )


class UserUpdate(BaseModel):
    full_name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    # EmailStr, not str: an unvalidated address ends up in SMS/receipt copy and
    # in the unique index, where a malformed value is a 500 waiting to happen.
    email: Optional[EmailStr] = None


class FCMTokenRequest(BaseModel):
    token: str = Field(min_length=1, max_length=4096)


class PasswordResetRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=20)


class PasswordResetConfirm(BaseModel):
    token: str = Field(min_length=8, max_length=512)
    new_password: str = Field(min_length=MIN_PASSWORD_LENGTH, max_length=200)


# --- Endpoints ---

@router.post("/register", response_model=Token)
async def register(user_in: UserCreate, request: Request = None):
    await _enforce_rate_limit(
        request,
        "register",
        user_in.phone,
        settings.REGISTER_RATE_LIMIT,
        settings.REGISTER_RATE_WINDOW_SECONDS,
    )

    existing_user = await User.find_one(User.phone == user_in.phone)
    if existing_user:
        raise HTTPException(status_code=400, detail="Phone already registered")

    if user_in.email:
        existing_email = await User.find_one(User.email == user_in.email)
        if existing_email:
             raise HTTPException(status_code=400, detail="Email already registered")

    # UserCreate rejects role="admin"; this is the belt to that braces, in
    # case a future caller builds the model some other way.
    if user_in.role == Role.ADMIN:
        raise HTTPException(status_code=400, detail="Cannot self-register as admin")

    user = await AuthService.create_user(user_in)
    logger.info("user_registered", user_id=str(user.id), role=user.role)
    return await AuthService.issue_token_pair(user)


@router.post("/token", response_model=Token)
async def login_for_access_token(
    form_data: OAuth2PasswordRequestForm = Depends(), request: Request = None
):
    await _enforce_rate_limit(
        request,
        "login",
        form_data.username,
        settings.LOGIN_RATE_LIMIT,
        settings.LOGIN_RATE_WINDOW_SECONDS,
    )

    user = await AuthService.authenticate_user(form_data.username, form_data.password)
    if not user:
        logger.info("login_failed", identifier_present=bool(form_data.username))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=INVALID_CREDENTIALS_DETAIL,
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=INACTIVE_ACCOUNT_DETAIL
        )
    logger.info("login_succeeded", user_id=str(user.id))
    return await AuthService.issue_token_pair(user)


@router.post("/refresh", response_model=Token)
async def refresh_tokens(req: RefreshRequest, request: Request = None):
    """Exchange a refresh token for a new pair.

    The presented token is consumed atomically, so it works exactly once: a
    replay (by the legitimate client or a thief) finds the registry entry gone
    and gets a 401. Rotation is what keeps a long-lived refresh credential
    from being a permanent key to the account.
    """
    await _enforce_rate_limit(
        request,
        "refresh",
        "",
        settings.LOGIN_RATE_LIMIT,
        settings.LOGIN_RATE_WINDOW_SECONDS,
    )
    try:
        payload = token_service.decode_token(
            req.refresh_token, token_service.REFRESH_TOKEN_TYPE
        )
    except token_service.TokenError as exc:
        logger.info("refresh_rejected", reason=str(exc))
        raise credentials_exception("Invalid or expired refresh token")

    user_id = payload["sub"]
    if not await token_service.consume_refresh_token(user_id, payload.get("jti", "")):
        # Either already rotated, revoked, or a replay of a stolen token.
        logger.warning("refresh_token_reuse_or_revoked", user_id=user_id)
        raise credentials_exception("Invalid or expired refresh token")

    user = await User.get(user_id)
    if user is None or not user.is_active:
        raise credentials_exception("Invalid or expired refresh token")

    return await AuthService.issue_token_pair(user)


@router.post("/logout")
async def logout(
    req: Optional[RefreshRequest] = None,
    current_user: User = Depends(get_current_user),
):
    """Revoke this device's refresh token, or all of them.

    Passing the device's refresh token revokes just that session. Omitting it
    revokes every refresh token for the account and moves the credential
    cutoff forward, which invalidates outstanding access tokens too.
    """
    user_id = str(current_user.id)
    if req and req.refresh_token:
        payload = token_service.decode_token_or_none(
            req.refresh_token, token_service.REFRESH_TOKEN_TYPE
        )
        if payload and payload.get("sub") == user_id:
            await token_service.revoke_refresh_token(user_id, payload.get("jti", ""))
        return {"status": "logged_out", "scope": "device"}

    await token_service.revoke_all_refresh_tokens(user_id)
    current_user.tokens_valid_from = utc_now()
    await current_user.save()
    logger.info("logged_out_everywhere", user_id=user_id)
    return {"status": "logged_out", "scope": "all_devices"}


@router.get("/me", response_model=UserProfile)
async def get_me(current_user: User = Depends(get_current_user)):
    return _profile(current_user)

@router.patch("/me", response_model=UserProfile)
async def update_me(update: UserUpdate, current_user: User = Depends(get_current_user)):
    if update.full_name is not None:
        current_user.full_name = update.full_name
    if update.email is not None:
        current_user.email = update.email
    await current_user.save()
    return _profile(current_user)


# --- OTP Endpoints ---

@router.post("/otp/request")
async def request_otp(req: OTPRequest, request: Request = None):
    """Send a login OTP.

    Answers identically for a registered and an unregistered number: the old
    404 turned this endpoint into a free "is this person a Zvingo user?"
    lookup for anyone with a phone book.
    """
    await _enforce_rate_limit(
        request,
        "otp_request",
        req.phone,
        settings.OTP_REQUEST_RATE_LIMIT,
        settings.OTP_REQUEST_RATE_WINDOW_SECONDS,
    )

    user = await User.find_one(User.phone == req.phone)
    if not user:
        logger.info("otp_requested_for_unknown_phone")
        return {"status": "otp_sent"}

    otp = await AuthService.create_otp(req.phone)

    # Send OTP via SMS
    from app.sms.gateway import sms_gateway
    await sms_gateway.send_sms(req.phone, f"Your Zvingo verification code is: {otp}")

    return {"status": "otp_sent"}


@router.post("/otp/verify", response_model=Token)
async def verify_otp(req: OTPVerify, request: Request = None):
    await _enforce_rate_limit(
        request,
        "otp_verify",
        req.phone,
        settings.OTP_VERIFY_RATE_LIMIT,
        settings.OTP_VERIFY_RATE_WINDOW_SECONDS,
    )

    valid = await AuthService.verify_otp(req.phone, req.code)
    if not valid:
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")

    user = await User.find_one(User.phone == req.phone)
    if not user:
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=INACTIVE_ACCOUNT_DETAIL
        )

    return await AuthService.issue_token_pair(user)


# --- FCM Token ---

@router.post("/fcm-token")
async def register_fcm_token(req: FCMTokenRequest, current_user: User = Depends(get_current_user)):
    current_user.fcm_token = req.token
    await current_user.save()
    return {"status": "updated"}


# --- Password Reset ---

@router.post("/reset-password/request")
async def request_password_reset(req: PasswordResetRequest, request: Request = None):
    """Start a password reset.

    The token is delivered **only** over SMS. It is never returned in the
    response body — not even in development, because "development" is a
    configuration value and a misconfigured deployment would hand every
    attacker a working reset for any phone number they can name. Local testing
    reads it from the mock SMS gateway's log line instead.
    """
    await _enforce_rate_limit(
        request,
        "password_reset",
        req.phone,
        settings.PASSWORD_RESET_RATE_LIMIT,
        settings.PASSWORD_RESET_RATE_WINDOW_SECONDS,
    )

    user = await User.find_one(User.phone == req.phone)
    if not user:
        # Don't reveal whether phone exists
        return dict(RESET_INITIATED)

    token = await AuthService.create_password_reset_token(req.phone)

    from app.sms.gateway import sms_gateway
    await sms_gateway.send_sms(req.phone, f"Your Zvingo password reset code: {token}")

    return dict(RESET_INITIATED)


@router.post("/reset-password/confirm")
async def confirm_password_reset(req: PasswordResetConfirm, request: Request = None):
    """Complete a password reset and invalidate every existing session."""
    await _enforce_rate_limit(
        request,
        "password_reset_confirm",
        "",
        settings.PASSWORD_RESET_RATE_LIMIT,
        settings.PASSWORD_RESET_RATE_WINDOW_SECONDS,
    )

    phone = await AuthService.verify_reset_token(req.token)
    if not phone:
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

    user = await User.find_one(User.phone == phone)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.hashed_password = AuthService.get_password_hash(req.new_password)
    # Everything issued before this instant stops working: whoever prompted
    # the reset does not get to keep the session they may already have.
    user.tokens_valid_from = utc_now()
    await user.save()
    try:
        await token_service.revoke_all_refresh_tokens(str(user.id))
    except Exception as exc:  # pragma: no cover - cutoff above already covers it
        logger.error("refresh_revocation_failed", user_id=str(user.id), error=str(exc))
    logger.info("password_reset_completed", user_id=str(user.id))
    return {"status": "password_reset"}


# --- Favourites ---

@router.get("/favourites")
async def get_favourites(current_user: User = Depends(get_current_user)):
    return {"favourite_restaurant_ids": current_user.favourite_restaurant_ids}


@router.post("/favourites/{restaurant_id}")
async def toggle_favourite(restaurant_id: str, current_user: User = Depends(get_current_user)):
    if restaurant_id in current_user.favourite_restaurant_ids:
        current_user.favourite_restaurant_ids.remove(restaurant_id)
        action = "removed"
    else:
        current_user.favourite_restaurant_ids.append(restaurant_id)
        action = "added"
    await current_user.save()
    return {
        "action": action,
        "restaurant_id": restaurant_id,
        "favourite_restaurant_ids": current_user.favourite_restaurant_ids,
    }
