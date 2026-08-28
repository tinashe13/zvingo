"""structlog configuration.

Every module calls ``structlog.get_logger()`` at import time; this module wires
up the shared processor chain once at startup so those loggers emit consistent,
context-rich records. Development gets colourised key/value output, production
gets one JSON object per line for log shipping.
"""

import logging
import sys

import structlog

from app.config import settings


def use_json_logs() -> bool:
    """JSON in production (or when explicitly requested), console otherwise."""
    return settings.LOG_JSON or settings.ENVIRONMENT == "production"


def configure_logging() -> None:
    """Configure structlog and the stdlib root logger.

    Safe to call more than once — configuration is idempotent, which matters
    because tests and the ASGI lifespan may both invoke it.
    """
    level = getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO)

    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=level,
        force=True,
    )
    # uvicorn installs its own handlers; let records propagate to the root so
    # access/error logs pick up the same formatting.
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logging.getLogger(name).handlers.clear()
        logging.getLogger(name).propagate = True

    processors = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
    ]
    if use_json_logs():
        processors.append(structlog.processors.JSONRenderer())
    else:
        processors.append(structlog.dev.ConsoleRenderer(colors=False))

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(level),
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
        cache_logger_on_first_use=False,
    )
