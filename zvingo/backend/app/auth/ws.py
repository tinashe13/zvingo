"""JWT authentication for WebSocket handshakes.

A WebSocket has no dependency-injection story in FastAPI the way an HTTP route
does, so the authentication has to happen as the first statement of the
handler. This module makes that one line, and makes it correct.

Use :func:`authenticate_websocket`. It validates the token, loads the user,
enforces "the socket belongs to the principal it claims", closes the socket
with a policy-violation code on any failure, and returns a :class:`WSPrincipal`
on success::

    @router.websocket("/ws/driver/{driver_id}")
    async def driver_ws(websocket: WebSocket, driver_id: str):
        principal = await authenticate_websocket(
            websocket, expected_user_id=driver_id, roles=(Role.DRIVER,)
        )
        if principal is None:
            return                      # already closed, nothing else to do
        await websocket.accept()
        ...                             # use principal.user_id, never driver_id

Note the last line: once authenticated, derive everything from
``principal.user_id``. Path parameters are attacker-controlled; the principal
is not. ``expected_user_id`` is what binds the two together, and passing it is
what stops one driver from opening another driver's channel.

Tokens are read from ``?token=`` or an ``Authorization: Bearer`` header —
browsers cannot set headers on a WebSocket handshake, so the query form has to
be supported. Query strings land in proxy access logs, so keep access-token
lifetimes short (``ACCESS_TOKEN_EXPIRE_MINUTES``).
"""

from dataclasses import dataclass
from typing import Any, Iterable, Optional

import structlog

from app.auth.tokens import ACCESS_TOKEN_TYPE, TokenError, decode_token

logger = structlog.get_logger()

# RFC 6455 close codes used here.
WS_POLICY_VIOLATION = 1008  # unauthenticated, wrong principal, wrong role
WS_INTERNAL_ERROR = 1011


def token_from_websocket(websocket) -> Optional[str]:
    """Pull the bearer token off a WebSocket handshake, if present."""
    token = None
    try:
        token = websocket.query_params.get("token")
    except Exception:  # pragma: no cover - defensive against odd scopes
        token = None
    if not token:
        try:
            auth_header = websocket.headers.get("authorization", "") or ""
        except Exception:  # pragma: no cover - defensive
            auth_header = ""
        if auth_header.lower().startswith("bearer "):
            token = auth_header[7:].strip()
    return token or None


def authenticate_ws(websocket) -> Optional[str]:
    """Return the authenticated user id for a WebSocket, or ``None``.

    Signature-and-claims only: no database round trip, so it cannot see a
    deactivated account or a token superseded by a password reset. Prefer
    :func:`authenticate_websocket`, which does both and closes the socket for
    you; this stays for callers that only need the subject.
    """
    token = token_from_websocket(websocket)
    if not token:
        return None
    try:
        payload = decode_token(token, ACCESS_TOKEN_TYPE)
    except TokenError:
        return None
    return payload.get("sub")


@dataclass(frozen=True)
class WSPrincipal:
    """The authenticated identity bound to one WebSocket connection."""

    user: Any
    user_id: str
    role: str

    def owns(self, other_id: Any) -> bool:
        """True when ``other_id`` names this principal."""
        return other_id is not None and str(other_id) == self.user_id


async def _reject(websocket, event: str, **fields) -> None:
    logger.warning(event, **fields)
    try:
        await websocket.close(code=WS_POLICY_VIOLATION)
    except Exception:  # pragma: no cover - socket may already be gone
        pass


async def authenticate_websocket(
    websocket,
    *,
    expected_user_id: Optional[str] = None,
    roles: Optional[Iterable[str]] = None,
    load_user: bool = True,
) -> Optional[WSPrincipal]:
    """Authenticate a handshake and bind the socket to a principal.

    On failure the socket is closed with 1008 and ``None`` is returned — the
    handler should ``return`` immediately. On success the caller still owns the
    ``accept()``.

    ``expected_user_id``
        The id the connection claims (usually a path parameter). The handshake
        is rejected unless it matches the token subject.
    ``roles``
        Optional allow-list of ``User.role`` values.
    ``load_user``
        Load and re-validate the user document (default). Turning it off skips
        the deactivation and credential-cutoff checks, so only do that for a
        channel where the token subject alone is enough.
    """
    token = token_from_websocket(websocket)
    if not token:
        await _reject(websocket, "ws_auth_rejected", reason="missing_token")
        return None

    try:
        payload = decode_token(token, ACCESS_TOKEN_TYPE)
    except TokenError as exc:
        await _reject(websocket, "ws_auth_rejected", reason="invalid_token", error=str(exc))
        return None

    user_id = str(payload["sub"])
    role = payload.get("role") or ""
    user = None

    if load_user:
        from app.auth.models import User
        from app.auth.principals import tokens_invalidated

        try:
            user = await User.get(user_id)
        except Exception as exc:
            logger.error("ws_auth_user_lookup_failed", user_id=user_id, error=str(exc))
            try:
                await websocket.close(code=WS_INTERNAL_ERROR)
            except Exception:  # pragma: no cover - socket may already be gone
                pass
            return None
        if user is None or not getattr(user, "is_active", False):
            await _reject(
                websocket, "ws_auth_rejected", reason="unknown_or_inactive_user", user_id=user_id
            )
            return None
        if tokens_invalidated(user, payload):
            await _reject(
                websocket, "ws_auth_rejected", reason="token_superseded", user_id=user_id
            )
            return None
        role = getattr(user, "role", role) or role

    if expected_user_id is not None and str(expected_user_id) != user_id:
        await _reject(
            websocket,
            "ws_auth_rejected",
            reason="principal_mismatch",
            user_id=user_id,
            requested_id=str(expected_user_id),
        )
        return None

    if roles is not None and role not in tuple(roles):
        await _reject(
            websocket,
            "ws_auth_rejected",
            reason="role_not_permitted",
            user_id=user_id,
            role=role,
        )
        return None

    structlog.contextvars.bind_contextvars(user_id=user_id, user_role=role)
    return WSPrincipal(user=user, user_id=user_id, role=role)
