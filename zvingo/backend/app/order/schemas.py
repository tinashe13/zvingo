from pydantic import BaseModel, Field, model_validator
from typing import List, Optional
from datetime import datetime
from app.order.state_machine import OrderState
from app.location.models import Location

class OrderItem(BaseModel):
    name: str
    quantity: int
    price: float
    special_instructions: Optional[str] = None

class OrderCreate(BaseModel):
    merchant_id: str
    consumer_id: str
    items: List[OrderItem]
    total_amount: float

    # Preferred nested GeoJSON locations.
    pickup: Optional[Location] = None
    dropoff: Optional[Location] = None

    # Legacy flat coordinates (deprecated — kept for backward compatibility).
    # Prefer `pickup` / `dropoff` above.
    pickup_lat: Optional[float] = None
    pickup_lng: Optional[float] = None
    dropoff_lat: Optional[float] = None
    dropoff_lng: Optional[float] = None

    delivery_instructions: Optional[str] = None
    tip_amount: Optional[float] = 0.0
    delivery_fee: Optional[float] = 0.0
    service_fee: Optional[float] = 0.0
    tax_amount: Optional[float] = 0.0
    idempotency_key: Optional[str] = None

    @model_validator(mode="after")
    def _normalize_locations(self) -> "OrderCreate":
        """Fold legacy flat lat/lng fields into nested Location objects."""
        if self.pickup is None:
            if self.pickup_lat is not None or self.pickup_lng is not None:
                if self.pickup_lat is None or self.pickup_lng is None:
                    raise ValueError("pickup_lat and pickup_lng must be provided together")
                self.pickup = Location.from_lat_lng(self.pickup_lat, self.pickup_lng)
        if self.dropoff is None:
            if self.dropoff_lat is not None or self.dropoff_lng is not None:
                if self.dropoff_lat is None or self.dropoff_lng is None:
                    raise ValueError("dropoff_lat and dropoff_lng must be provided together")
                self.dropoff = Location.from_lat_lng(self.dropoff_lat, self.dropoff_lng)
        return self

class OrderUpdateState(BaseModel):
    state: OrderState

class OrderResponse(BaseModel):
    id: str
    state: OrderState
    total_amount: float
    created_at: datetime
    driver_id: Optional[str] = None
    driver_name: Optional[str] = None
    merchant_id: Optional[str] = None
    consumer_id: Optional[str] = None
    items: List[OrderItem] = []
    pickup_lat: Optional[float] = None
    pickup_lng: Optional[float] = None
    delivery_lat: Optional[float] = None
    delivery_lng: Optional[float] = None
    delivery_instructions: Optional[str] = None
