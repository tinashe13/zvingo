"""JWT authentication for WebSocket handshakes.

WebSocket clients cannot always set an Authorization header, so the token is
accepted from a `token` query parameter as well. Unlike the HTTP dependency
this returns None instead of raising — the caller decides which close code to
send.
"""

from typing import Optional

from jose import JWTError, jwt

from app.config import settings


def token_from_websocket(websocket) -> Optional[str]:
    """Pull the bearer token off a WebSocket handshake, if present."""
    token = websocket.query_params.get("token")
    if not token:
        auth_header = websocket.headers.get("authorization", "")
        if auth_header.lower().startswith("bearer "):
            token = auth_header[7:]
    return token or None


def authenticate_ws(websocket) -> Optional[str]:
    """Return the authenticated user id for a WebSocket, or None."""
    token = token_from_websocket(websocket)
    if not token:
        return None
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        return payload.get("sub")
    except JWTError:
        return None
