from pydantic import BaseModel
from typing import List, Dict, Any, Optional

class SyncRequest(BaseModel):
    driver_id: str
    last_version: int

class SyncResponse(BaseModel):
    new_version: int
    data: Dict[str, List[Dict[str, Any]]] # collection -> list of docs
    has_more: bool = False
