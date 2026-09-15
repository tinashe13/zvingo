"""Application settings, with hard production safety gates.

Everything the process needs is read from the environment exactly once, at
import time. A misconfigured production deployment must never start: the
``_enforce_production_safety`` validator below refuses to build ``Settings``
when a known-insecure secret, a mock payment/SMS gateway, a wildcard CORS
policy or a dev-only escape hatch is still enabled. Each message names the
offending environment variable so the failure is actionable from a container
log alone.
"""

from pydantic import model_validator
from pydantic_settings import BaseSettings
from typing import List, Optional
from urllib.parse import urlparse

# Placeholder secrets that must never reach production. Compared
# case-insensitively after stripping surrounding whitespace and quotes.
KNOWN_INSECURE_SECRETS = {
    "changethis",
    "changeme",
    "change-me",
    "secret",
    "secretkey",
    "secret_key",
    "supersecret",
    "super-secret",
    "password",
    "test",
    "testing",
    "dev",
    "development",
    "zvingo",
    "generate-a-random-64-char-string-here",
    "your-secret-key",
    "your-secret-key-here",
    "insecure",
    "0123456789abcdef",
}

# A production signing key must be at least this long and carry at least this
# many distinct characters. The distinctness floor is what rejects padded
# placeholders such as "x" * 64, which are long but have no entropy at all.
MIN_SECRET_KEY_LENGTH = 32
MIN_SECRET_KEY_DISTINCT_CHARS = 12


def _normalise_secret(value: str) -> str:
    return (value or "").strip().strip("'\"").lower()


