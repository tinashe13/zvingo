"""Paynow webhook authentication.

`POST /payment/webhook` is the endpoint that marks orders paid. Before this
change it believed whatever it was sent, so `reference=<guess>&status=Paid` was
a direct route to free food. These tests prove a forged notification is now
rejected, that a genuine one is accepted, and that our hash matches Paynow's
own algorithm byte for byte.
"""

import hashlib
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.payment import webhook_security as ws

INTEGRATION_KEY = "0f5b2c8a-4d1e-4a7b-9c33-3f2a1b9e7d10"


def paynow_hash(fields, key=INTEGRATION_KEY):
    """Reference implementation, mirroring the official Paynow SDK."""
    out = "".join(str(v) for k, v in fields if str(k).lower() != "hash")
    out += key.lower()
    return hashlib.sha512(out.encode("utf-8")).hexdigest().upper()


def genuine_fields(status="Paid", reference="ZVINGO-abc12345", amount="31.50"):
    return [
        ("reference", reference),
        ("paynowreference", "1234567"),
        ("amount", amount),
        ("status", status),
        ("pollurl", "https://www.paynow.co.zw/interface/poll/abc"),
    ]


# ── hash algorithm ──────────────────────────────────────────────────


def test_our_hash_matches_the_official_paynow_sdk_algorithm():
    """Cross-checked against `paynow.model.Paynow.__hash`, not just ourselves."""
    from paynow.model import Paynow

    fields = genuine_fields()
    body = dict(fields)
    sdk = Paynow("id", INTEGRATION_KEY, "https://r", "https://s")
    # The SDK's hash helper is name-mangled private; reach it deliberately so
    # this test breaks if Paynow ever changes the algorithm.
    sdk_hash = sdk._Paynow__hash(body, INTEGRATION_KEY)
    assert ws.compute_paynow_hash(fields, INTEGRATION_KEY) == sdk_hash
    assert sdk_hash == paynow_hash(fields)


def test_valid_hash_verifies_and_is_case_insensitive():
    fields = genuine_fields()
    h = paynow_hash(fields)
    assert ws.verify_paynow_hash(fields, h, INTEGRATION_KEY)
    assert ws.verify_paynow_hash(fields, h.lower(), INTEGRATION_KEY)
    assert ws.verify_paynow_hash(fields, f"  {h}  ", INTEGRATION_KEY)


def test_a_forged_or_tampered_notification_does_not_verify():
    fields = genuine_fields(status="Created", amount="0.01")
    h = paynow_hash(fields)

    # The attacker flips the status to Paid but cannot recompute the hash.
    tampered = genuine_fields(status="Paid", amount="0.01")
    assert not ws.verify_paynow_hash(tampered, h, INTEGRATION_KEY)

    # Or inflates nothing and just guesses a hash.
    assert not ws.verify_paynow_hash(fields, "A" * 128, INTEGRATION_KEY)
    # Or omits it entirely.
    assert not ws.verify_paynow_hash(fields, None, INTEGRATION_KEY)
    assert not ws.verify_paynow_hash(fields, "", INTEGRATION_KEY)
    # Or knows the fields but not the key.
    assert not ws.verify_paynow_hash(fields, paynow_hash(fields, "wrong-key"), INTEGRATION_KEY)


def test_hash_verification_survives_reordered_fields():
    """Some proxies reorder form fields; the documented order is the fallback."""
    canonical = genuine_fields()
    h = paynow_hash(canonical)
    shuffled = [canonical[3], canonical[0], canonical[4], canonical[1], canonical[2]]
    assert ws.verify_paynow_hash(shuffled, h, INTEGRATION_KEY)


# ── policy ──────────────────────────────────────────────────────────


