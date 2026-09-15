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

    # Self-pickup: no driver, no delivery fee.
    is_pickup: bool = False
    # Scheduled: dispatch deferred until this time (UTC).
    scheduled_at: Optional[datetime] = None
    # Promo code to redeem at checkout (discount is computed server-side).
    promo_code: Optional[str] = None

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


class OrderEventResponse(BaseModel):
    """One entry of an order's audit trail, as returned by GET /orders/{id}/events."""

    state: str
    timestamp: Optional[datetime] = None
    actor_id: Optional[str] = None
    reason: Optional[str] = None

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
    # Set when the order came from a multi-restaurant checkout.
    group_id: Optional[str] = None


class CheckoutBasket(BaseModel):
    """One restaurant's slice of a multi-restaurant cart."""

    merchant_id: str
    items: List[OrderItem]
    # Basket subtotal *before* fees, tip, and any promo discount.
    subtotal: float

    # Optional per-basket overrides; pickup falls back to the restaurant record.
    pickup: Optional[Location] = None
    delivery_fee: Optional[float] = None
    service_fee: Optional[float] = 0.0
    tax_amount: Optional[float] = 0.0
    is_pickup: bool = False


class CheckoutCreate(BaseModel):
    """A single checkout that may span several restaurants.

    The consumer's cart is grouped by restaurant on the client; each group
    becomes its own Order (each has its own merchant, driver, and lifecycle)
    but all of them share a `group_id` so the app can present one basket.
    """

    baskets: List[CheckoutBasket]
    dropoff: Location

    delivery_instructions: Optional[str] = None
    tip_amount: float = 0.0
    scheduled_at: Optional[datetime] = None
    # Applied once across the whole checkout and split across the baskets.
    promo_code: Optional[str] = None
    idempotency_key: Optional[str] = None

    @model_validator(mode="after")
    def _validate_baskets(self) -> "CheckoutCreate":
        if not self.baskets:
            raise ValueError("At least one basket is required")
        merchant_ids = [b.merchant_id for b in self.baskets]
        if len(set(merchant_ids)) != len(merchant_ids):
            raise ValueError("Each basket must be for a different restaurant")
        for basket in self.baskets:
            if not basket.items:
                raise ValueError("Each basket must contain at least one item")
        return self

    @property
    def subtotal(self) -> float:
        return round(sum(b.subtotal for b in self.baskets), 2)


class CheckoutResponse(BaseModel):
    group_id: str
    promo_code: Optional[str] = None
    discount_total: float = 0.0
    subtotal: float = 0.0
    orders: List["OrderResponse"] = []