def secret_key_problem(secret: str) -> Optional[str]:
    """Why ``secret`` is unfit for signing production tokens, or None.

    Kept as a module-level function so the same rule can be asserted in tests
    and reused by any future key-rotation tooling.
    """
    if not secret or not secret.strip():
        return "is empty"
    normalised = _normalise_secret(secret)
    if normalised in KNOWN_INSECURE_SECRETS:
        return "is a well-known placeholder value"
    if len(secret) < MIN_SECRET_KEY_LENGTH:
        return f"is only {len(secret)} characters (minimum {MIN_SECRET_KEY_LENGTH})"
    if len(set(secret)) < MIN_SECRET_KEY_DISTINCT_CHARS:
        return (
            f"has only {len(set(secret))} distinct characters "
            f"(minimum {MIN_SECRET_KEY_DISTINCT_CHARS}) — it looks like padding, "
            "not a random key"
        )
    return None


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
    # Refresh tokens are long-lived but single-use: every refresh rotates the
    # token and revokes its predecessor (see app/auth/tokens.py).
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30
    # `iss` claim minted into, and required of, every token this service issues.
    JWT_ISSUER: str = "zvingo"

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
    # Uploads accepted per user per window. Stops an authenticated account
    # being used to fill the disk.
    UPLOAD_RATE_LIMIT: int = 30
    UPLOAD_RATE_WINDOW_SECONDS: int = 300

    # Dispatch retry (re-offer stuck orders)
    DISPATCH_RETRY_INTERVAL_SECONDS: int = 120
    DISPATCH_MAX_RETRY_ATTEMPTS: int = 10

    # Dispatch engine. app/dispatch/service.py reads these through a helper that
    # falls back to the same defaults, so the engine still runs if a value is
    # absent — but they belong here so they are tunable per environment and show
    # up in the settings surface like everything else.
    #: Seconds a driver has to answer an offer before it moves to the next driver.
    DISPATCH_OFFER_TIMEOUT_SECONDS: int = 45
    #: Drivers who see one order at once. 1 = strictly sequential offers.
    DISPATCH_OFFER_FANOUT: int = 1
    #: How often the sweep expires lapsed offers.
    DISPATCH_OFFER_SWEEP_SECONDS: int = 5
    #: Radius of the driver geo search around the pickup point.
    DISPATCH_SEARCH_RADIUS_KM: float = 5.0
    #: Upper bound on candidates pulled from Redis in one search.
    DISPATCH_MAX_CANDIDATES: int = 50
    #: Deliveries a driver may hold before dispatch stops offering them work.
    DISPATCH_MAX_CONCURRENT_DELIVERIES: int = 2
    #: A driver idle this long scores maximum fairness in the offer ranking.
    DISPATCH_FAIRNESS_WINDOW_SECONDS: int = 900
    #: A GPS ping older than this makes a driver look unreachable.
    DISPATCH_LOCATION_STALE_SECONDS: int = 120
    #: Orders processed per sweep pass.
    DISPATCH_SWEEP_BATCH_SIZE: int = 200
    #: Scheduled orders released per poll pass.
    SCHEDULED_RELEASE_BATCH_SIZE: int = 200

    # Scheduled orders — a dedicated poller dispatches them ahead of time so
    # the driver arrives for the requested slot instead of starting then.
    SCHEDULED_POLL_INTERVAL_SECONDS: int = 15
    SCHEDULED_DISPATCH_LEAD_MINUTES: int = 15

    # Geocoding. Nominatim's usage policy requires a User-Agent that identifies
    # the application AND gives them someone to contact before they block you.
    # Unset is legal but means the first warning is the ban.
    NOMINATIM_CONTACT_EMAIL: Optional[str] = None

    # Observability
    LOG_LEVEL: str = "INFO"
    LOG_JSON: bool = False  # force JSON logs (always on in production)
    METRICS_ENABLED: bool = True
    # When set, GET /metrics requires `Authorization: Bearer <token>`.
    # Required in production whenever METRICS_ENABLED is true.
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

    # Delivery fee model: the fee is charged in blocks of distance, so a trip is
    # priced per started block rather than per exact kilometre.
    DELIVERY_BLOCK_SIZE_KM: float = 5.0
    DELIVERY_BLOCK_PRICE_USD: float = 5.00

    # Who absorbs a promo discount. "platform" means Zvingo funds it and the
    # merchant is still paid in full; "merchant" deducts it from the merchant
    # payout. This is a commercial decision, not a technical default — it
    # changes who loses money on every discounted order.
    PROMO_DISCOUNT_FUNDED_BY: str = "platform"

    # Exchange rates older than this are refused rather than used to price an
    # order. In a volatile-currency market, charging at a stale rate is charging
    # at a guess.
    EXCHANGE_RATE_MAX_AGE_SECONDS: int = 6 * 60 * 60

    # BinProto
    BINPROTO_UDP_PORT: int = 9090
    BINPROTO_TCP_PORT: int = 9091

    # Rate Limiting
    LOCATION_UPDATE_RATE_LIMIT: int = 30  # Max 30 requests per driver per 60 seconds (3s interval = ~20, with headroom)
    LOCATION_UPDATE_WINDOW_SECONDS: int = 60

    # Credential-stuffing / OTP-brute-force defences. Each limit is
    # "attempts per window", counted per client IP *and* per identifier.
    LOGIN_RATE_LIMIT: int = 10
    LOGIN_RATE_WINDOW_SECONDS: int = 300
    REGISTER_RATE_LIMIT: int = 5
    REGISTER_RATE_WINDOW_SECONDS: int = 3600
    OTP_REQUEST_RATE_LIMIT: int = 5
    OTP_REQUEST_RATE_WINDOW_SECONDS: int = 900
    OTP_VERIFY_RATE_LIMIT: int = 10
    OTP_VERIFY_RATE_WINDOW_SECONDS: int = 900
    PASSWORD_RESET_RATE_LIMIT: int = 5
    PASSWORD_RESET_RATE_WINDOW_SECONDS: int = 3600
    # A single OTP may be guessed this many times before it is burned.
    OTP_MAX_ATTEMPTS: int = 5
    OTP_TTL_SECONDS: int = 300
    # Password reset tokens are short-lived by design — 15 minutes is long
    # enough to receive an SMS and short enough to limit exposure.
    PASSWORD_RESET_TTL_SECONDS: int = 900

    # Security response headers (main.py). Disable only for local debugging.
    SECURITY_HEADERS_ENABLED: bool = True
    HSTS_MAX_AGE_SECONDS: int = 31536000  # 1 year

    # Dev: default restaurant location behavior
    DEV_ALLOW_ADMIN_ENDPOINTS: bool = False
    DEV_FORCE_DEFAULT_RESTAURANT_LOCATION: bool = False
    DEV_DEFAULT_BASE_LAT: float = 37.4219983
    DEV_DEFAULT_BASE_LNG: float = -122.084
    DEV_DEFAULT_OFFSET_MILES: float = 5.0

    model_config = {"env_file": ".env"}

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.strip().lower() == "production"

    @property
    def cors_origins(self) -> List[str]:
        """Parsed list of allowed CORS origins.

        Falls back to permissive "*" only in development; in production an
        explicit CORS_ORIGINS list must be provided (empty otherwise), and a
        wildcard entry is rejected outright by the validator below.
        """
        if self.CORS_ORIGINS:
            origins = [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]
            if self.is_production:
                return [o for o in origins if o != "*"]
            return origins
        if self.ENVIRONMENT == "development":
            return ["*"]
        return []

    @model_validator(mode="after")
    def _enforce_production_safety(self) -> "Settings":
        """Refuse to start with insecure/mock configuration in production."""
        if not self.is_production:
            return self

        errors = []

        problem = secret_key_problem(self.SECRET_KEY)
        if problem:
            errors.append(
                f"SECRET_KEY {problem}; generate a strong random value "
                "(e.g. `openssl rand -hex 32`)"
            )

        if self.PAYMENT_MOCK_MODE:
            errors.append(
                "PAYMENT_MOCK_MODE must be false in production "
                "(true auto-approves every payment without charging anyone)"
            )
        if not (self.PAYNOW_INTEGRATION_ID and self.PAYNOW_INTEGRATION_KEY):
            errors.append(
                "PAYNOW_INTEGRATION_ID and PAYNOW_INTEGRATION_KEY are required in production"
            )
        if self.SMS_MOCK_MODE:
            errors.append(
                "SMS_MOCK_MODE must be false in production "
                "(true silently drops OTP and password-reset messages)"
            )
        if not self.AFRICASTALKING_API_KEY:
            errors.append("AFRICASTALKING_API_KEY is required in production")

        # CORS: a wildcard with allow_credentials=True is a cross-site
        # request-forgery primitive, so it is refused rather than filtered.
        raw_origins = [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]
        if "*" in raw_origins:
            errors.append(
                "CORS_ORIGINS must not contain '*' in production; list the exact "
                "browser origins (e.g. https://app.zvingo.com)"
            )
        for origin in raw_origins:
            if origin == "*":
                continue
            parsed = urlparse(origin)
            if parsed.scheme not in ("http", "https") or not parsed.netloc:
                errors.append(
                    f"CORS_ORIGINS entry {origin!r} is not an absolute origin "
                    "(expected scheme://host[:port] with no path)"
                )
            elif parsed.path not in ("", "/"):
                errors.append(
                    f"CORS_ORIGINS entry {origin!r} must not include a path"
                )

        if self.DEV_ALLOW_ADMIN_ENDPOINTS:
            errors.append(
                "DEV_ALLOW_ADMIN_ENDPOINTS must be false in production "
                "(it exposes unauthenticated maintenance routes)"
            )
        if self.DEV_FORCE_DEFAULT_RESTAURANT_LOCATION:
            errors.append(
                "DEV_FORCE_DEFAULT_RESTAURANT_LOCATION must be false in production"
            )

        if self.METRICS_ENABLED and not self.METRICS_TOKEN:
            errors.append(
                "METRICS_TOKEN is required in production when METRICS_ENABLED is true "
                "(otherwise GET /metrics publishes internal traffic data); set a random "
                "token or disable with METRICS_ENABLED=false"
            )

        if errors:
            raise ValueError(
                "Refusing to start with ENVIRONMENT=production: " + "; ".join(errors)
            )
        return self


settings = Settings()