def test_verification_is_mandatory_whenever_mock_mode_is_off(monkeypatch):
    monkeypatch.setattr(ws.settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(ws.settings, "PAYMENT_MOCK_MODE", True)
    assert ws.verification_required() is False

    monkeypatch.setattr(ws.settings, "PAYMENT_MOCK_MODE", False)
    assert ws.verification_required() is True


def test_production_always_requires_verification(monkeypatch):
    """Even a settings object that somehow claims mock mode cannot opt out."""
    monkeypatch.setattr(ws.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(ws.settings, "PAYMENT_MOCK_MODE", True)
    assert ws.verification_required() is True

    result = ws.verify_webhook_fields(genuine_fields(), None)
    assert result.verified is False
    assert result.required is True
    assert result.accepted is False


def test_missing_integration_key_in_live_mode_rejects_everything(monkeypatch):
    monkeypatch.setattr(ws.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(ws.settings, "PAYMENT_MOCK_MODE", False)
    monkeypatch.setattr(ws.settings, "PAYNOW_INTEGRATION_KEY", None)
    result = ws.verify_webhook_fields(genuine_fields(), paynow_hash(genuine_fields()))
    assert result.accepted is False
    assert "PAYNOW_INTEGRATION_KEY" in result.reason


def test_configured_key_accepts_a_genuine_delivery_and_rejects_a_forgery(monkeypatch):
    monkeypatch.setattr(ws.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(ws.settings, "PAYMENT_MOCK_MODE", False)
    monkeypatch.setattr(ws.settings, "PAYNOW_INTEGRATION_KEY", INTEGRATION_KEY)

    fields = genuine_fields()
    good = ws.verify_webhook_fields(fields, paynow_hash(fields))
    assert good.verified and good.accepted

    bad = ws.verify_webhook_fields(fields, paynow_hash(fields, "someone-elses-key"))
    assert not bad.verified and not bad.accepted
    assert bad.reason == "webhook hash does not match"


def test_poll_urls_outside_paynow_are_never_trusted():
    assert ws.is_trusted_poll_url("https://www.paynow.co.zw/interface/poll/abc")
    assert ws.is_trusted_poll_url("https://paynow.co.zw/x")
    # An attacker-controlled endpoint that would always answer "Paid".
    assert not ws.is_trusted_poll_url("https://evil.example.com/poll")
    # Lookalike domain.
    assert not ws.is_trusted_poll_url("https://paynow.co.zw.evil.com/poll")
    # SSRF into the cluster.
    assert not ws.is_trusted_poll_url("http://169.254.169.254/latest/meta-data/")
    assert not ws.is_trusted_poll_url("file:///etc/passwd")
    assert not ws.is_trusted_poll_url("")
    assert not ws.is_trusted_poll_url(None)


# ── the endpoint itself ─────────────────────────────────────────────


class FormData(dict):
    """Stand-in for Starlette's FormData, preserving field order."""

    def multi_items(self):
        return list(self.items())


def request_with(fields):
    return SimpleNamespace(form=AsyncMock(return_value=FormData(fields)))


@pytest.mark.asyncio
async def test_endpoint_rejects_a_forged_webhook_with_401(monkeypatch):
    """The headline test: a forged 'paid' notification must not reach the service."""
    import app.payment.router as module

    monkeypatch.setattr(ws.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(ws.settings, "PAYMENT_MOCK_MODE", False)
    monkeypatch.setattr(ws.settings, "PAYNOW_INTEGRATION_KEY", INTEGRATION_KEY)

    handler = AsyncMock()
    monkeypatch.setattr(module.PaymentService, "handle_webhook", handler)

    forged = genuine_fields(status="Paid") + [("hash", "DEADBEEF" * 16)]
    with pytest.raises(HTTPException) as exc:
        await module.payment_webhook(request_with(forged))
    assert exc.value.status_code == 401
    # Nothing was marked paid, nothing was dispatched.
    handler.assert_not_awaited()

    # A notification with no hash at all is refused the same way.
    with pytest.raises(HTTPException) as exc:
        await module.payment_webhook(request_with(genuine_fields(status="Paid")))
    assert exc.value.status_code == 401
    handler.assert_not_awaited()


@pytest.mark.asyncio
async def test_endpoint_accepts_a_correctly_signed_webhook(monkeypatch):
    import app.payment.router as module

    monkeypatch.setattr(ws.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(ws.settings, "PAYMENT_MOCK_MODE", False)
    monkeypatch.setattr(ws.settings, "PAYNOW_INTEGRATION_KEY", INTEGRATION_KEY)

    handler = AsyncMock(return_value=SimpleNamespace(id="p1"))
    monkeypatch.setattr(module.PaymentService, "handle_webhook", handler)

    fields = genuine_fields(status="Paid")
    signed = fields + [("hash", paynow_hash(fields))]
    assert await module.payment_webhook(request_with(signed)) == {"status": "ok"}

    handler.assert_awaited_once()
    kwargs = handler.await_args.kwargs
    assert kwargs["signature_verified"] is True
    assert kwargs["status"] == "Paid"
    assert kwargs["amount"] == "31.50"
    assert kwargs["paynow_reference"] == "1234567"
    # The raw delivery is handed on for the audit log (the service redacts the
    # signature before storing it — see test_b2_payment_flow).
    assert set(kwargs["payload"]) == {
        "reference", "paynowreference", "amount", "status", "pollurl", "hash"
    }


@pytest.mark.asyncio
async def test_unknown_reference_yields_404_so_paynow_retries(monkeypatch):
    import app.payment.router as module

    monkeypatch.setattr(ws.settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(ws.settings, "PAYMENT_MOCK_MODE", True)
    monkeypatch.setattr(module.PaymentService, "handle_webhook", AsyncMock(return_value=None))

    with pytest.raises(HTTPException) as exc:
        await module.payment_webhook(request_with(genuine_fields()))
    assert exc.value.status_code == 404
