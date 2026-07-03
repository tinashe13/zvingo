import httpx
import structlog
from app.config import settings

logger = structlog.get_logger()


class SMSGateway:
    """SMS delivery via Africa's Talking, with an explicit mock mode.

    Mock mode is controlled by the SMS_MOCK_MODE setting (default true in
    development). Settings validation refuses to start in production with
    mock mode on or missing Africa's Talking credentials; this class
    re-checks as a defense-in-depth guard.
    """

    BASE_URL = "https://api.africastalking.com/version1/messaging"
    SANDBOX_URL = "https://api.sandbox.africastalking.com/version1/messaging"

    def __init__(self):
        self.mock_mode = settings.SMS_MOCK_MODE
        self.username = settings.AFRICASTALKING_USERNAME
        self.api_key = settings.AFRICASTALKING_API_KEY
        self.base_url = self.SANDBOX_URL if self.username == "sandbox" else self.BASE_URL

        if self.mock_mode:
            if settings.ENVIRONMENT == "production":
                # Defense in depth: Settings already blocks this combination.
                raise RuntimeError("SMS_MOCK_MODE must not be enabled in production")
            logger.warning(
                "SMS gateway initialized in MOCK mode - messages are not delivered. "
                "Set SMS_MOCK_MODE=false with Africa's Talking credentials for real SMS."
            )
        elif not self.api_key:
            raise RuntimeError(
                "SMS_MOCK_MODE is false but AFRICASTALKING_API_KEY is not configured"
            )

    async def send_sms(self, to: str, message: str) -> bool:
        if self.mock_mode:
            return await self._send_mock(to, message)
        return await self._send_africastalking(to, message)

    async def _send_mock(self, to: str, message: str) -> bool:
        """Development-only path: forward to a local mock gateway or just log."""
        if settings.SMS_GATEWAY_URL:
            try:
                async with httpx.AsyncClient() as client:
                    resp = await client.post(
                        f"{settings.SMS_GATEWAY_URL}/send",
                        json={"to": to, "message": message},
                    )
                    logger.info("Mock SMS sent", to=to, status=resp.status_code)
                    return True
            except Exception as e:
                logger.error("Failed to send Mock SMS", error=str(e))
                return False

        logger.info("Mock SMS (logged only)", to=to, message=message)
        return True

    async def _send_africastalking(self, to: str, message: str) -> bool:
        """Production path: deliver via Africa's Talking API."""
        headers = {
            "ApiKey": self.api_key,
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        }

        data = {
            "username": self.username,
            "to": to,
            "message": message,
        }

        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(self.base_url, data=data, headers=headers)
                response.raise_for_status()
                logger.info("SMS sent", to=to, response=response.json())
                return True
        except Exception as e:
            logger.error("SMS send failed", error=str(e))
            return False


sms_gateway = SMSGateway()
