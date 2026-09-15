"""Upload hardening, rate-limit atomicity, response headers, log redaction."""

from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

import app.upload.router as upload_router
from app.observability.logging import redact_secrets
from app.observability.middleware import (
    API_CSP,
    BASE_SECURITY_HEADERS,
    STATIC_CSP,
    csp_for,
)
from app.rate_limiter import _SLIDING_WINDOW_LUA, RateLimiter
from app.upload.router import sanitize_filename, sniff_image_type

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
GIF = b"GIF89a" + b"\x00" * 64
WEBP = b"RIFF" + b"\x00\x00\x00\x00" + b"WEBP" + b"\x00" * 64


def user(uid="user-1"):
    return SimpleNamespace(id=uid, role="merchant")


class StreamingUpload:
    """Behaves like Starlette's UploadFile: read(n) drains the buffer."""

    def __init__(self, filename, content):
        self.filename = filename
        self._content = content
        self._offset = 0

    async def read(self, size=-1):
        if size is None or size < 0:
            chunk, self._offset = self._content[self._offset:], len(self._content)
            return chunk
        chunk = self._content[self._offset:self._offset + size]
        self._offset += len(chunk)
        return chunk


@pytest.fixture(autouse=True)
def _no_rate_limiting(monkeypatch):
    """Redis is not available in the suite; skip the quota round trip."""
    monkeypatch.setattr(upload_router, "_enforce_upload_quota", AsyncMock())


# --- Filename handling --------------------------------------------------------


@pytest.mark.parametrize(
    "hostile",
    [
        "../../../../etc/passwd",
        "..\\..\\windows\\system32\\cmd.exe",
        "/etc/cron.d/backdoor",
        "nul",
        "a\x00.png",
        "....//....//evil.png",
        "file\nwith\nnewlines.png",
    ],
)
def test_sanitize_filename_defuses_hostile_names(hostile):
    cleaned = sanitize_filename(hostile)
    assert "/" not in cleaned and "\\" not in cleaned
    assert "\x00" not in cleaned and "\n" not in cleaned
    assert not cleaned.startswith(".")
    assert cleaned  # never empty


def test_sanitize_filename_handles_the_empty_case():
    assert sanitize_filename(None) == "upload"
    assert sanitize_filename("") == "upload"
    assert sanitize_filename("...") == "upload"


def test_sanitize_filename_caps_length():
    assert len(sanitize_filename("a" * 500 + ".png")) <= 100


# --- Content sniffing ---------------------------------------------------------


@pytest.mark.parametrize(
    "content,expected",
    [(PNG, ".png"), (JPEG, ".jpg"), (GIF, ".gif"), (WEBP, ".webp")],
)
def test_real_images_are_recognised_by_their_magic_bytes(content, expected):
    assert sniff_image_type(content)[0] == expected


@pytest.mark.parametrize(
    "content",
    [
        b"<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>",
        b"<?php system($_GET['c']); ?>",
        b"<!DOCTYPE html><html><body>hi</body></html>",
        b"%PDF-1.7\n",
        b"\x7fELF\x02\x01\x01",
        b"PK\x03\x04",
        b"",
        b"RIFF____NOTWEBP",
    ],
)
def test_non_images_are_not_recognised(content):
    assert sniff_image_type(content) is None


# --- The upload route ---------------------------------------------------------


@pytest.mark.asyncio
async def test_a_php_shell_named_as_a_png_is_refused(monkeypatch, tmp_path):
    monkeypatch.setattr(upload_router, "UPLOAD_DIR", tmp_path)
    payload = b"<?php system($_GET['cmd']); ?>"
    with pytest.raises(HTTPException) as exc:
        await upload_router.upload_file(StreamingUpload("avatar.png", payload), user())
    assert exc.value.status_code == 400
    assert list(tmp_path.iterdir()) == []


