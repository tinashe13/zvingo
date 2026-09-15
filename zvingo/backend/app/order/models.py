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
    """One entry in an order's immutable audit trail.

    Every state change appends exactly one event recording *what* changed, *who*
    changed it and *why*. Events are only ever pushed, never rewritten, so the
    history of an order can be replayed for support and dispute handling.
    """

    state: OrderState
    timestamp: datetime = Field(default_factory=utc_now)
    #: The authenticated principal that caused the change, or "system" for a
    #: change made by dispatch/scheduler background work.
    actor_id: Optional[str] = None
    #: Machine-readable cause, e.g. "driver_accepted", "consumer_cancelled",
    #: "dispatch_offered", "driver_released". Free-form but stable per call site.
    reason: Optional[str] = None
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
    # Set once the scheduler has released a scheduled order for dispatch, so it
    # is handed over to the ordinary retry loop and never double-dispatched.
    scheduled_dispatched: bool = False
    # Multi-restaurant checkout: sibling orders placed in the same basket share
    # this id. None for a single-restaurant order.
    group_id: Optional[str] = None
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

    # ── Dispatch bookkeeping ────────────────────────────────────────
    # Drivers this order has already been offered to. Dispatch offers to one
    # driver at a time and never re-offers to a driver who has already seen (or
    # declined) this order in the current round, so the pool is walked fairly
    # instead of hammering whoever happens to be nearest.
    offered_to: List[str] = []
    declined_by: List[str] = []
    # The driver currently holding an unanswered offer, and when it lapses.
    offered_driver_id: Optional[str] = None
    offer_expires_at: Optional[datetime] = None

    # ── Dead letter ─────────────────────────────────────────────────
    # Set when dispatch gave up after DISPATCH_MAX_RETRY_ATTEMPTS. The order
    # stops being retried, an operational alert is raised, and the consumer is
    # told once — an order nobody will ever pick up must surface to ops rather
    # than leave the consumer waiting forever.
    dispatch_escalated: bool = False
    dispatch_escalated_at: Optional[datetime] = None

    class Settings:
        name = "orders"
        indexes = [
            [("pickup_location", "2dsphere")],
            [("idempotency_key", 1)],
            [("group_id", 1)],
            # Dispatch/scheduler sweeps and the stuck-order alert.
            [("state", 1), ("scheduled_at", 1)],
            [("state", 1), ("updated_at", 1)],
            [("state", 1), ("created_at", 1)],
            # "My orders", newest first (consumer app home + merchant dashboard).
            [("consumer_id", 1), ("created_at", -1)],
            [("merchant_id", 1), ("created_at", -1)],
            # Driver's active job(s) and the driver sync delta.
            [("driver_id", 1), ("state", 1)],
            [("driver_id", 1), ("updated_at", -1)],
            # Offers pending for a specific driver (sync + re-offer exclusion).
            [("state", 1), ("offered_to", 1)],
        ]
