"""Prometheus scrape endpoint and the readiness probe."""

import structlog
from fastapi import APIRouter, Header, HTTPException
from fastapi.responses import JSONResponse, PlainTextResponse
from typing import Optional

from app.config import settings
from app.observability import metrics

router = APIRouter()
logger = structlog.get_logger()

CONTENT_TYPE = "text/plain; version=0.0.4; charset=utf-8"


@router.get("/metrics", response_class=PlainTextResponse, include_in_schema=False)
async def scrape(authorization: Optional[str] = Header(default=None)):
    """Expose the metric registry in Prometheus text exposition format.

    Set ``METRICS_TOKEN`` to require ``Authorization: Bearer <token>``; without
    it the endpoint is open, which is fine when nginx keeps ``/metrics`` on the
    internal network only.
    """
    if not settings.METRICS_ENABLED:
        raise HTTPException(status_code=404, detail="Metrics are disabled")

    if settings.METRICS_TOKEN:
        expected = f"Bearer {settings.METRICS_TOKEN}"
        if authorization != expected:
            raise HTTPException(status_code=401, detail="Invalid metrics token")

    return PlainTextResponse(metrics.render(), media_type=CONTENT_TYPE)


@router.get("/ready", include_in_schema=False)
async def readiness():
    """Readiness probe: are the backing stores reachable?

    Distinct from ``/health``, which only proves the process is up. An
    orchestrator should gate traffic on this one so a pod with a dead Mongo
    connection is pulled out of rotation instead of serving 500s.

    The payload is deliberately dull — per-dependency "ok"/"unavailable" and
    nothing else. Connection strings, driver exceptions and hostnames stay in
    the server-side log where they belong.
    """
    checks = {"mongodb": "unavailable", "redis": "unavailable"}

    try:
        from app.db.session import ping_database

        checks["mongodb"] = "ok" if await ping_database() else "unavailable"
    except Exception as exc:
        logger.warning("readiness_mongodb_failed", error=str(exc))

    try:
        from app.db.redis import redis_client

        async with redis_client() as r:
            await r.ping()
        checks["redis"] = "ok"
    except Exception as exc:
        logger.warning("readiness_redis_failed", error=str(exc))

    ready = all(value == "ok" for value in checks.values())
    return JSONResponse(
        status_code=200 if ready else 503,
        content={"status": "ready" if ready else "not_ready", "checks": checks},
    )
