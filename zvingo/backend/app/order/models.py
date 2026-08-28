from typing import List, Optional
from datetime import datetime
from app.time_utils import utc_now
from beanie import Document, Indexed
from pydantic import BaseModel, Field
from app.order.state_machine import OrderState
from app.location.models import Location

class OrderItem(BaseModel):
    name: str
    quantity: int
    price: float
    special_instructions: Optional[str] = None

class OrderEvent(BaseModel):
    state: OrderState
    timestamp: datetime = Field(default_factory=utc_now)
    actor_id: Optional[str] = None
    metadata: dict = {}

class Order(Document):
    merchant_id: Indexed(str)
    consumer_id: Indexed(str)
    driver_id: Optional[Indexed(str)] = None

    state: OrderState = OrderState.CREATED
    items: List[OrderItem]
    total_amount: float

    pickup_location: Optional[Location] = None  # GeoJSON Point
    dropoff_location: Optional[Location] = None  # GeoJSON Point

    delivery_instructions: Optional[str] = None
    tip_amount: float = 0.0
    delivery_fee: float = 0.0
    service_fee: float = 0.0
    tax_amount: float = 0.0

    # Self-pickup: no driver, no delivery fee.
    is_pickup: bool = False
    # Scheduled: dispatch deferred until this time (UTC).
    scheduled_at: Optional[datetime] = None
    # Promo discount applied at checkout (dollars).
    promo_code: Optional[str] = None
    discount_amount: float = 0.0

    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)

    events: List[OrderEvent] = []

    idempotency_key: Optional[str] = None

    # Retry tracking for stuck orders
    retry_count: int = 0
    last_retry_at: Optional[datetime] = None

    class Settings:
        name = "orders"
        indexes = [
            [("pickup_location", "2dsphere")],
            [("idempotency_key", 1)],
        ]
