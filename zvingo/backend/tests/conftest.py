"""Shared pytest setup.

`app.config.Settings` requires MONGODB_URL and REDIS_URL and is instantiated at
import time, so without them every module fails to collect. Defaults are
supplied here; a real value in the environment always wins, which keeps
integration runs possible.

**Redis is genuinely touched.** Most collaborators are faked per test, but the
rate limiter, the geocode cache and the SSE ticket store all talk to the real
`REDIS_URL`. That made the suite non-hermetic in two ways that both showed up
as failing *security* tests:

* `test_the_reset_token_never_appears_in_the_response_body` is parametrised, and
  both parametrisations shared one `rate_limit:password_reset:ip:unknown`
  budget, so the second run of the pair was rate-limited by the first.
* Anything else using the same Redis -- a dev server, a second suite run inside
  the same hour -- consumed the same budgets and failed the suite.

A flaky security test is worse than no test, because people learn to ignore it.
So the suite defaults to its own Redis database, and the fixture below clears
the specific prefixes the app writes before every test. Deletion is by prefix
rather than FLUSHDB so that pointing REDIS_URL at a shared instance cannot
destroy anything that is not ours.
"""

import os

os.environ.setdefault("MONGODB_URL", "mongodb://localhost:27017/zvingo_test")
# db 15, not db 0: keep the suite off whatever a dev server is using.
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/15")
os.environ.setdefault("ENVIRONMENT", "development")

import pytest  # noqa: E402

#: Key prefixes the application writes to Redis. Anything stateful the suite
#: could inherit from a previous run or a parallel process belongs here.
_STATEFUL_PREFIXES = (
    "rate_limit:",
    "geocode:",
    "sse_ticket:",
    "otp:",
    "refresh:",
    "driver_pending_offer_",
    "driver:",
)


@pytest.fixture(autouse=True)
def _isolate_redis_state():
    """Clear the app's Redis keys before each test.

    Best effort: if Redis is not running the suite still works, because every
    caller of it already tolerates an unavailable cache.
    """
    try:
        import redis

        client = redis.from_url(os.environ["REDIS_URL"], decode_responses=True)
        for prefix in _STATEFUL_PREFIXES:
            keys = list(client.scan_iter(match=f"{prefix}*", count=500))
            if keys:
                client.delete(*keys)
        client.close()
    except Exception:
        pass
    yield
