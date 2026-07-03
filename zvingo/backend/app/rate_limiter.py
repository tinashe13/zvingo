"""
Redis-based rate limiter for API endpoints.
Uses sliding window counter algorithm for accurate per-driver rate limiting.
"""

import time
from typing import Optional
import redis.asyncio as aioredis
import structlog
from app.config import settings

logger = structlog.get_logger()


class RateLimiter:
    def __init__(self, redis_client: aioredis.Redis):
        self.redis = redis_client
        self.location_limit = settings.LOCATION_UPDATE_RATE_LIMIT
        self.location_window = settings.LOCATION_UPDATE_WINDOW_SECONDS

    async def check_location_update(self, driver_id: str) -> tuple[bool, Optional[str]]:
        """
        Check if driver is within rate limit for location updates.

        Returns:
            (allowed: bool, error_message: Optional[str])
            - (True, None) if request is allowed
            - (False, "Rate limited") if request exceeds limit
        """
        key = f"rate_limit:location:{driver_id}"
        current_time = int(time.time())
        window_start = current_time - self.location_window

        try:
            # Remove old entries outside the window
            await self.redis.zremrangebyscore(key, 0, window_start)

            # Count requests in current window
            request_count = await self.redis.zcard(key)

            if request_count >= self.location_limit:
                return False, f"Rate limited: max {self.location_limit} updates per {self.location_window}s"

            # Add current request
            await self.redis.zadd(key, {str(current_time): current_time})

            # Set expiry to window size (auto-cleanup)
            await self.redis.expire(key, self.location_window + 10)

            return True, None

        except Exception as e:
            # On Redis error, allow request but log it
            # Better to track location with degraded rate limiting than fail
            logger.error("Rate limiter error", driver_id=driver_id, error=str(e))
            return True, None


# Global rate limiter instance
_limiter: Optional[RateLimiter] = None


async def get_rate_limiter(redis_client: aioredis.Redis) -> RateLimiter:
    """Get or initialize the global rate limiter."""
    global _limiter
    if _limiter is None:
        _limiter = RateLimiter(redis_client)
    return _limiter
