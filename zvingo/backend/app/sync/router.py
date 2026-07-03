from fastapi import APIRouter, Depends, HTTPException, Response
from app.sync.schemas import SyncRequest
from app.sync.service import SyncService
from app.auth.router import get_current_user
from app.auth.models import User

router = APIRouter()

@router.post("/pull")
async def pull_changes(request: SyncRequest, current_user: User = Depends(get_current_user)):
    # Ownership check: callers may only pull their own sync deltas
    if request.driver_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Cannot sync another driver's data")
    packed_data = await SyncService.get_deltas(request.driver_id, request.last_version)
    return Response(content=packed_data, media_type="application/x-msgpack")
