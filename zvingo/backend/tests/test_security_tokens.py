"""JWT hardening: algorithm pinning, mandatory expiry, type separation.

Each test is an attack that used to work, or that would start working the
moment someone relaxed `decode_token`.
"""

import base64
import json
from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException
from jose import jwt

from app.auth import tokens as token_service
from app.auth.tokens import (
    ACCESS_TOKEN_TYPE,
    REFRESH_TOKEN_TYPE,
    TokenError,
    create_access_token,
    create_refresh_token,
    decode_token,
    decode_token_or_none,
)
from app.config import settings
from app.time_utils import epoch_seconds, utc_now


def _unsigned(claims: dict) -> str:
    """Hand-build an `alg: none` token — the classic JWT bypass."""
    header = base64.urlsafe_b64encode(
        json.dumps({"alg": "none", "typ": "JWT"}).encode()
    ).rstrip(b"=")
    payload = base64.urlsafe_b64encode(json.dumps(claims).encode()).rstrip(b"=")
    return (header + b"." + payload + b".").decode()


# --- Minting ------------------------------------------------------------------


def test_access_token_carries_the_claims_we_rely_on():
    token = create_access_token({"sub": "user-1"}, role="driver")
    payload = decode_token(token)
    assert payload["sub"] == "user-1"
    assert payload["typ"] == ACCESS_TOKEN_TYPE
    assert payload["iss"] == settings.JWT_ISSUER
    assert payload["role"] == "driver"
    assert payload["exp"] > payload["iat"]
    assert payload["jti"]


def test_two_tokens_for_the_same_user_are_distinguishable():
    """A per-token id is what makes revocation and audit possible at all."""
    first = decode_token(create_access_token({"sub": "user-1"}))
    second = decode_token(create_access_token({"sub": "user-1"}))
    assert first["jti"] != second["jti"]


def test_a_caller_cannot_smuggle_in_its_own_security_claims():
    """Extra keys are merged, but type/issuer/expiry are ours to set."""
    token = create_access_token(
        {
            "sub": "user-1",
            "typ": REFRESH_TOKEN_TYPE,
            "iss": "evil",
            "exp": epoch_seconds() + 10_000_000,
            "jti": "attacker-chosen",
        }
    )
    payload = decode_token(token)
    assert payload["typ"] == ACCESS_TOKEN_TYPE
    assert payload["iss"] == settings.JWT_ISSUER
    assert payload["jti"] != "attacker-chosen"


def test_a_token_cannot_be_minted_without_a_subject():
    with pytest.raises(TokenError):
        create_access_token({})


# --- Verification -------------------------------------------------------------


def test_alg_none_tokens_are_rejected():
    forged = _unsigned({"sub": "admin", "exp": epoch_seconds() + 600, "iat": epoch_seconds()})
    with pytest.raises(TokenError):
        decode_token(forged)


def test_tokens_signed_with_another_key_are_rejected():
    forged = jwt.encode(
        {
            "sub": "user-1",
            "typ": ACCESS_TOKEN_TYPE,
            "iss": settings.JWT_ISSUER,
            "iat": epoch_seconds(),
            "exp": epoch_seconds() + 600,
        },
        "an-attackers-own-signing-key",
        algorithm="HS256",
    )
    with pytest.raises(TokenError):
        decode_token(forged)


def test_expired_tokens_are_rejected():
    token = create_access_token({"sub": "user-1"}, expires_delta=timedelta(seconds=-1))
    with pytest.raises(TokenError):
        decode_token(token)


def test_tokens_without_an_expiry_are_rejected():
    """No `exp` must not mean "never expires"."""
    eternal = jwt.encode(
        {"sub": "user-1", "typ": ACCESS_TOKEN_TYPE, "iss": settings.JWT_ISSUER, "iat": epoch_seconds()},
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )
    with pytest.raises(TokenError):
        decode_token(eternal)


def test_tokens_from_another_issuer_are_rejected():
    foreign = jwt.encode(
        {
            "sub": "user-1",
            "typ": ACCESS_TOKEN_TYPE,
            "iss": "some-other-service",
            "iat": epoch_seconds(),
            "exp": epoch_seconds() + 600,
        },
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )
    with pytest.raises(TokenError):
        decode_token(foreign)


def test_a_refresh_token_is_not_a_bearer_credential():
    refresh, _jti, _ttl = create_refresh_token("user-1")
    with pytest.raises(TokenError, match="Expected a access token"):
        decode_token(refresh, ACCESS_TOKEN_TYPE)
    # ...and it is perfectly valid as what it is.
    assert decode_token(refresh, REFRESH_TOKEN_TYPE)["sub"] == "user-1"


def test_an_access_token_cannot_be_redeemed_at_the_refresh_endpoint():
    access = create_access_token({"sub": "user-1"})
    with pytest.raises(TokenError, match="Expected a refresh token"):
        decode_token(access, REFRESH_TOKEN_TYPE)


def test_decode_token_or_none_swallows_exactly_the_same_cases():
    assert decode_token_or_none("") is None
    assert decode_token_or_none("garbage") is None
    assert decode_token_or_none(create_access_token({"sub": "u"}))["sub"] == "u"


