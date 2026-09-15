"""Image upload.

Files land on disk and are then served back by ``StaticFiles`` at
``/static/uploads``, which makes this endpoint the most dangerous surface in
the API: whatever is written here is later handed to a browser. Three separate
things have to hold.

1. **The bytes really are an image.** The declared ``Content-Type`` and the
   filename extension are both attacker-controlled, so neither is trusted.
   :func:`sniff_image_type` reads the magic bytes and derives the extension
   from *those*. A polyglot (HTML that also parses as GIF), a PHP file named
   ``.png``, or an SVG carrying a script all fail here — SVG in particular is
   refused outright because it is an active document, not a picture.
2. **The stored name is ours, not theirs.** The saved filename is a random
   hex string plus the sniffed extension, so path traversal
   (``../../etc/cron.d/x``), Windows device names, null bytes and unicode
   look-alikes cannot influence where the write lands. The original name is
   only ever logged.
3. **Nobody can fill the disk.** The route requires authentication, caps the
   size from settings *while streaming* (so an oversized body is abandoned
   rather than buffered), and rate-limits per user.
"""

import os
import re
import secrets
from pathlib import Path
from typing import Optional, Tuple

import structlog
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from app.auth.models import User
from app.auth.router import get_current_user
from app.config import settings
from app.db.redis import redis_client
from app.rate_limiter import RateLimiter

logger = structlog.get_logger()

router = APIRouter()

UPLOAD_DIR = Path("static/uploads")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
MAX_FILE_SIZE = settings.MAX_UPLOAD_SIZE_BYTES  # default 5MB
CHUNK_SIZE = 64 * 1024

# Magic-byte signatures for the raster formats we accept. Everything else —
# SVG, HTML, PDF, ELF, scripts, archives — has no entry and is rejected.
_SIGNATURES: Tuple[Tuple[bytes, str, str], ...] = (
    (b"\xff\xd8\xff", ".jpg", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", ".png", "image/png"),
    (b"GIF87a", ".gif", "image/gif"),
    (b"GIF89a", ".gif", "image/gif"),
)

# Extensions that must never be written, whatever the bytes look like. This is
# belt-and-braces behind the allow-list above: if a future edit widens the
# allow-list by accident, these still cannot land.
DENIED_EXTENSIONS = {
    ".php", ".phtml", ".php3", ".php4", ".php5", ".phar",
    ".html", ".htm", ".xhtml", ".shtml", ".svg", ".xml",
    ".js", ".mjs", ".jsp", ".asp", ".aspx", ".cgi", ".pl",
    ".py", ".rb", ".sh", ".bash", ".exe", ".dll", ".so",
    ".jar", ".war", ".bat", ".cmd", ".ps1", ".htaccess",
}

_SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]")


def sanitize_filename(name: Optional[str]) -> str:
    """Reduce a client-supplied name to a harmless label.

    The result is **not** used as the storage name (that is randomised); this
    exists so the original can be logged and echoed without smuggling control
    characters, newlines or separators into logs and responses.
    """
    if not name:
        return "upload"
    # Take the basename under both separator conventions, then strip anything
    # that is not plainly alphanumeric.
    base = os.path.basename(name.replace("\\", "/")).replace("\x00", "")
    base = _SAFE_NAME.sub("_", base).lstrip(".")
    base = base[:100]
    return base or "upload"


def sniff_image_type(content: bytes) -> Optional[Tuple[str, str]]:
    """Return ``(extension, content_type)`` for real image bytes, else None.

    WEBP needs two checks because its signature is split: ``RIFF`` at offset 0
    and ``WEBP`` at offset 8.
    """
    for signature, extension, content_type in _SIGNATURES:
        if content.startswith(signature):
            return extension, content_type
    if len(content) >= 12 and content[:4] == b"RIFF" and content[8:12] == b"WEBP":
        return ".webp", "image/webp"
    return None


def _looks_like_markup(content: bytes) -> bool:
    """True for content a browser might render as an active document.

    A GIF/HTML polyglot passes the magic-byte check (it really does start with
    ``GIF89a``) yet still executes when served with the wrong content type.
    Refusing anything with a markup opener closes that door.
    """
    head = content[:2048].lower()
    return b"<script" in head or b"<html" in head or b"<?php" in head or b"<svg" in head


