"""Firebase Cloud Messaging, with an explicit "not configured" mode.

Push is optional infrastructure: the platform must run without Firebase
credentials (local dev, CI, a deployment that has not onboarded FCM yet) and
it must be *obvious* that it is running that way. So:

* `init_firebase()` records why FCM is unavailable instead of failing startup.
* `send_push_notification()` never raises; it returns False and increments a
  counter, so "no pushes are arriving" shows up in `/metrics` and the logs
  rather than as silence.
* the blocking `firebase_admin` send runs on a worker thread, because calling
  it inline would stall the event loop for every other request.
"""

import asyncio
from typing import Optional

import structlog

from app.config import settings

logger = structlog.get_logger()

_fcm_initialized = False
#: Why FCM is unavailable — surfaced by `fcm_status()` and the health payload.
_fcm_status = "uninitialised"

#: Counters so a silently-disabled push channel is still measurable.
_counters = {"sent": 0, "failed": 0, "skipped": 0}


def fcm_status() -> dict:
    """Current push-delivery state, for diagnostics and the admin dashboard."""
    return {
        "available": _fcm_initialized,
        "reason": _fcm_status,
        "sent": _counters["sent"],
        "failed": _counters["failed"],
        "skipped": _counters["skipped"],
    }


def init_firebase() -> bool:
    """Initialise firebase-admin if it is configured. Never raises."""
    global _fcm_initialized, _fcm_status
    if _fcm_initialized:
        return True

    creds_path = settings.FIREBASE_CREDENTIALS_PATH
    if not creds_path:
        _fcm_status = "FIREBASE_CREDENTIALS_PATH is not set"
        logger.warning(
            "Push notifications disabled — FIREBASE_CREDENTIALS_PATH is not set. "
            "Order updates and driver offers will be delivered over SSE only.",
        )
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(creds_path)
        firebase_admin.initialize_app(cred)
        _fcm_initialized = True
        _fcm_status = "ready"
        logger.info("Firebase initialized successfully")
        return True
    except ImportError:
        _fcm_status = "firebase-admin package is not installed"
        logger.warning("firebase-admin not installed, FCM disabled")
    except Exception as e:
        _fcm_status = f"initialisation failed: {e}"
        logger.error("Firebase init failed", error=str(e))
    return False


def _send_blocking(fcm_token: str, title: str, body: str, data: Optional[dict]):
    """The synchronous firebase-admin call, run off the event loop."""
    from firebase_admin import messaging

    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},
        token=fcm_token,
    )
    return messaging.send(message)


async def send_push_notification(
    fcm_token: Optional[str], title: str, body: str, data: Optional[dict] = None
) -> bool:
    """Deliver one push. Returns False (never raises) when it cannot be sent."""
    if not fcm_token:
        _counters["skipped"] += 1
        logger.debug("Push skipped — no FCM token", title=title)
        return False

    if not _fcm_initialized:
        _counters["skipped"] += 1
        logger.info(
            "Push not delivered — FCM unavailable",
            reason=_fcm_status,
            title=title,
            body=body,
            token_prefix=str(fcm_token)[:12],
            skipped_total=_counters["skipped"],
        )
        return False

    try:
        response = await asyncio.to_thread(
            _send_blocking, fcm_token, title, body, data
        )
        _counters["sent"] += 1
        logger.info("FCM sent", response=response)
        return True
    except Exception as e:
        _counters["failed"] += 1
        logger.error("FCM send failed", error=str(e), failed_total=_counters["failed"])
        return False
