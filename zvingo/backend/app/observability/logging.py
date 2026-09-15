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


# Keys whose values must never reach a log sink, matched case-insensitively as
# substrings so `hashed_password`, `X-Api-Key` and `refresh_token` are all
# caught by the short entries below.
SENSITIVE_KEY_PARTS = (
    "password",
    "secret",
    "token",
    "authorization",
    "api_key",
    "apikey",
    "credential",
    "otp",
    "pin",
    "signature",
    "cookie",
    "session_key",
)

REDACTED = "[redacted]"

# Structural keys that are named "token"-ish but carry no secret.
SAFE_KEYS = {"token_type", "fcm_token_present", "has_token", "token_expired"}


def _is_sensitive(key: str) -> bool:
    lowered = key.lower()
    if lowered in SAFE_KEYS:
        return False
    return any(part in lowered for part in SENSITIVE_KEY_PARTS)


def redact_secrets(_logger, _method, event_dict):
    """structlog processor: replace secret-looking values before rendering.

    Runs on every record, including ones bound by contextvars, so a caller
    cannot leak a credential by accident — `logger.info("x", password=p)`
    emits `password='[redacted]'`. Nested dicts and lists are walked because
    request payloads are usually logged whole.
    """

    def scrub(value, depth=0):
        if depth > 6:
            return value
        if isinstance(value, dict):
            return {
                k: (REDACTED if isinstance(k, str) and _is_sensitive(k) else scrub(v, depth + 1))
                for k, v in value.items()
            }
        if isinstance(value, (list, tuple)):
            return type(value)(scrub(v, depth + 1) for v in value)
        return value

    for key in list(event_dict.keys()):
        if isinstance(key, str) and _is_sensitive(key):
            event_dict[key] = REDACTED
        else:
            event_dict[key] = scrub(event_dict[key])
    return event_dict


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
        redact_secrets,
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
