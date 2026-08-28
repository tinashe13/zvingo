from pydantic import model_validator
from pydantic_settings import BaseSettings
from typing import List, Optional

# Placeholder secrets that must never reach production.
KNOWN_INSECURE_SECRETS = {
    "changethis",
    "changeme",
    "secret",
    "generate-a-random-64-char-string-here",
}

class Settings(BaseSettings):
    PROJECT_NAME: str = "Zvingo"
    API_V1_STR: str = "/api/v1"

    # Deployment environment: "development" or "production"
    ENVIRONMENT: str = "development"

    # Database
    MONGODB_URL: str
    MONGODB_DB_NAME: str = "zvingo"

    # Redis
    REDIS_URL: str

    # Security
    SECRET_KEY: str = "changethis"  # MUST change in production (enforced below)
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 8  # 8 days

    # CORS: comma-separated list of allowed origins.
    # Empty => "*" in development, no origins in production.
    CORS_ORIGINS: str = ""

    # SMS
    # SMS_MOCK_MODE=true logs/forwards SMS to a mock gateway instead of
    # Africa's Talking. Must be false in production (enforced below).
    SMS_MOCK_MODE: bool = True
    AFRICASTALKING_USERNAME: Optional[str] = "sandbox"
    AFRICASTALKING_API_KEY: Optional[str] = None
    SMS_GATEWAY_URL: Optional[str] = None

    # Paynow Zimbabwe
    # PAYMENT_MOCK_MODE=true auto-approves payments without contacting Paynow.
    # Must be false in production (enforced below).
    PAYMENT_MOCK_MODE: bool = True
    PAYNOW_INTEGRATION_ID: Optional[str] = None
    PAYNOW_INTEGRATION_KEY: Optional[str] = None
    PAYNOW_RETURN_URL: str = "http://localhost/payment/return"
    PAYNOW_RESULT_URL: str = "http://localhost/api/payment/webhook"

    # Firebase
    FIREBASE_CREDENTIALS_PATH: Optional[str] = None

    # Upload
    UPLOAD_BASE_URL: str = "http://localhost:8000"
    MAX_UPLOAD_SIZE_BYTES: int = 5 * 1024 * 1024  # 5MB

    # Dispatch retry (re-offer stuck orders)
    DISPATCH_RETRY_INTERVAL_SECONDS: int = 120
    DISPATCH_MAX_RETRY_ATTEMPTS: int = 10

    # Scheduled orders — a dedicated poller dispatches them ahead of time so
    # the driver arrives for the requested slot instead of starting then.
    SCHEDULED_POLL_INTERVAL_SECONDS: int = 15
    SCHEDULED_DISPATCH_LEAD_MINUTES: int = 15

    # Observability
    LOG_LEVEL: str = "INFO"
    LOG_JSON: bool = False  # force JSON logs (always on in production)
    METRICS_ENABLED: bool = True
    # When set, GET /metrics requires `Authorization: Bearer <token>`.
    METRICS_TOKEN: Optional[str] = None

    # Alerting — a background monitor emits `alert` log events and publishes
    # them to the Redis `alerts` channel.
    ALERTS_ENABLED: bool = True
    ALERT_POLL_INTERVAL_SECONDS: int = 300
    ALERT_STUCK_ORDER_MINUTES: int = 30
    ALERT_FAILED_PAYMENT_THRESHOLD: int = 5
    ALERT_WINDOW_MINUTES: int = 60
    ALERT_HISTORY_SIZE: int = 100

    # Finance
    DRIVER_SHARE_RATIO: float = 0.85  # driver keeps 85% of delivery fee

    # BinProto
    BINPROTO_UDP_PORT: int = 9090
    BINPROTO_TCP_PORT: int = 9091

    # Rate Limiting
    LOCATION_UPDATE_RATE_LIMIT: int = 30  # Max 30 requests per driver per 60 seconds (3s interval = ~20, with headroom)
    LOCATION_UPDATE_WINDOW_SECONDS: int = 60

    # Dev: default restaurant location behavior
    DEV_ALLOW_ADMIN_ENDPOINTS: bool = False
    DEV_FORCE_DEFAULT_RESTAURANT_LOCATION: bool = False
    DEV_DEFAULT_BASE_LAT: float = 37.4219983
    DEV_DEFAULT_BASE_LNG: float = -122.084
    DEV_DEFAULT_OFFSET_MILES: float = 5.0

    model_config = {"env_file": ".env"}

    @property
    def cors_origins(self) -> List[str]:
        """Parsed list of allowed CORS origins.

        Falls back to permissive "*" only in development; in production an
        explicit CORS_ORIGINS list must be provided (empty otherwise).
        """
        if self.CORS_ORIGINS:
            return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]
        if self.ENVIRONMENT == "development":
            return ["*"]
        return []

    @model_validator(mode="after")
    def _enforce_production_safety(self) -> "Settings":
        """Refuse to start with insecure/mock configuration in production."""
        if self.ENVIRONMENT != "production":
            return self

        errors = []
        if not self.SECRET_KEY or self.SECRET_KEY in KNOWN_INSECURE_SECRETS:
            errors.append(
                "SECRET_KEY is missing or set to a known default; "
                "generate a strong random value (e.g. `openssl rand -hex 32`)"
            )
        if self.PAYMENT_MOCK_MODE:
            errors.append("PAYMENT_MOCK_MODE must be false in production")
        if not (self.PAYNOW_INTEGRATION_ID and self.PAYNOW_INTEGRATION_KEY):
            errors.append(
                "PAYNOW_INTEGRATION_ID and PAYNOW_INTEGRATION_KEY are required in production"
            )
        if self.SMS_MOCK_MODE:
            errors.append("SMS_MOCK_MODE must be false in production")
        if not self.AFRICASTALKING_API_KEY:
            errors.append("AFRICASTALKING_API_KEY is required in production")

        if errors:
            raise ValueError(
                "Refusing to start with ENVIRONMENT=production: " + "; ".join(errors)
            )
        return self

settings = Settings()
