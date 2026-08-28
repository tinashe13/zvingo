from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from app.auth.schemas import Token, UserCreate, UserLogin, OTPRequest, OTPVerify
from app.auth.service import AuthService
from app.auth.models import User
from jose import jwt, JWTError
from app.config import settings
from pydantic import BaseModel
from typing import Optional

router = APIRouter()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/token")

INACTIVE_ACCOUNT_DETAIL = "Account is deactivated"


def _credentials_exception() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def resolve_user_from_token(token: str) -> User:
    """Decode a JWT and load the active user it identifies.

    Raises 401 for a bad/expired token or an unknown subject, and 403 for a
    user an admin has deactivated — a deactivated account must not be able to
    keep using tokens minted before the deactivation.
    """
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise _credentials_exception()
    except JWTError:
        raise _credentials_exception()
    user = await User.get(user_id)
    if user is None:
        raise _credentials_exception()
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=INACTIVE_ACCOUNT_DETAIL
        )
    return user


# --- Helper to get current user from JWT ---
async def get_current_user(token: str = Depends(oauth2_scheme)) -> User:
    return await resolve_user_from_token(token)


async def get_current_user_flexible(request: Request) -> User:
    """Authenticate from the Authorization header *or* a `token` query param.

    Browser `EventSource` and `WebSocket` clients cannot set headers, so
    streaming endpoints accept the JWT as a query parameter as well.
    """
    token = request.query_params.get("token")
    if not token:
        header = request.headers.get("authorization", "")
        if header.lower().startswith("bearer "):
            token = header[7:]
    if not token:
        raise _credentials_exception()
    return await resolve_user_from_token(token)


async def get_current_admin(user: User = Depends(get_current_user)) -> User:
    """Require an authenticated admin user (role == "admin")."""
    if user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )
    return user


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
    full_name: Optional[str] = None
    email: Optional[str] = None


class FCMTokenRequest(BaseModel):
    token: str


class PasswordResetRequest(BaseModel):
    phone: str


class PasswordResetConfirm(BaseModel):
    token: str
    new_password: str


# --- Endpoints ---

@router.post("/register", response_model=Token)
async def register(user_in: UserCreate):
    existing_user = await User.find_one(User.phone == user_in.phone)
    if existing_user:
        raise HTTPException(status_code=400, detail="Phone already registered")

    if user_in.email:
        existing_email = await User.find_one(User.email == user_in.email)
        if existing_email:
             raise HTTPException(status_code=400, detail="Email already registered")

    user = await AuthService.create_user(user_in)
    access_token = AuthService.create_access_token(data={"sub": str(user.id)})
    return {"access_token": access_token, "token_type": "bearer"}

@router.post("/token", response_model=Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    user = await AuthService.authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=INACTIVE_ACCOUNT_DETAIL
        )
    access_token = AuthService.create_access_token(data={"sub": str(user.id)})
    return {"access_token": access_token, "token_type": "bearer"}

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
async def request_otp(req: OTPRequest):
    user = await User.find_one(User.phone == req.phone)
    if not user:
        raise HTTPException(status_code=404, detail="Phone number not registered")

    otp = await AuthService.create_otp(req.phone)

    # Send OTP via SMS
    from app.sms.gateway import sms_gateway
    await sms_gateway.send_sms(req.phone, f"Your Zvingo verification code is: {otp}")

    return {"status": "otp_sent"}


@router.post("/otp/verify", response_model=Token)
async def verify_otp(req: OTPVerify):
    valid = await AuthService.verify_otp(req.phone, req.code)
    if not valid:
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")

    user = await User.find_one(User.phone == req.phone)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    access_token = AuthService.create_access_token(data={"sub": str(user.id)})
    return {"access_token": access_token, "token_type": "bearer"}


# --- FCM Token ---

@router.post("/fcm-token")
async def register_fcm_token(req: FCMTokenRequest, current_user: User = Depends(get_current_user)):
    current_user.fcm_token = req.token
    await current_user.save()
    return {"status": "updated"}


# --- Password Reset ---

@router.post("/reset-password/request")
async def request_password_reset(req: PasswordResetRequest):
    user = await User.find_one(User.phone == req.phone)
    if not user:
        # Don't reveal whether phone exists
        return {"status": "reset_initiated"}

    token = await AuthService.create_password_reset_token(req.phone)

    from app.sms.gateway import sms_gateway
    await sms_gateway.send_sms(req.phone, f"Your Zvingo password reset code: {token[:8]}")

    # SECURITY: the reset token must ONLY be delivered out-of-band (SMS).
    # It is echoed in the response strictly in development, where the SMS
    # gateway is mocked, to keep local testing possible.
    if settings.ENVIRONMENT == "development":
        return {"status": "reset_initiated", "token": token}
    return {"status": "reset_initiated"}


@router.post("/reset-password/confirm")
async def confirm_password_reset(req: PasswordResetConfirm):
    phone = await AuthService.verify_reset_token(req.token)
    if not phone:
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

    user = await User.find_one(User.phone == phone)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.hashed_password = AuthService.get_password_hash(req.new_password)
    await user.save()
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
