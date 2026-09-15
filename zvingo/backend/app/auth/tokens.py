"""JWT minting and verification.

Everything about a Zvingo token is decided here so no caller can accidentally
relax it:

* **The algorithm is pinned.** ``jwt.decode`` is always given an explicit
  single-algorithm allow-list, which is what makes ``alg: none`` and
  HS/RS confusion attacks fail closed.
* **Expiry is mandatory.** A token without ``exp`` is rejected rather than
  treated as eternal, and ``iat``/``sub`` are required too.
* **Type is part of the claim set.** An access token cannot be replayed at the
  refresh endpoint and a refresh token cannot be used as a bearer credential,
  because :func:`decode_token` checks ``typ``.
* **Role travels with the token** so role checks do not need a second lookup,
  but the role is re-read from the user document on every request — the claim
  is a hint, the database is the authority.

Refresh tokens are single-use. Each one carries a ``jti`` recorded in Redis;
refreshing consumes that entry and issues a new pair (rotation), so a stolen
refresh token stops working the moment the legitimate client next refreshes,
and the reuse is visible. Logging out deletes the entry (revocation).
"""

from datetime import timedelta
from typing import Any, Dict, Optional
import uuid

import structlog
from jose import JWTError, jwt

from app.config import settings
from app.db.redis import redis_client
from app.time_utils import epoch_seconds, utc_now_aware

logger = structlog.get_logger()

ACCESS_TOKEN_TYPE = "access"
REFRESH_TOKEN_TYPE = "refresh"

_REQUIRED_CLAIMS = {"require_exp": True, "require_iat": True, "require_sub": True}


class TokenError(Exception):
    """A token was missing, malformed, expired, revoked or of the wrong type."""


def _encode(claims: Dict[str, Any]) -> str:
    return jwt.encode(claims, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def _base_claims(subject: str, token_type: str, lifetime: timedelta) -> Dict[str, Any]:
    now = utc_now_aware()
    return {
        "sub": subject,
        "typ": token_type,
        "iss": settings.JWT_ISSUER,
        "iat": epoch_seconds(now),
        "nbf": epoch_seconds(now),
        "exp": epoch_seconds(now + lifetime),
        "jti": uuid.uuid4().hex,
    }


def create_access_token(
    data: Dict[str, Any],
    expires_delta: Optional[timedelta] = None,
    role: Optional[str] = None,
) -> str:
    """Mint an access token.

    ``data`` must carry ``sub`` (the user id). Any extra keys are merged in,
    but the security-relevant claims below always win — a caller cannot
    override ``typ``, ``iss`` or ``exp`` by passing them in.
    """
    extra = dict(data)
    subject = str(extra.pop("sub", "") or "")
    if not subject:
        raise TokenError("Cannot mint a token without a subject")

    lifetime = expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    claims = {k: v for k, v in extra.items() if k not in ("typ", "iss", "exp", "iat", "nbf", "jti")}
    if role is not None:
        claims["role"] = role
    claims.update(_base_claims(subject, ACCESS_TOKEN_TYPE, lifetime))
    return _encode(claims)


def create_refresh_token(subject: str, role: Optional[str] = None) -> tuple[str, str, int]:
    """Mint a refresh token. Returns ``(token, jti, ttl_seconds)``.

    The caller is responsible for recording the ``jti`` with
    :func:`remember_refresh_token`; splitting it this way keeps token minting
    free of I/O so it stays testable without Redis.
    """
    lifetime = timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    claims = _base_claims(str(subject), REFRESH_TOKEN_TYPE, lifetime)
    if role is not None:
        claims["role"] = role
    return _encode(claims), claims["jti"], int(lifetime.total_seconds())


def decode_token(token: str, expected_type: Optional[str] = ACCESS_TOKEN_TYPE) -> Dict[str, Any]:
    """Verify signature, expiry, issuer and type; return the claim set.

    Raises :class:`TokenError` for anything that is not a currently valid token
    of ``expected_type``. Pass ``expected_type=None`` to accept either kind.
    """
    if not token:
        raise TokenError("Missing token")
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],  # pinned: defeats alg=none / confusion
            issuer=settings.JWT_ISSUER,
            options=dict(_REQUIRED_CLAIMS),
        )
    except JWTError as exc:
        raise TokenError(str(exc)) from exc

    if expected_type is not None and payload.get("typ") != expected_type:
        raise TokenError(
            f"Expected a {expected_type} token, got {payload.get('typ') or 'untyped'}"
        )
    if not payload.get("sub"):
        raise TokenError("Token has no subject")
    return payload


def decode_token_or_none(
    token: Optional[str], expected_type: Optional[str] = ACCESS_TOKEN_TYPE
) -> Optional[Dict[str, Any]]:
    """:func:`decode_token` that returns None instead of raising."""
    if not token:
        return None
    try:
        return decode_token(token, expected_type)
    except TokenError:
        return None


# --- Refresh-token registry (rotation + revocation) ---------------------------


def _refresh_key(user_id: str, jti: str) -> str:
    return f"auth:refresh:{user_id}:{jti}"


async def remember_refresh_token(user_id: str, jti: str, ttl_seconds: int) -> None:
    """Record a refresh token as live. Absent == revoked."""
    async with redis_client() as r:
        await r.setex(_refresh_key(user_id, jti), ttl_seconds, "1")


async def consume_refresh_token(user_id: str, jti: str) -> bool:
    """Atomically burn a refresh token. False if it was already used/revoked.

    ``DEL`` returns the number of keys removed, so the winner of a race is the
    only caller that sees 1 — two clients replaying the same refresh token
    cannot both succeed.
    """
    async with redis_client() as r:
        deleted = await r.delete(_refresh_key(user_id, jti))
    return bool(deleted)


async def revoke_refresh_token(user_id: str, jti: str) -> None:
    """Revoke one refresh token (single-device logout)."""
    async with redis_client() as r:
        await r.delete(_refresh_key(user_id, jti))


async def revoke_all_refresh_tokens(user_id: str) -> int:
    """Revoke every refresh token for a user (logout everywhere).

    Called on password reset so a stolen session cannot outlive the password
    that leaked it.
    """
    removed = 0
    async with redis_client() as r:
        pattern = _refresh_key(user_id, "*")
        scan = getattr(r, "scan_iter", None)
        if scan is None:  # pragma: no cover - only for minimal test doubles
            return 0
        async for key in scan(match=pattern):
            removed += await r.delete(key)
    return removed
