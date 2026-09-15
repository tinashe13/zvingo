"""Production configuration must fail closed.

Every assertion here is a deployment that should never boot. The point of the
validator in app/config.py is that these are caught at import time, in the
container's first log line, rather than discovered by an attacker.
"""

import pytest

from app.config import (
    KNOWN_INSECURE_SECRETS,
    MIN_SECRET_KEY_LENGTH,
    Settings,
    secret_key_problem,
)

# A realistic key: 64 hex characters of actual entropy.
GOOD_SECRET = "9f2c41ab7e05d8631c4a0fbe27d95a83704ec6218dbf5a0917c3e4d6b8a12f7e"

BASE = {
    "MONGODB_URL": "mongodb://test",
    "REDIS_URL": "redis://test",
    "_env_file": None,
}

PRODUCTION = {
    "ENVIRONMENT": "production",
    "SECRET_KEY": GOOD_SECRET,
    "PAYMENT_MOCK_MODE": False,
    "PAYNOW_INTEGRATION_ID": "id",
    "PAYNOW_INTEGRATION_KEY": "key",
    "SMS_MOCK_MODE": False,
    "AFRICASTALKING_API_KEY": "sms-key",
    "METRICS_TOKEN": "metrics-token",
}


def production(**overrides) -> Settings:
    return Settings(**BASE, **{**PRODUCTION, **overrides})


def test_a_healthy_production_config_builds():
    settings = production()
    assert settings.is_production
    assert settings.cors_origins == []


@pytest.mark.parametrize("secret", sorted(KNOWN_INSECURE_SECRETS))
def test_every_known_placeholder_secret_is_refused(secret):
    assert secret_key_problem(secret) is not None
    with pytest.raises(ValueError, match="SECRET_KEY"):
        production(SECRET_KEY=secret)


def test_placeholder_secrets_are_matched_case_and_quote_insensitively():
    # A .env written as SECRET_KEY="ChangeThis" is the same mistake.
    assert secret_key_problem('"ChangeThis"') is not None
    assert secret_key_problem("  CHANGEME  ") is not None


def test_short_secrets_are_refused():
    short = "a1b2c3d4e5f6"
    assert len(short) < MIN_SECRET_KEY_LENGTH
    assert "characters" in secret_key_problem(short)
    with pytest.raises(ValueError, match="SECRET_KEY"):
        production(SECRET_KEY=short)


def test_long_but_low_entropy_secrets_are_refused():
    """`SECRET_KEY=xxxxxxxx...` is long enough to pass a naive length check."""
    assert "distinct characters" in secret_key_problem("x" * 64)
    with pytest.raises(ValueError, match="SECRET_KEY"):
        production(SECRET_KEY="x" * 64)
    # Two characters alternating is the same failure mode.
    assert secret_key_problem("ab" * 40) is not None


def test_empty_secret_is_refused():
    assert secret_key_problem("") == "is empty"
    assert secret_key_problem("    ") == "is empty"


def test_mock_payment_mode_cannot_reach_production():
    with pytest.raises(ValueError, match="PAYMENT_MOCK_MODE must be false"):
        production(PAYMENT_MOCK_MODE=True)


def test_mock_sms_mode_cannot_reach_production():
    with pytest.raises(ValueError, match="SMS_MOCK_MODE must be false"):
        production(SMS_MOCK_MODE=True)


def test_live_payment_requires_paynow_credentials():
    with pytest.raises(ValueError, match="PAYNOW_INTEGRATION_ID"):
        production(PAYNOW_INTEGRATION_KEY=None)


def test_live_sms_requires_an_api_key():
    with pytest.raises(ValueError, match="AFRICASTALKING_API_KEY"):
        production(AFRICASTALKING_API_KEY=None)


def test_wildcard_cors_is_refused_in_production():
    with pytest.raises(ValueError, match="CORS_ORIGINS must not contain"):
        production(CORS_ORIGINS="*")
    with pytest.raises(ValueError, match="CORS_ORIGINS must not contain"):
        production(CORS_ORIGINS="https://app.zvingo.com,*")


def test_cors_entries_must_be_absolute_origins():
    with pytest.raises(ValueError, match="not an absolute origin"):
        production(CORS_ORIGINS="app.zvingo.com")
    with pytest.raises(ValueError, match="must not include a path"):
        production(CORS_ORIGINS="https://app.zvingo.com/dashboard")


def test_valid_cors_origins_are_accepted_and_parsed():
    settings = production(CORS_ORIGINS=" https://app.zvingo.com , https://admin.zvingo.com ")
    assert settings.cors_origins == [
        "https://app.zvingo.com",
        "https://admin.zvingo.com",
    ]


def test_wildcard_is_stripped_even_if_it_somehow_reaches_the_property():
    """cors_origins never yields "*" in production, whatever the raw value."""
    settings = production()
    object.__setattr__(settings, "CORS_ORIGINS", "*")
    assert settings.cors_origins == []


def test_development_still_gets_a_permissive_default():
    assert Settings(**BASE).cors_origins == ["*"]


def test_dev_escape_hatches_cannot_reach_production():
    with pytest.raises(ValueError, match="DEV_ALLOW_ADMIN_ENDPOINTS"):
        production(DEV_ALLOW_ADMIN_ENDPOINTS=True)
    with pytest.raises(ValueError, match="DEV_FORCE_DEFAULT_RESTAURANT_LOCATION"):
        production(DEV_FORCE_DEFAULT_RESTAURANT_LOCATION=True)


def test_open_metrics_endpoint_is_refused_in_production():
    with pytest.raises(ValueError, match="METRICS_TOKEN is required"):
        production(METRICS_TOKEN=None)
    # ...unless metrics are switched off entirely.
    assert production(METRICS_TOKEN=None, METRICS_ENABLED=False).METRICS_ENABLED is False


def test_the_failure_message_names_every_offending_variable():
    with pytest.raises(ValueError) as exc:
        Settings(**BASE, ENVIRONMENT="production")
    message = str(exc.value)
    for variable in (
        "SECRET_KEY",
        "PAYMENT_MOCK_MODE",
        "PAYNOW_INTEGRATION_ID",
        "SMS_MOCK_MODE",
        "AFRICASTALKING_API_KEY",
        "METRICS_TOKEN",
    ):
        assert variable in message


def test_development_configuration_is_left_alone():
    """Nothing above should make local development harder."""
    settings = Settings(**BASE, ENVIRONMENT="development", SECRET_KEY="changethis")
    assert settings.SECRET_KEY == "changethis"
    assert settings.is_production is False