def test_empty_token_is_rejected():
    with pytest.raises(TokenError, match="Missing token"):
        decode_token("")


# --- Session invalidation -----------------------------------------------------


def _user(**overrides):
    values = {
        "id": "user-1",
        "role": "consumer",
        "is_active": True,
        "tokens_valid_from": None,
        "save": AsyncMock(),
    }
    values.update(overrides)
    return SimpleNamespace(**values)


@pytest.mark.asyncio
async def test_a_deactivated_account_cannot_use_an_existing_token(monkeypatch):
    import app.auth.router as module

    disabled = _user(is_active=False)
    monkeypatch.setattr(module, "User", SimpleNamespace(get=AsyncMock(return_value=disabled)))
    with pytest.raises(HTTPException) as exc:
        await module.resolve_user_from_token(create_access_token({"sub": "user-1"}))
    assert exc.value.status_code == 403


@pytest.mark.asyncio
async def test_tokens_issued_before_a_password_reset_stop_working(monkeypatch):
    import app.auth.router as module

    # A session that existed an hour before the reset.
    stale = jwt.encode(
        {
            "sub": "user-1",
            "typ": ACCESS_TOKEN_TYPE,
            "iss": settings.JWT_ISSUER,
            "iat": epoch_seconds() - 3600,
            "exp": epoch_seconds() + 600,
            "jti": "stale",
        },
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )
    # `tokens_valid_from` is naive UTC, as every datetime on the document is.
    reset_user = _user(tokens_valid_from=utc_now())
    monkeypatch.setattr(module, "User", SimpleNamespace(get=AsyncMock(return_value=reset_user)))

    with pytest.raises(HTTPException) as exc:
        await module.resolve_user_from_token(stale)
    assert exc.value.status_code == 401

    # A token minted after the reset is fine.
    fresh = create_access_token({"sub": "user-1"})
    assert await module.resolve_user_from_token(fresh) is reset_user


@pytest.mark.asyncio
async def test_a_token_for_a_deleted_user_is_rejected(monkeypatch):
    import app.auth.router as module

    monkeypatch.setattr(module, "User", SimpleNamespace(get=AsyncMock(return_value=None)))
    with pytest.raises(HTTPException) as exc:
        await module.resolve_user_from_token(create_access_token({"sub": "gone"}))
    assert exc.value.status_code == 401


# --- Refresh rotation ---------------------------------------------------------


class RecordingRedis:
    """Minimal Redis stand-in with the handful of ops the registry uses."""

    def __init__(self):
        self.values = {}
        self.closed = False

    async def setex(self, key, _ttl, value):
        self.values[key] = value

    async def delete(self, key):
        return 1 if self.values.pop(key, None) is not None else 0

    async def scan_iter(self, match=None):
        prefix = (match or "").rstrip("*")
        for key in list(self.values):
            if key.startswith(prefix):
                yield key

    async def aclose(self):
        self.closed = True


@pytest.fixture
def fake_redis(monkeypatch):
    import redis.asyncio as aioredis

    store = RecordingRedis()
    monkeypatch.setattr(aioredis, "from_url", lambda *_a, **_k: store)
    return store


@pytest.mark.asyncio
async def test_a_refresh_token_works_exactly_once(fake_redis):
    _token, jti, ttl = create_refresh_token("user-1")
    await token_service.remember_refresh_token("user-1", jti, ttl)

    assert await token_service.consume_refresh_token("user-1", jti) is True
    # The replay — by the real client or by whoever stole it — fails.
    assert await token_service.consume_refresh_token("user-1", jti) is False


@pytest.mark.asyncio
async def test_an_unknown_refresh_token_is_never_honoured(fake_redis):
    assert await token_service.consume_refresh_token("user-1", "never-issued") is False


@pytest.mark.asyncio
async def test_revoking_everything_kills_every_session_for_that_user(fake_redis):
    for _ in range(3):
        _token, jti, ttl = create_refresh_token("user-1")
        await token_service.remember_refresh_token("user-1", jti, ttl)
    _other, other_jti, other_ttl = create_refresh_token("user-2")
    await token_service.remember_refresh_token("user-2", other_jti, other_ttl)

    assert await token_service.revoke_all_refresh_tokens("user-1") == 3
    # Another user's sessions are untouched.
    assert await token_service.consume_refresh_token("user-2", other_jti) is True


@pytest.mark.asyncio
async def test_revoking_one_device_leaves_the_others_signed_in(fake_redis):
    _a, jti_a, ttl = create_refresh_token("user-1")
    _b, jti_b, _ = create_refresh_token("user-1")
    await token_service.remember_refresh_token("user-1", jti_a, ttl)
    await token_service.remember_refresh_token("user-1", jti_b, ttl)

    await token_service.revoke_refresh_token("user-1", jti_a)

    assert await token_service.consume_refresh_token("user-1", jti_a) is False
    assert await token_service.consume_refresh_token("user-1", jti_b) is True