@pytest.mark.asyncio
async def test_a_gif_html_polyglot_is_refused(monkeypatch, tmp_path):
    """Valid GIF magic bytes, but a browser would still run the script."""
    monkeypatch.setattr(upload_router, "UPLOAD_DIR", tmp_path)
    polyglot = b"GIF89a" + b"/*" + b"<script>alert(document.cookie)</script>"
    with pytest.raises(HTTPException) as exc:
        await upload_router.upload_file(StreamingUpload("ok.gif", polyglot), user())
    assert exc.value.status_code == 400
    assert list(tmp_path.iterdir()) == []


@pytest.mark.asyncio
@pytest.mark.parametrize("name", ["shell.php", "index.html", "logo.svg", "run.sh", "x.exe"])
async def test_dangerous_extensions_are_refused_outright(monkeypatch, tmp_path, name):
    monkeypatch.setattr(upload_router, "UPLOAD_DIR", tmp_path)
    with pytest.raises(HTTPException) as exc:
        await upload_router.upload_file(StreamingUpload(name, PNG), user())
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_a_traversal_filename_cannot_escape_the_upload_directory(
    monkeypatch, tmp_path
):
    monkeypatch.setattr(upload_router, "UPLOAD_DIR", tmp_path)
    result = await upload_router.upload_file(
        StreamingUpload("../../../../tmp/evil.png", PNG), user()
    )
    written = list(tmp_path.iterdir())
    assert len(written) == 1
    assert written[0].parent == tmp_path
    assert "evil" not in written[0].name
    assert written[0].name in result["url"]


@pytest.mark.asyncio
async def test_stored_names_are_random_not_client_supplied(monkeypatch, tmp_path):
    monkeypatch.setattr(upload_router, "UPLOAD_DIR", tmp_path)
    first = await upload_router.upload_file(StreamingUpload("same.png", PNG), user())
    second = await upload_router.upload_file(StreamingUpload("same.png", PNG), user())
    assert first["url"] != second["url"]  # no overwrite, no guessable path
    assert len(list(tmp_path.iterdir())) == 2


@pytest.mark.asyncio
async def test_the_extension_comes_from_the_bytes_not_the_name(monkeypatch, tmp_path):
    """A JPEG uploaded as `photo.png` is stored as .jpg, matching its content."""
    monkeypatch.setattr(upload_router, "UPLOAD_DIR", tmp_path)
    result = await upload_router.upload_file(StreamingUpload("photo.png", JPEG), user())
    assert result["url"].endswith(".jpg")
    assert result["content_type"] == "image/jpeg"


@pytest.mark.asyncio
async def test_oversized_uploads_are_rejected_using_the_configured_limit(
    monkeypatch, tmp_path
):
    monkeypatch.setattr(upload_router, "UPLOAD_DIR", tmp_path)
    monkeypatch.setattr(upload_router, "MAX_FILE_SIZE", 16)
    with pytest.raises(HTTPException) as exc:
        await upload_router.upload_file(StreamingUpload("big.png", PNG), user())
    assert exc.value.status_code == 413
    assert list(tmp_path.iterdir()) == []


@pytest.mark.asyncio
async def test_an_empty_upload_is_rejected(monkeypatch, tmp_path):
    monkeypatch.setattr(upload_router, "UPLOAD_DIR", tmp_path)
    with pytest.raises(HTTPException) as exc:
        await upload_router.upload_file(StreamingUpload("empty.png", b""), user())
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_a_write_failure_does_not_leak_the_filesystem_error(monkeypatch):
    monkeypatch.setattr(upload_router, "UPLOAD_DIR", Path("missing") / "nested")
    with pytest.raises(HTTPException) as exc:
        await upload_router.upload_file(StreamingUpload("a.png", PNG), user())
    assert exc.value.status_code == 500
    assert "missing" not in exc.value.detail


def test_the_upload_route_requires_authentication():
    """Regression guard for the endpoint that used to be wide open."""
    import inspect

    signature = inspect.signature(upload_router.upload_file)
    dependency = signature.parameters["current_user"].default
    assert dependency.dependency.__name__ == "get_current_user"


