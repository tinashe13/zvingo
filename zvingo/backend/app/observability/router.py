"""Prometheus scrape endpoint."""

from fastapi import APIRouter, Header, HTTPException
from fastapi.responses import PlainTextResponse
from typing import Optional

from app.config import settings
from app.observability import metrics

router = APIRouter()

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
