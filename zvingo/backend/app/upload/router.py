from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
import shutil
import os
import uuid
from pathlib import Path

from app.config import settings
from app.auth.router import get_current_user
from app.auth.models import User

router = APIRouter()

UPLOAD_DIR = Path("static/uploads")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
MAX_FILE_SIZE = settings.MAX_UPLOAD_SIZE_BYTES  # default 5MB


@router.post("/")
async def upload_file(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    original_name = file.filename or "image.jpg"
    extension = os.path.splitext(original_name)[1].lower()

    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"File type {extension} not allowed. Allowed: {', '.join(ALLOWED_EXTENSIONS)}")

    # Read and check size
    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail=f"File too large. Maximum size is {MAX_FILE_SIZE // (1024*1024)}MB")

    try:
        filename = f"{uuid.uuid4().hex}{extension}"
        file_path = UPLOAD_DIR / filename

        with open(file_path, "wb") as buffer:
            buffer.write(content)

        url = f"{settings.UPLOAD_BASE_URL}/static/uploads/{filename}"
        return {"url": url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