def test_the_size_limit_comes_from_settings():
    from app.config import settings

    assert upload_router.MAX_FILE_SIZE == settings.MAX_UPLOAD_SIZE_BYTES


# --- Rate limiter -------------------------------------------------------------


class ScriptingRedis:
    """A client that supports EVAL, recording what was executed."""

    def __init__(self, result):
        self.result = result
        self.calls = []

    async def eval(self, script, numkeys, *args):
        self.calls.append((script, numkeys, args))
        return self.result


class SortedSetRedis:
    """No scripting support — exercises the compatibility path."""

    def __init__(self):
        self.entries = []

    async def zremrangebyscore(self, _key, _lo, hi):
        self.entries = [e for e in self.entries if e > hi]

    async def zcard(self, _key):
        return len(self.entries)

    async def zadd(self, _key, mapping):
        self.entries.extend(mapping.values())

    async def expire(self, _key, _ttl):
        return True


def test_the_window_decision_is_one_atomic_script():
    """Trim, count and admit must not be three separate round trips."""
    for command in ("ZREMRANGEBYSCORE", "ZCARD", "ZADD", "EXPIRE"):
        assert command in _SLIDING_WINDOW_LUA


@pytest.mark.asyncio
async def test_the_limiter_uses_the_script_when_the_client_supports_it():
    redis = ScriptingRedis([0, 12, 7])
    result = await RateLimiter(redis).check("k", limit=10, window=60)
    assert not result.allowed
    assert result.retry_after == 7
    assert result.count == 12
    assert "Retry in 7s" in result.message
    assert redis.calls and redis.calls[0][0] is _SLIDING_WINDOW_LUA


@pytest.mark.asyncio
async def test_the_limiter_admits_requests_under_the_limit():
    redis = ScriptingRedis([1, 3, 0])
    result = await RateLimiter(redis).check("k", limit=10, window=60)
    assert result.allowed and result.message is None


@pytest.mark.asyncio
async def test_the_limiter_still_enforces_without_server_side_scripting():
    redis = SortedSetRedis()
    limiter = RateLimiter(redis)
    for _ in range(3):
        assert (await limiter.check("k", limit=3, window=60)).allowed
    assert not (await limiter.check("k", limit=3, window=60)).allowed


@pytest.mark.asyncio
async def test_the_limiter_fails_open_when_redis_is_down():
    class Broken:
        async def eval(self, *_a, **_k):
            raise RuntimeError("connection refused")

    result = await RateLimiter(Broken()).check("k", limit=1, window=60)
    assert result.allowed is True


@pytest.mark.asyncio
async def test_location_updates_keep_their_existing_contract():
    redis = ScriptingRedis([0, 99, 5])
    limiter = RateLimiter(redis)
    limiter.location_limit = 2
    allowed, message = await limiter.check_location_update("driver-1")
    assert not allowed and "max 2" in message


@pytest.mark.asyncio
async def test_there_is_no_shared_mutable_limiter_singleton():
    """A cached client captured on the first request outlives Redis failover."""
    import app.rate_limiter as module

    assert not hasattr(module, "_limiter")
    assert not hasattr(module, "get_rate_limiter")


# --- Security headers ---------------------------------------------------------


def test_the_api_content_security_policy_allows_nothing():
    assert "default-src 'none'" in API_CSP
    assert "frame-ancestors 'none'" in API_CSP


def test_uploaded_files_are_served_under_a_sandboxed_policy():
    policy = csp_for("/static/uploads/abc.png")
    assert policy == STATIC_CSP
    assert "sandbox" in policy
    assert "script-src" not in policy


def test_docs_get_their_own_policy_and_everything_else_gets_the_api_one():
    assert "cdn.jsdelivr.net" in csp_for("/docs")
    assert csp_for("/orders/123") == API_CSP


