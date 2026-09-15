"""Authentication primitives shared by HTTP and WebSocket entry points.

Everything here is free of FastAPI routing and of the ``User`` document, so
both ``app.auth.router`` (HTTP dependencies) and ``app.auth.ws`` (WebSocket
handshakes) can import it without a cycle. The rules live here once so the two
transports cannot drift apart — a token rejected on HTTP must be rejected on a
socket too.
"""

from typing import Any, Optional

from fastapi import HTTPException, status

from app.time_utils import ensure_utc, epoch_seconds

INACTIVE_ACCOUNT_DETAIL = "Account is deactivated"
CREDENTIALS_DETAIL = "Could not validate credentials"


def credentials_exception(detail: str = CREDENTIALS_DETAIL) -> HTTPException:
    """401 with the WWW-Authenticate header clients expect.

    The detail is intentionally uniform: expired, forged, wrong-type and
    "names a deleted user" all look identical from outside, so a caller cannot
    probe which of those it hit.
    """
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def inactive_account_exception() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_403_FORBIDDEN, detail=INACTIVE_ACCOUNT_DETAIL
    )


def bearer_token_from(request: Any) -> Optional[str]:
    """Pull a bearer token off a Request or a WebSocket.

    Header first, then a ``?token=`` query parameter — browser ``EventSource``
    and ``WebSocket`` clients cannot set headers, so streaming endpoints have
    to accept the query form. Query strings reach proxy access logs, which is
    an argument for short access-token lifetimes, not against the mechanism.
    """
    header = ""
    try:
        header = request.headers.get("authorization", "") or ""
    except Exception:  # pragma: no cover - defensive against odd scopes
        header = ""
    if header.lower().startswith("bearer "):
        candidate = header[7:].strip()
        if candidate:
            return candidate
    try:
        token = request.query_params.get("token")
    except Exception:  # pragma: no cover - defensive
        token = None
    return token or None


def tokens_invalidated(user: Any, payload: dict) -> bool:
    """True when the token predates the user's most recent credential change.

    Setting ``User.tokens_valid_from`` (password reset, "log out everywhere")
    invalidates every token issued before that instant. Because the user
    document is already loaded on each authenticated request, this costs
    nothing extra — no per-request denylist lookup, no Redis dependency in the
    authentication path.
    """
    cutoff = ensure_utc(getattr(user, "tokens_valid_from", None))
    if cutoff is None:
        return False
    issued_at = payload.get("iat")
    if issued_at is None:
        # A token with no issue time cannot be placed relative to the cutoff,
        # so it is treated as older than it. (decode_token requires `iat`, so
        # this is only reachable for a payload built some other way.)
        return True
    try:
        # Whole seconds on both sides: `iat` has one-second resolution, so a
        # sub-second comparison would reject the token a user gets when they
        # sign in immediately after resetting their password.
        return int(issued_at) < epoch_seconds(cutoff)
    except (TypeError, ValueError):
        return True
