"""Redis sliding-window rate limiting.

The window is a Redis sorted set keyed by subject, holding one member per
request scored by its timestamp. Trimming, counting and admitting have to
happen as one indivisible step — doing them as three round trips lets N
concurrent requests each read a count below the limit and then all insert,
so the real ceiling becomes ``limit + concurrency``. :data:`_SLIDING_WINDOW_LUA`
performs the whole decision inside Redis, which is single-threaded, so the
check is atomic without a distributed lock.

There is no module-level limiter instance: a cached client captured on the
first request outlives Redis failovers and cannot be swapped in a test.
Construct :class:`RateLimiter` with the client you already have — it is a thin
wrapper and costs nothing.
"""

import time
import uuid
from typing import Optional, Tuple

import redis.asyncio as aioredis
import structlog

from app.config import settings

logger = structlog.get_logger()

# KEYS[1] = zset key
# ARGV[1] = now (seconds)  ARGV[2] = window (seconds)
# ARGV[3] = limit          ARGV[4] = unique member id
# Returns {allowed (0|1), count_in_window, retry_after_seconds}
_SLIDING_WINDOW_LUA = """
local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])
local member = ARGV[4]

redis.call('ZREMRANGEBYSCORE', key, 0, now - window)
local count = redis.call('ZCARD', key)
if count >= limit then
  local oldest = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
  local retry = window
  if oldest[2] then
    retry = math.ceil((tonumber(oldest[2]) + window) - now)
    if retry < 1 then retry = 1 end
  end
  return {0, count, retry}
end
redis.call('ZADD', key, now, member)
redis.call('EXPIRE', key, window + 10)
return {1, count + 1, 0}
"""


class RateLimitResult:
    """Outcome of one rate-limit decision."""

    __slots__ = ("allowed", "count", "limit", "window", "retry_after")

    def __init__(
        self,
        allowed: bool,
        count: int,
        limit: int,
        window: int,
        retry_after: int = 0,
    ) -> None:
        self.allowed = allowed
        self.count = count
        self.limit = limit
        self.window = window
        self.retry_after = retry_after

    @property
    def message(self) -> Optional[str]:
        if self.allowed:
            return None
        return (
            f"Rate limited: max {self.limit} requests per {self.window}s. "
            f"Retry in {self.retry_after}s."
        )

    def __bool__(self) -> bool:  # pragma: no cover - convenience
        return self.allowed


class RateLimiter:
    """Sliding-window limiter over a Redis client.

    Construct one per request with whatever client is at hand::

        limiter = RateLimiter(redis)
        result = await limiter.check("login:ip:1.2.3.4", limit=10, window=300)
        if not result.allowed:
            raise HTTPException(429, result.message,
                                headers={"Retry-After": str(result.retry_after)})
    """

    def __init__(self, redis_client: aioredis.Redis):
        self.redis = redis_client
        self.location_limit = settings.LOCATION_UPDATE_RATE_LIMIT
        self.location_window = settings.LOCATION_UPDATE_WINDOW_SECONDS

    async def check(self, key: str, limit: int, window: int) -> RateLimitResult:
        """Admit or reject one request against ``key``.

        Fails **open** — if Redis is unreachable the request is allowed and the
        failure is logged. A rate limiter is a availability control, not an
        authorization control; taking the whole platform down because the
        counter store blinked would be the worse outcome. Authorization
        decisions never depend on this path.
        """
        now = int(time.time())
        try:
            raw = await self._evaluate(key, now, limit, window)
        except Exception as exc:
            logger.error(
                "rate_limiter_unavailable",
                rate_limit_key=key,
                error=str(exc),
                error_type=type(exc).__name__,
            )
            return RateLimitResult(True, 0, limit, window)

        allowed, count, retry_after = raw
        if not allowed:
            logger.warning(
                "rate_limited",
                rate_limit_key=key,
                limit=limit,
                window_seconds=window,
                retry_after=retry_after,
            )
        return RateLimitResult(bool(allowed), int(count), limit, window, int(retry_after))

    async def _evaluate(
        self, key: str, now: int, limit: int, window: int
    ) -> Tuple[int, int, int]:
        """Run the atomic window check, falling back only for test doubles."""
        evaluate = getattr(self.redis, "eval", None)
        if callable(evaluate):
            result = await evaluate(
                _SLIDING_WINDOW_LUA, 1, key, now, window, limit, uuid.uuid4().hex
            )
            return int(result[0]), int(result[1]), int(result[2])
        return await self._evaluate_without_scripting(key, now, limit, window)

    async def _evaluate_without_scripting(
        self, key: str, now: int, limit: int, window: int
    ) -> Tuple[int, int, int]:
        """Non-atomic fallback for clients without server-side scripting.

        Only reachable with an in-memory stand-in; every real Redis (and the
        managed offerings) supports EVAL. Kept so a fake client in a unit test
        still exercises the caller's rejection path.
        """
        await self.redis.zremrangebyscore(key, 0, now - window)
        count = await self.redis.zcard(key)
        if count >= limit:
            return 0, int(count), window
        await self.redis.zadd(key, {uuid.uuid4().hex: now})
        await self.redis.expire(key, window + 10)
        return 1, int(count) + 1, 0

    async def check_location_update(self, driver_id: str) -> tuple[bool, Optional[str]]:
        """Rate-limit a driver's location pings.

        Returns ``(allowed, error_message)`` for the existing callers in the
        dispatch router and the BinProto servers.
        """
        result = await self.check(
            f"rate_limit:location:{driver_id}",
            limit=self.location_limit,
            window=self.location_window,
        )
        if result.allowed:
            return True, None
        return False, (
            f"Rate limited: max {self.location_limit} updates "
            f"per {self.location_window}s"
        )