def test_the_standard_headers_are_present_and_strict():
    assert BASE_SECURITY_HEADERS["X-Content-Type-Options"] == "nosniff"
    assert BASE_SECURITY_HEADERS["X-Frame-Options"] == "DENY"
    assert BASE_SECURITY_HEADERS["Referrer-Policy"] == "no-referrer"


def test_health_responses_carry_the_security_headers_and_a_request_id():
    from fastapi.testclient import TestClient

    import app.main as main_module

    # No context manager: the lifespan (Mongo, Redis, BinProto) must not run.
    client = TestClient(main_module.app)
    response = client.get("/health")

    assert response.status_code == 200
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert response.headers["Content-Security-Policy"] == API_CSP
    assert response.headers["X-Request-ID"]


def test_an_incoming_request_id_is_propagated_back():
    from fastapi.testclient import TestClient

    import app.main as main_module

    client = TestClient(main_module.app)
    response = client.get("/health", headers={"X-Request-ID": "trace-me-1234"})
    assert response.headers["X-Request-ID"] == "trace-me-1234"


def test_hsts_is_only_sent_over_tls():
    from fastapi.testclient import TestClient

    import app.main as main_module

    client = TestClient(main_module.app)
    assert "Strict-Transport-Security" not in client.get("/health").headers
    secure = client.get("/health", headers={"X-Forwarded-Proto": "https"})
    assert "max-age=" in secure.headers["Strict-Transport-Security"]


def test_an_unhandled_error_returns_a_generic_body_with_no_stack_trace():
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    import app.main as main_module

    probe = FastAPI()
    probe.add_exception_handler(Exception, main_module.unhandled_exception_handler)

    @probe.get("/boom")
    async def boom():
        raise RuntimeError("secret connection string postgres://user:pw@host/db")

    client = TestClient(probe, raise_server_exceptions=False)
    response = client.get("/boom")

    assert response.status_code == 500
    body = response.text
    assert response.json()["detail"] == "Internal server error"
    for leak in ("Traceback", "RuntimeError", "postgres://", "app/main.py"):
        assert leak not in body


def test_validation_errors_do_not_echo_the_rejected_payload():
    from fastapi import FastAPI
    from fastapi.exceptions import RequestValidationError
    from fastapi.testclient import TestClient
    from pydantic import BaseModel

    import app.main as main_module

    class Credentials(BaseModel):
        username: str
        password: str

    probe = FastAPI()
    probe.add_exception_handler(
        RequestValidationError, main_module.validation_exception_handler
    )

    @probe.post("/login")
    async def login(_credentials: Credentials):  # pragma: no cover - never reached
        return {}

    client = TestClient(probe)
    response = client.post("/login", json={"username": "someone"})

    assert response.status_code == 422
    assert "hunter2" not in response.text
    assert "input" not in response.text  # the default handler includes this


# --- Log redaction ------------------------------------------------------------


@pytest.mark.parametrize(
    "key",
    [
        "password",
        "hashed_password",
        "new_password",
        "secret_key",
        "access_token",
        "refresh_token",
        "authorization",
        "api_key",
        "otp",
        "signature",
        "cookie",
    ],
)
def test_secret_looking_fields_never_reach_the_log(key):
    event = redact_secrets(None, "info", {"event": "x", key: "the-actual-secret"})
    assert event[key] == "[redacted]"


def test_redaction_walks_nested_payloads():
    event = redact_secrets(
        None,
        "info",
        {
            "event": "request",
            "body": {"username": "amai", "password": "hunter2"},
            "items": [{"api_key": "sk-live-123"}],
        },
    )
    assert event["body"]["password"] == "[redacted]"
    assert event["body"]["username"] == "amai"
    assert event["items"][0]["api_key"] == "[redacted]"


def test_redaction_leaves_harmless_fields_alone():
    event = redact_secrets(
        None, "info", {"event": "login", "token_type": "bearer", "user_id": "user-1"}
    )
    assert event["token_type"] == "bearer"
    assert event["user_id"] == "user-1"
