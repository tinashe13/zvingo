from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel


class Page(BaseModel):
    """Envelope shared by every paginated admin listing."""

    page: int
    page_size: int
    total: int
    records: List[Dict[str, Any]] = []


class AdminUserUpdate(BaseModel):
    """Fields an admin may change on a user account."""

    is_active: Optional[bool] = None
    role: Optional[str] = None
    full_name: Optional[str] = None


class RestaurantAdminUpdate(BaseModel):
    is_active: Optional[bool] = None


class PlatformStats(BaseModel):
    users: Dict[str, int]
    orders: Dict[str, int]
    payments: Dict[str, int]
    gmv: Dict[str, float]
    restaurants: Dict[str, int]
    generated_at: datetime
