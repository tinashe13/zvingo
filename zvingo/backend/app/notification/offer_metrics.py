"""Reading the dispatcher's per-driver offer counters.

The driver app's ratings screen shows an acceptance rate. Dispatch already
keeps the numbers it needs — it bumps `offers_sent`, `offers_accepted`,
`offers_declined` and `offers_timed_out` on the Redis hash `driver:{id}` as
part of scoring candidates — so this module *reads* those counters rather than
maintaining a second, divergent set.

Counters are lifetime totals and best-effort: a Redis failure degrades the
acceptance rate to "unknown", it never fails a metrics read.
"""

import redis.asyncio as aioredis
import structlog

from app.config import settings

logger = structlog.get_logger()

#: The hash dispatch writes to, and the fields it maintains.
DRIVER_HASH = "driver:{driver_id}"
OFFER_FIELDS = (
    "offers_sent",
    "offers_accepted",
    "offers_declined",
    "offers_timed_out",
)


def _as_int(value) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return 0


async def offer_stats(driver_id: str) -> dict:
    """Lifetime offer counters for one driver, zeroed when unavailable."""
    empty = {field: 0 for field in OFFER_FIELDS}
    if not driver_id:
        return empty

    client = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        values = await client.hmget(
            DRIVER_HASH.format(driver_id=driver_id), list(OFFER_FIELDS)
        )
        return {field: _as_int(value) for field, value in zip(OFFER_FIELDS, values)}
    except Exception as e:
        logger.warning("Offer counters unavailable", driver_id=driver_id, error=str(e))
        return empty
    finally:
        try:
            await client.close()
        except Exception:
            pass
