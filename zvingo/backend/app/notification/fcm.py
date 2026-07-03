import structlog
from typing import Optional
from app.config import settings

logger = structlog.get_logger()

_fcm_initialized = False


def init_firebase():
    global _fcm_initialized
    if _fcm_initialized:
        return

    creds_path = settings.FIREBASE_CREDENTIALS_PATH
    if not creds_path:
        logger.info("Firebase not configured (no FIREBASE_CREDENTIALS_PATH)")
        return

    try:
        import firebase_admin
        from firebase_admin import credentials
        cred = credentials.Certificate(creds_path)
        firebase_admin.initialize_app(cred)
        _fcm_initialized = True
        logger.info("Firebase initialized successfully")
    except ImportError:
        logger.warning("firebase-admin not installed, FCM disabled")
    except Exception as e:
        logger.error("Firebase init failed", error=str(e))


async def send_push_notification(fcm_token: str, title: str, body: str, data: Optional[dict] = None) -> bool:
    if not _fcm_initialized:
        logger.info("FCM not available, logging notification", title=title, body=body, token=fcm_token[:20] + "...")
        return False

    try:
        from firebase_admin import messaging
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data or {},
            token=fcm_token,
        )
        response = messaging.send(message)
        logger.info("FCM sent", response=response)
        return True
    except Exception as e:
        logger.error("FCM send failed", error=str(e))
        return False
