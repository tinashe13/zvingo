from pydantic import BaseModel, EmailStr, Field, field_validator
from typing import Optional

from app.auth.authorization import Role

# Roles a user may give themselves at registration. "admin" is deliberately
# absent: self-service registration must never be able to mint an
# administrator, and before this list existed `{"role": "admin"}` in the
# register payload was a complete privilege escalation. Admin accounts are
# assigned by an existing admin through PATCH /admin/users/{id}.
SELF_ASSIGNABLE_ROLES = (Role.CONSUMER, Role.DRIVER, Role.MERCHANT)

MIN_PASSWORD_LENGTH = 8


class Token(BaseModel):
    access_token: str
    token_type: str
    # Present on login/register/refresh. Clients exchange it at
    # POST /auth/refresh for a new pair; each refresh token works exactly once.
    refresh_token: Optional[str] = None
    expires_in: Optional[int] = None


class TokenData(BaseModel):
    user_id: Optional[str] = None


class RefreshRequest(BaseModel):
    refresh_token: str


class UserCreate(BaseModel):
    email: Optional[EmailStr] = None
    phone: str = Field(min_length=6, max_length=20)
    password: str = Field(min_length=MIN_PASSWORD_LENGTH, max_length=200)
    full_name: str = Field(min_length=1, max_length=120)
    role: str = Role.DRIVER  # driver, consumer, merchant — never admin

    @field_validator("role")
    @classmethod
    def _role_must_be_self_assignable(cls, value: str) -> str:
        normalised = (value or "").strip().lower()
        if normalised not in SELF_ASSIGNABLE_ROLES:
            raise ValueError(
                "role must be one of " + ", ".join(SELF_ASSIGNABLE_ROLES)
            )
        return normalised

    @field_validator("phone")
    @classmethod
    def _phone_must_be_e164(cls, value: str) -> str:
        candidate = (value or "").strip().replace(" ", "")
        if not candidate.startswith("+") or not candidate[1:].isdigit():
            raise ValueError("phone must be E.164, e.g. +263771234567")
        return candidate


class UserLogin(BaseModel):
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    password: str


class OTPRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=20)


class OTPVerify(BaseModel):
    phone: str = Field(min_length=6, max_length=20)
    code: str = Field(min_length=4, max_length=10)
