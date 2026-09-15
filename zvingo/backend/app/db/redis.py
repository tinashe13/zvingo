"""Redis access helpers.

Modules across the codebase each call ``aioredis.from_url(...)`` and close the
client in a ``finally``. That is correct but noisy, and it makes it easy to
leak a connection on an early return. :func:`redis_client` wraps the same
pattern in an async context manager so a caller cannot forget the close, and
:func:`get_redis_client` remains available for the dependency-injection style
FastAPI routes already use.

Both go through ``aioredis.from_url`` on every call rather than caching a
module-level client: a cached client captured at import time survives failover
badly and is impossible to swap out in a test.
"""

from contextlib import asynccontextmanager
from typing import AsyncIterator

import redis.asyncio as aioredis

from app.config import settings


def get_redis_client(**kwargs) -> aioredis.Redis:
    """A new Redis client bound to ``settings.REDIS_URL``.

    The caller owns the client and must close it — prefer :func:`redis_client`
    unless the lifetime is managed elsewhere (e.g. a FastAPI dependency).
    """
    kwargs.setdefault("decode_responses", True)
    return aioredis.from_url(settings.REDIS_URL, **kwargs)


@asynccontextmanager
async def redis_client(**kwargs) -> AsyncIterator[aioredis.Redis]:
    """Yield a Redis client and close it on the way out, errors included."""
    client = get_redis_client(**kwargs)
    try:
        yield client
    finally:
        # redis>=5 renamed close() to aclose(); support both so the client
        # version is not pinned by this helper.
        closer = getattr(client, "aclose", None) or getattr(client, "close", None)
        if closer is not None:
            try:
                await closer()
            except Exception:  # pragma: no cover - close is best effort
                pass
