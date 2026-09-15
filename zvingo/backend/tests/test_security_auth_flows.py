"""Public auth surface: enumeration oracles, one-shot credentials, escalation."""

import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.auth.schemas import SELF_ASSIGNABLE_ROLES, UserCreate
from app.auth.service import AuthService, _digest
from app.config import settings


class FakeRedis:
    """Enough Redis for the OTP / reset-token records."""

    def __init__(self):
        self.values = {}
        self.closed = False

    async def setex(self, key, _ttl, value):
        self.values[key] = value

    async def get(self, key):
        return self.values.get(key)

    async def delete(self, key):
        return 1 if self.values.pop(key, None) is not None else 0

    async def aclose(self):
        self.closed = True


@pytest.fixture
def redis(monkeypatch):
    import redis.asyncio as aioredis

    store = FakeRedis()
    monkeypatch.setattr(aioredis, "from_url", lambda *_a, **_k: store)
    return store


class _QueryField:
    """Stands in for a Beanie indexed field so `User.phone == x` builds a query."""

    def __eq__(self, other):
        return ("eq", other)


def fake_user_model(**attrs):
    """A `User` stand-in exposing the class-level query fields the router uses."""
    return SimpleNamespace(phone=_QueryField(), email=_QueryField(), **attrs)


def user(**overrides):
    values = {
        "id": "user-1",
        "phone": "+263770000000",
        "role": "consumer",
        "is_active": True,
        "hashed_password": "x",
        "tokens_valid_from": None,
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


# --- Privilege escalation -----------------------------------------------------


def test_nobody_can_self_register_as_an_admin():
    """`{"role": "admin"}` in the register payload used to mint an admin."""
    with pytest.raises(ValidationError, match="role must be one of"):
        UserCreate(
            phone="+263770000000", password="a-good-password", full_name="A", role="admin"
        )
    assert "admin" not in SELF_ASSIGNABLE_ROLES


@pytest.mark.parametrize("role", SELF_ASSIGNABLE_ROLES)
def test_the_three_product_roles_remain_self_assignable(role):
    created = UserCreate(
        phone="+263770000000", password="a-good-password", full_name="A", role=role
    )
    assert created.role == role


def test_role_is_normalised_so_case_cannot_smuggle_admin_in():
    with pytest.raises(ValidationError):
        UserCreate(
            phone="+263770000000", password="a-good-password", full_name="A", role="Admin"
        )
    assert UserCreate(
        phone="+263770000000", password="a-good-password", full_name="A", role="MERCHANT"
    ).role == "merchant"


def test_short_passwords_are_refused_at_the_schema():
    with pytest.raises(ValidationError):
        UserCreate(phone="+263770000000", password="1234567", full_name="A")


def test_phone_must_be_e164():
    with pytest.raises(ValidationError, match="E.164"):
        UserCreate(phone="0771234567", password="a-good-password", full_name="A")


@pytest.mark.asyncio
async def test_register_refuses_an_admin_role_even_if_the_model_is_bypassed(monkeypatch):
    import app.auth.router as module

    payload = UserCreate(phone="+263770000000", password="a-good-password", full_name="A")
    object.__setattr__(payload, "role", "admin")
    monkeypatch.setattr(
        module, "User", fake_user_model(find_one=AsyncMock(return_value=None))
    )
    with pytest.raises(HTTPException, match="Cannot self-register as admin"):
        await module.register(payload)


# --- Enumeration --------------------------------------------------------------


@pytest.mark.asyncio
async def test_otp_request_answers_the_same_for_known_and_unknown_numbers(monkeypatch):
    import app.auth.router as module
    import app.sms.gateway as sms_module

    known = user()
    monkeypatch.setattr(module.AuthService, "create_otp", AsyncMock(return_value="123456"))
    monkeypatch.setattr(sms_module.sms_gateway, "send_sms", AsyncMock(return_value=True))

    monkeypatch.setattr(module, "User", fake_user_model(find_one=AsyncMock(return_value=None)))
    unknown_response = await module.request_otp(module.OTPRequest(phone="+263770000001"))

    monkeypatch.setattr(module, "User", fake_user_model(find_one=AsyncMock(return_value=known)))
    known_response = await module.request_otp(module.OTPRequest(phone=known.phone))

    assert unknown_response == known_response == {"status": "otp_sent"}


@pytest.mark.asyncio
async def test_password_reset_answers_the_same_for_known_and_unknown_numbers(monkeypatch):
    import app.auth.router as module
    import app.sms.gateway as sms_module

    monkeypatch.setattr(
        module.AuthService, "create_password_reset_token", AsyncMock(return_value="tok")
    )
    monkeypatch.setattr(sms_module.sms_gateway, "send_sms", AsyncMock(return_value=True))

    monkeypatch.setattr(module, "User", fake_user_model(find_one=AsyncMock(return_value=None)))
    unknown = await module.request_password_reset(
        module.PasswordResetRequest(phone="+263770000001")
    )
    monkeypatch.setattr(module, "User", fake_user_model(find_one=AsyncMock(return_value=user())))
    known = await module.request_password_reset(
        module.PasswordResetRequest(phone="+263770000000")
    )
    assert unknown == known == {"status": "reset_initiated"}


@pytest.mark.asyncio
@pytest.mark.parametrize("environment", ["development", "production"])
async def test_the_reset_token_never_appears_in_the_response_body(monkeypatch, environment):
    """It is delivered over SMS only — in every environment."""
    import app.auth.router as module
    import app.sms.gateway as sms_module

    monkeypatch.setattr(settings, "ENVIRONMENT", environment)
    monkeypatch.setattr(
        module.AuthService,
        "create_password_reset_token",
        AsyncMock(return_value="super-secret-reset-token"),
    )
    sent = AsyncMock(return_value=True)
    monkeypatch.setattr(sms_module.sms_gateway, "send_sms", sent)
    monkeypatch.setattr(module, "User", fake_user_model(find_one=AsyncMock(return_value=user())))

    response = await module.request_password_reset(
        module.PasswordResetRequest(phone="+263770000000")
    )

    assert response == {"status": "reset_initiated"}
    assert "super-secret-reset-token" not in json.dumps(response)
    # ...and it did go out of band.
    assert "super-secret-reset-token" in sent.await_args.args[1]


@pytest.mark.asyncio
async def test_a_valid_otp_for_an_unknown_user_is_reported_as_a_bad_otp(monkeypatch):
    import app.auth.router as module

    monkeypatch.setattr(module.AuthService, "verify_otp", AsyncMock(return_value=True))
    monkeypatch.setattr(module, "User", fake_user_model(find_one=AsyncMock(return_value=None)))
    with pytest.raises(HTTPException) as exc:
        await module.verify_otp(module.OTPVerify(phone="+263770000000", code="123456"))
    assert exc.value.status_code == 400
    assert exc.value.detail == "Invalid or expired OTP"


@pytest.mark.asyncio
async def test_login_does_not_say_which_half_of_the_credential_was_wrong(monkeypatch):
    import app.auth.router as module

    monkeypatch.setattr(module.AuthService, "authenticate_user", AsyncMock(return_value=None))
    with pytest.raises(HTTPException) as exc:
        await module.login_for_access_token(
            SimpleNamespace(username="nobody@example.com", password="whatever")
        )
    assert exc.value.status_code == 401
    assert exc.value.detail == module.INVALID_CREDENTIALS_DETAIL


# --- One-shot credentials -----------------------------------------------------


@pytest.mark.asyncio
async def test_otps_are_stored_hashed_not_in_the_clear(redis):
    otp = await AuthService.create_otp("+263770000000")
    stored = json.loads(redis.values["otp:+263770000000"])
    assert otp not in json.dumps(stored)
    assert stored["hash"] == _digest(otp, salt="+263770000000")


@pytest.mark.asyncio
async def test_an_otp_works_exactly_once(redis):
    otp = await AuthService.create_otp("+263770000000")
    assert await AuthService.verify_otp("+263770000000", otp) is True
    assert await AuthService.verify_otp("+263770000000", otp) is False


@pytest.mark.asyncio
async def test_an_otp_is_burned_after_too_many_wrong_guesses(redis, monkeypatch):
    monkeypatch.setattr(settings, "OTP_MAX_ATTEMPTS", 3)
    otp = await AuthService.create_otp("+263770000000")

    for _ in range(3):
        assert await AuthService.verify_otp("+263770000000", "000000") is False

    # The record is gone, so even the real code no longer works.
    assert "otp:+263770000000" not in redis.values
    assert await AuthService.verify_otp("+263770000000", otp) is False


@pytest.mark.asyncio
async def test_a_wrong_guess_does_not_extend_the_otps_life(redis):
    await AuthService.create_otp("+263770000000")
    before = json.loads(redis.values["otp:+263770000000"])["exp"]
    await AuthService.verify_otp("+263770000000", "000000")
    after = json.loads(redis.values["otp:+263770000000"])["exp"]
    assert after == before


@pytest.mark.asyncio
async def test_an_expired_otp_is_refused_even_if_redis_still_holds_it(redis):
    otp = await AuthService.create_otp("+263770000000")
    record = json.loads(redis.values["otp:+263770000000"])
    record["exp"] = 0
    redis.values["otp:+263770000000"] = json.dumps(record)
    assert await AuthService.verify_otp("+263770000000", otp) is False


@pytest.mark.asyncio
async def test_a_corrupt_otp_record_is_discarded_rather_than_trusted(redis):
    redis.values["otp:+263770000000"] = "not-json"
    assert await AuthService.verify_otp("+263770000000", "123456") is False
    assert "otp:+263770000000" not in redis.values


@pytest.mark.asyncio
async def test_reset_tokens_are_stored_hashed_and_are_single_use(redis):
    token = await AuthService.create_password_reset_token("+263770000000")

    # The plaintext token is nowhere in Redis; only its digest keys the entry.
    assert all(token not in key for key in redis.values)
    assert f"auth:reset:{_digest(token)}" in redis.values

    assert await AuthService.verify_reset_token(token) == "+263770000000"
    assert await AuthService.verify_reset_token(token) is None


@pytest.mark.asyncio
async def test_reset_tokens_are_short_lived_by_configuration():
    assert settings.PASSWORD_RESET_TTL_SECONDS <= 3600


@pytest.mark.asyncio
async def test_an_unknown_reset_token_yields_nothing(redis):
    assert await AuthService.verify_reset_token("never-issued") is None
    assert await AuthService.verify_reset_token("") is None


@pytest.mark.asyncio
async def test_completing_a_reset_invalidates_every_existing_session(monkeypatch):
    import app.auth.router as module

    account = user()
    monkeypatch.setattr(
        module.AuthService, "verify_reset_token", AsyncMock(return_value=account.phone)
    )
    monkeypatch.setattr(module.AuthService, "get_password_hash", lambda value: f"hashed-{value}")
    monkeypatch.setattr(
        module, "User", fake_user_model(find_one=AsyncMock(return_value=account))
    )
    revoked = AsyncMock(return_value=2)
    monkeypatch.setattr(module.token_service, "revoke_all_refresh_tokens", revoked)

    result = await module.confirm_password_reset(
        module.PasswordResetConfirm(token="a-valid-token", new_password="a-new-password")
    )

    assert result == {"status": "password_reset"}
    assert account.hashed_password == "hashed-a-new-password"
    assert account.tokens_valid_from is not None  # access tokens cut off
    revoked.assert_awaited_once_with("user-1")  # refresh tokens revoked


# --- Rate limiting ------------------------------------------------------------


@pytest.mark.asyncio
async def test_login_is_rate_limited_per_ip_and_per_identifier(monkeypatch):
    import app.auth.router as module

    seen = []

    class Limiter:
        def __init__(self, _redis):
            pass

        async def check(self, key, limit, window):
            seen.append(key)
            return SimpleNamespace(allowed=True, retry_after=0)

    monkeypatch.setattr(module, "RateLimiter", Limiter)
    monkeypatch.setattr(module.AuthService, "authenticate_user", AsyncMock(return_value=None))

    request = SimpleNamespace(
        headers={"x-forwarded-for": "203.0.113.9, 10.0.0.1"}, client=None
    )
    with pytest.raises(HTTPException):
        await module.login_for_access_token(
            SimpleNamespace(username="Victim@Example.com", password="x"), request
        )

    assert "rate_limit:login:ip:203.0.113.9" in seen
    assert "rate_limit:login:id:victim@example.com" in seen


@pytest.mark.asyncio
async def test_exceeding_the_limit_returns_429_with_retry_after(monkeypatch):
    import app.auth.router as module

    class Limiter:
        def __init__(self, _redis):
            pass

        async def check(self, key, limit, window):
            return SimpleNamespace(allowed=False, retry_after=42)

    monkeypatch.setattr(module, "RateLimiter", Limiter)
    with pytest.raises(HTTPException) as exc:
        await module.login_for_access_token(
            SimpleNamespace(username="victim@example.com", password="x")
        )
    assert exc.value.status_code == 429
    assert exc.value.headers["Retry-After"] == "42"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "bucket_limit",
    [
        ("LOGIN_RATE_LIMIT", settings.LOGIN_RATE_LIMIT),
        ("REGISTER_RATE_LIMIT", settings.REGISTER_RATE_LIMIT),
        ("OTP_REQUEST_RATE_LIMIT", settings.OTP_REQUEST_RATE_LIMIT),
        ("OTP_VERIFY_RATE_LIMIT", settings.OTP_VERIFY_RATE_LIMIT),
        ("PASSWORD_RESET_RATE_LIMIT", settings.PASSWORD_RESET_RATE_LIMIT),
    ],
)
async def test_every_credential_endpoint_has_a_finite_budget(bucket_limit):
    name, limit = bucket_limit
    assert 0 < limit <= 20, f"{name} is not a credible anti-stuffing limit"


@pytest.mark.asyncio
async def test_a_redis_outage_does_not_lock_users_out(monkeypatch):
    """The limiter fails open: availability, not authorization."""
    import app.auth.router as module

    class Broken:
        def __init__(self, _redis):
            pass

        async def check(self, *_a, **_k):
            raise RuntimeError("redis down")

    monkeypatch.setattr(module, "RateLimiter", Broken)
    # No exception: the call proceeds to the real authentication check.
    await module._enforce_rate_limit(None, "login", "someone", 5, 60)


def test_client_ip_prefers_the_left_most_forwarded_address():
    import app.auth.router as module

    assert module._client_ip(None) == "unknown"
    assert (
        module._client_ip(
            SimpleNamespace(headers={"x-forwarded-for": "198.51.100.7, 10.0.0.1"}, client=None)
        )
        == "198.51.100.7"
    )
    assert (
        module._client_ip(
            SimpleNamespace(headers={}, client=SimpleNamespace(host="192.0.2.4"))
        )
        == "192.0.2.4"
    )
    assert module._client_ip(SimpleNamespace(headers={}, client=None)) == "unknown"