async def _read_capped(file: UploadFile, limit: int) -> bytes:
    """Read at most ``limit`` bytes, then one more to detect an overrun.

    Streaming in chunks means a 10 GB body costs us one chunk of memory and an
    early 413, instead of being buffered in full before the size check.
    """
    chunks = []
    total = 0
    while True:
        chunk = await file.read(CHUNK_SIZE)
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise HTTPException(
                status_code=413,  # Content Too Large
                detail=f"File too large. Maximum size is {limit // (1024 * 1024)}MB",
            )
        chunks.append(chunk)
    return b"".join(chunks)


async def _enforce_upload_quota(user_id: str) -> None:
    """Rate-limit uploads per account. Fails open if Redis is unavailable."""
    try:
        async with redis_client() as r:
            result = await RateLimiter(r).check(
                f"rate_limit:upload:{user_id}",
                limit=settings.UPLOAD_RATE_LIMIT,
                window=settings.UPLOAD_RATE_WINDOW_SECONDS,
            )
        if not result.allowed:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Too many uploads. Retry in {result.retry_after}s.",
                headers={"Retry-After": str(result.retry_after)},
            )
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover - limiter already fails open
        logger.error("upload_rate_limit_unavailable", error=str(exc))


@router.post("/")
async def upload_file(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    """Store an uploaded image and return its public URL.

    Requires authentication: an open upload endpoint is free hosting for
    malware and a straight path to a full disk.
    """
    user_id = str(current_user.id)
    await _enforce_upload_quota(user_id)

    original_name = sanitize_filename(getattr(file, "filename", None))
    declared_extension = os.path.splitext(original_name)[1].lower()

    if declared_extension in DENIED_EXTENSIONS:
        logger.warning(
            "upload_rejected", reason="denied_extension", user_id=user_id,
            filename=original_name,
        )
        raise HTTPException(
            status_code=400, detail=f"File type {declared_extension} is not allowed"
        )
    if declared_extension and declared_extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=(
                f"File type {declared_extension} not allowed. "
                f"Allowed: {', '.join(sorted(ALLOWED_EXTENSIONS))}"
            ),
        )

    content = await _read_capped(file, MAX_FILE_SIZE)
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded file is empty")

    sniffed = sniff_image_type(content)
    if sniffed is None or _looks_like_markup(content):
        logger.warning(
            "upload_rejected", reason="not_an_image", user_id=user_id,
            filename=original_name, declared_extension=declared_extension,
        )
        raise HTTPException(
            status_code=400,
            detail="File content is not a supported image (JPEG, PNG, GIF or WEBP)",
        )
    extension, content_type = sniffed

    # The stored name comes from the sniffed type and a random token — never
    # from anything the client sent.
    filename = f"{secrets.token_hex(16)}{extension}"
    upload_dir = Path(UPLOAD_DIR)
    file_path = upload_dir / filename

    # Defence in depth: the name is generated, but assert it really resolves
    # inside the upload directory before writing.
    try:
        resolved = file_path.resolve()
        if upload_dir.resolve() not in resolved.parents:
            raise HTTPException(status_code=400, detail="Invalid upload path")
    except HTTPException:
        raise
    except OSError as exc:
        logger.error("upload_path_resolution_failed", error=str(exc))
        raise HTTPException(status_code=500, detail="Could not store the uploaded file")

    try:
        with open(file_path, "wb") as buffer:
            buffer.write(content)
    except OSError as exc:
        logger.error("upload_write_failed", user_id=user_id, error=str(exc))
        raise HTTPException(status_code=500, detail="Could not store the uploaded file")

    logger.info(
        "upload_stored",
        user_id=user_id,
        stored_as=filename,
        content_type=content_type,
        bytes=len(content),
    )
    return {
        "url": f"{settings.UPLOAD_BASE_URL}/static/uploads/{filename}",
        "content_type": content_type,
        "bytes": len(content),
    }
