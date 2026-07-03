from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime
from app.order.state_machine import OrderState

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
    pickup_lat: float
    pickup_lng: float
    dropoff_lat: float
    dropoff_lng: float
    delivery_instructions: Optional[str] = None
    tip_amount: Optional[float] = 0.0
    delivery_fee: Optional[float] = 0.0
    service_fee: Optional[float] = 0.0
    tax_amount: Optional[float] = 0.0
    idempotency_key: Optional[str] = None

class OrderUpdateState(BaseModel):
    state: OrderState
    driver_id: Optional[str] = None

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
