"""Rolling per-driver delivery-offer counters.

The driver app's ratings screen shows an acceptance rate. Acceptances are
derivable from orders (an assigned order *is* an accepted offer), but offers
are not stored anywhere — they are pushed and forgotten. This module keeps one
small counter per driver per day in Redis so the rate can be computed over a
rolling window.

Counters are best-effort: a Redis failure degrades the acceptance rate to
"unknown", it never fails an offer or a metrics read.
"""

from datetime import timedelta

import redis.asyncio as aioredis
import structlog

from app.config import settings
from app.time_utils import utc_now

logger = structlog.get_logger()

#: Keep a few days more than the reporting window so a 30-day read is complete.
COUNTER_TTL_DAYS = 35


def _key(driver_id: str, day: str) -> str:
    return f"driver_offers:{driver_id}:{day}"


def _day(offset: int = 0) -> str:
    return (utc_now() - timedelta(days=offset)).strftime("%Y%m%d")


async def record_offer(driver_id: str) -> None:
    """Count one delivery offer pushed to this driver."""
    if not driver_id:
        return
    client = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        key = _key(driver_id, _day())
        await client.incr(key)
        await client.expire(key, COUNTER_TTL_DAYS * 24 * 3600)
    except Exception as e:
        logger.warning("Offer counter write failed", driver_id=driver_id, error=str(e))
    finally:
        try:
            await client.close()
        except Exception:
            pass


async def offers_sent(driver_id: str, days: int = 30) -> int:
    """Total offers pushed to this driver over the last `days` days."""
    if not driver_id:
        return 0
    client = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        keys = [_key(driver_id, _day(offset)) for offset in range(max(days, 1))]
        values = await client.mget(keys)
        return sum(int(v) for v in values if v)
    except Exception as e:
        logger.warning("Offer counter read failed", driver_id=driver_id, error=str(e))
        return 0
    finally:
        try:
            await client.close()
        except Exception:
            pass
