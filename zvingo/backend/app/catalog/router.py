from fastapi import APIRouter, HTTPException, Depends, Query, status
from typing import Annotated, List, Optional
from app.catalog import search_service
from app.catalog.hours import (
    DEFAULT_TIMEZONE,
    DayHours,
    InvalidHours,
    availability_of,
    describe_week,
    normalise_week,
    parse_legacy_hours,
)
from app.catalog.models import Restaurant, MenuItem, Location
from app.catalog.maintenance import get_default_restaurant_coords, backfill_restaurant_locations
from app.config import settings
from app.catalog.promotion_models import Promotion
from app.catalog.promotion_service import SUPPORTED_PROMO_TYPES
from app.auth.router import get_current_admin, get_current_user, User
from pydantic import BaseModel, Field
import re
from datetime import datetime, timedelta, timezone as dt_timezone
from app.time_utils import utc_now

router = APIRouter()

# Every list endpoint is bounded. `DEFAULT_PAGE_SIZE` is what a client gets when
# it asks for nothing; `MAX_PAGE_SIZE` is the hard ceiling even if it asks for
# more. An unbounded catalog listing is an outage waiting for the first city
# with 10k restaurants.
DEFAULT_PAGE_SIZE = 25
MAX_PAGE_SIZE = 100

# Ranking needs a pool bigger than one page to sort meaningfully, but not the
# whole collection. This is the read ceiling for a single discovery request.
CANDIDATE_POOL = 300


def _pool_size(offset: int, limit: int) -> int:
    return min(CANDIDATE_POOL, max(offset + limit, limit) * 4)


def _apply_page(query, offset: int, limit: int):
    """Push pagination into the database query."""
    return query.skip(offset).limit(limit)

# --- Schemas ---
class RestaurantCreate(BaseModel):
    name: str
    description: Optional[str] = None
    categories: List[str] = []
    delivery_time_min: int = 30
    delivery_time_max: int = 45
    delivery_fee_usd: float = 2.00
    lat: float
    lng: float
    image_url: Optional[str] = None
    free_delivery_threshold: Optional[float] = None
    is_zvingo_plus: bool = False

class MenuItemCreate(BaseModel):
    name: str
    description: Optional[str] = None
    price_usd: float
    category: str
    image_url: Optional[str] = None
    images: List[str] = []
    approval_percent: Optional[int] = None
    approval_count: Optional[int] = None
    is_great_price: bool = False

class MenuItemUpdate(BaseModel):
    is_available: Optional[bool] = None
    name: Optional[str] = None
    price_usd: Optional[float] = None
    description: Optional[str] = None
    category: Optional[str] = None
    image_url: Optional[str] = None
    images: Optional[List[str]] = None
    approval_percent: Optional[int] = None
    approval_count: Optional[int] = None
    is_great_price: Optional[bool] = None

# --- Endpoints ---

def _price_band(restaurant) -> int:
    """1–4 "$" band from the median menu price, for the price filter."""
    prices = sorted(
        float(getattr(i, "price_usd", 0) or 0)
        for i in (getattr(restaurant, "menu", None) or [])
    )
    if not prices:
        return 2
    median = prices[len(prices) // 2]
    if median < 5:
        return 1
    if median < 12:
        return 2
    if median < 25:
        return 3
    return 4


def _apply_filters(
    restaurants: List,
    *,
    free_delivery: bool = False,
    min_rating: Optional[float] = None,
    dietary: Optional[str] = None,
    category: Optional[str] = None,
    has_promotions: bool = False,
    max_delivery_minutes: Optional[int] = None,
    price_band: Optional[int] = None,
    open_now: bool = False,
) -> List:
    """Shared filter pass for `/restaurants`, `/search`, and `/nearby`."""
    if free_delivery:
        restaurants = [r for r in restaurants if r.delivery_fee_usd == 0]
    if min_rating is not None:
        restaurants = [r for r in restaurants if r.rating >= min_rating]
    if dietary:
        tags = [t.strip().lower() for t in dietary.split(",") if t.strip()]
        restaurants = [
            r
            for r in restaurants
            if any(t in [x.lower() for x in (r.dietary_tags or [])] for t in tags)
        ]
    if category:
        cats = [c.strip().lower() for c in category.split(",") if c.strip()]
        restaurants = [
            r
            for r in restaurants
            if any(c in [x.lower() for x in (r.categories or [])] for c in cats)
        ]
    if has_promotions:
        restaurants = [r for r in restaurants if r.promotions]
    if max_delivery_minutes is not None:
        restaurants = [
            r for r in restaurants if r.delivery_time_max <= max_delivery_minutes
        ]
    if price_band is not None:
        restaurants = [r for r in restaurants if _price_band(r) <= price_band]
    if open_now:
        restaurants = [r for r in restaurants if availability_of(r)["is_open"]]
    return restaurants


@router.get("/restaurants", response_model=List[Restaurant])
async def list_restaurants(
    lat: Optional[float] = None,
    lon: Optional[float] = None,
    merchant_id: Optional[str] = None,
    radius_km: float = 10.0,
    sort_by: Optional[str] = None,  # "rating", "delivery_time", "delivery_fee", "distance"
    dietary: Optional[str] = None,  # comma-separated: "Vegetarian,Vegan"
    category: Optional[str] = None,  # comma-separated: "Pizza,Burgers"
    free_delivery: bool = False,
    min_rating: Optional[float] = None,
    has_promotions: bool = False,
    max_delivery_minutes: Annotated[Optional[int], Query(ge=1)] = None,
    price_band: Annotated[Optional[int], Query(ge=1, le=4)] = None,
    open_now: bool = False,
    include_closed: bool = True,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
):
    """Browse restaurants.

    With no explicit `sort_by`, results come back in discovery rank order
    (distance × rating × delivery speed × promotions × open-now) — the same
    formula `/catalog/search` uses with the relevance term held at 1.0.
    Closed restaurants are demoted, not hidden, unless `open_now=true`.
    """
    pool = _pool_size(offset, limit)

    if merchant_id:
        # A merchant's own back-office listing: every restaurant they own,
        # including delisted ones, newest last.
        restaurants = await _apply_page(
            Restaurant.find(Restaurant.merchant_id == merchant_id), 0, pool
        ).to_list()
    elif lat is not None and lon is not None:
        # Geospatial query using the 2dsphere index. $near already returns
        # nearest-first, which bounds the candidate pool sensibly.
        restaurants = await _apply_page(
            Restaurant.find(
                {
                    "location": {
                        "$near": {
                            "$geometry": {"type": "Point", "coordinates": [lon, lat]},
                            "$maxDistance": radius_km * 1000,
                        }
                    },
                    "is_active": True,
                }
            ),
            0,
            pool,
        ).to_list()
    else:
        restaurants = await _apply_page(
            Restaurant.find(Restaurant.is_active == True), 0, pool  # noqa: E712
        ).to_list()

    restaurants = _apply_filters(
        restaurants,
        free_delivery=free_delivery,
        min_rating=min_rating,
        dietary=dietary,
        category=category,
        has_promotions=has_promotions,
        max_delivery_minutes=max_delivery_minutes,
        price_band=price_band,
        open_now=open_now,
    )
    if not include_closed:
        restaurants = [r for r in restaurants if availability_of(r)["is_open"]]

    if sort_by == "rating":
        restaurants.sort(key=lambda r: r.rating, reverse=True)
    elif sort_by == "delivery_time":
        restaurants.sort(key=lambda r: r.delivery_time_min)
    elif sort_by == "delivery_fee":
        restaurants.sort(key=lambda r: r.delivery_fee_usd)
    elif merchant_id is None:
        ranked = search_service.rank(
            restaurants, lat=lat, lng=lon, radius_km=radius_km
        )
        restaurants = [search_service.attach_discovery(entry) for entry in ranked]

    return restaurants[offset : offset + limit]

@router.post("/restaurants", response_model=Restaurant)
async def create_restaurant(restaurant_in: RestaurantCreate, current_user: User = Depends(get_current_user)):
    if current_user.role != "merchant":
        raise HTTPException(status_code=403, detail="Only merchants can create restaurants")
        
    restaurant = Restaurant(
        name=restaurant_in.name,
        description=restaurant_in.description,
        categories=restaurant_in.categories,
        delivery_time_min=restaurant_in.delivery_time_min,
        delivery_time_max=restaurant_in.delivery_time_max,
        delivery_fee_usd=restaurant_in.delivery_fee_usd,
        location=Location(coordinates=[restaurant_in.lng, restaurant_in.lat]),
        merchant_id=str(current_user.id),
        image_url=restaurant_in.image_url,
        free_delivery_threshold=restaurant_in.free_delivery_threshold,
        is_zvingo_plus=restaurant_in.is_zvingo_plus,
        menu=[]
    )
    if settings.DEV_FORCE_DEFAULT_RESTAURANT_LOCATION:
        default_lat, default_lng = get_default_restaurant_coords()
        restaurant.location = Location(coordinates=[default_lng, default_lat])
    await restaurant.insert()
    return restaurant

@router.get("/restaurants/{restaurant_id}", response_model=Restaurant)
async def get_restaurant(restaurant_id: str):
    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")
    return restaurant

class RestaurantUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    image_url: Optional[str] = None
    banner_url: Optional[str] = None
    delivery_time_min: Optional[int] = None
    delivery_time_max: Optional[int] = None
    delivery_fee_usd: Optional[float] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    free_delivery_threshold: Optional[float] = None
    is_zvingo_plus: Optional[bool] = None
    review_count: Optional[int] = None
    neighbors_liked: Optional[int] = None
    customer_photos_count: Optional[int] = None
    is_active: Optional[bool] = None
    operating_hours: Optional[str] = None
    address: Optional[str] = None

@router.put("/restaurants/{restaurant_id}", response_model=Restaurant)
async def update_restaurant(restaurant_id: str, restaurant_in: RestaurantUpdate, current_user: User = Depends(get_current_user)):
    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")
        
    if restaurant.merchant_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to edit this restaurant")
    
    if restaurant_in.name is not None:
        restaurant.name = restaurant_in.name
    if restaurant_in.description is not None:
        restaurant.description = restaurant_in.description
    if restaurant_in.image_url is not None:
        restaurant.image_url = restaurant_in.image_url
    if restaurant_in.banner_url is not None:
        restaurant.banner_url = restaurant_in.banner_url
    if restaurant_in.delivery_time_min is not None:
        restaurant.delivery_time_min = restaurant_in.delivery_time_min
    if restaurant_in.delivery_time_max is not None:
        restaurant.delivery_time_max = restaurant_in.delivery_time_max
    if restaurant_in.delivery_fee_usd is not None:
        restaurant.delivery_fee_usd = restaurant_in.delivery_fee_usd
    if restaurant_in.free_delivery_threshold is not None:
        restaurant.free_delivery_threshold = restaurant_in.free_delivery_threshold
    if restaurant_in.is_zvingo_plus is not None:
        restaurant.is_zvingo_plus = restaurant_in.is_zvingo_plus
    if restaurant_in.review_count is not None:
        restaurant.review_count = restaurant_in.review_count
    if restaurant_in.neighbors_liked is not None:
        restaurant.neighbors_liked = restaurant_in.neighbors_liked
    if restaurant_in.customer_photos_count is not None:
        restaurant.customer_photos_count = restaurant_in.customer_photos_count
    if restaurant_in.is_active is not None:
        restaurant.is_active = restaurant_in.is_active
    if restaurant_in.operating_hours is not None:
        restaurant.operating_hours = restaurant_in.operating_hours
        # Bridge the legacy "08:00-22:00" free-text field into the structured
        # week so restaurants saved by the old dashboard get real availability.
        bridged = parse_legacy_hours(restaurant_in.operating_hours)
        if bridged:
            restaurant.hours = bridged
    if restaurant_in.address is not None:
        restaurant.address = restaurant_in.address

    if (restaurant_in.lat is None) ^ (restaurant_in.lng is None):
        raise HTTPException(status_code=400, detail="Both lat and lng are required to update location")
    if restaurant_in.lat is not None and restaurant_in.lng is not None:
        restaurant.location = Location(coordinates=[restaurant_in.lng, restaurant_in.lat])
        
    await restaurant.save()
    return restaurant

# ────────────────────────────────────────────────────────────────────
# Store availability — open/closed toggle, pause, and weekly hours
# ────────────────────────────────────────────────────────────────────


class RestaurantStatusUpdate(BaseModel):
    """Everything a merchant can change about *when* they are open.

    All fields are optional and only applied when present, so the dashboard can
    PATCH the toggle alone without resending the whole week. `is_open_override`
    is explicitly tri-state: `true` forces open, `false` forces closed, and
    `null` hands control back to `hours`.
    """

    is_open_override: Optional[bool] = None
    #: Convenience snooze: closes the store for N minutes from now.
    pause_minutes: Optional[int] = Field(default=None, ge=1, le=24 * 60)
    #: Explicit resume instant (UTC). Mutually exclusive with `pause_minutes`.
    pause_until: Optional[datetime] = None
    #: Cancel an active pause immediately.
    resume: bool = False
    hours: Optional[List[DayHours]] = None
    timezone: Optional[str] = None
    accepts_scheduled_orders: Optional[bool] = None
    #: Platform listing switch — distinct from "closed right now".
    is_active: Optional[bool] = None


def _availability_payload(restaurant) -> dict:
    return {
        "restaurant_id": str(restaurant.id),
        "is_active": restaurant.is_active,
        "is_open_override": getattr(restaurant, "is_open_override", None),
        "pause_until": (
            restaurant.pause_until.isoformat()
            if getattr(restaurant, "pause_until", None)
            else None
        ),
        "timezone": getattr(restaurant, "timezone", DEFAULT_TIMEZONE),
        "hours": [
            h.model_dump() if hasattr(h, "model_dump") else h
            for h in (getattr(restaurant, "hours", None) or [])
        ],
        "operating_hours": getattr(restaurant, "operating_hours", None),
        "accepts_scheduled_orders": getattr(
            restaurant, "accepts_scheduled_orders", True
        ),
        "availability": availability_of(restaurant),
    }


@router.get("/restaurants/{restaurant_id}/status")
async def get_restaurant_status(restaurant_id: str):
    """Current open/closed state and the weekly schedule behind it."""
    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")
    return _availability_payload(restaurant)


@router.patch("/restaurants/{restaurant_id}/status")
async def update_restaurant_status(
    restaurant_id: str,
    status_in: RestaurantStatusUpdate,
    current_user: User = Depends(get_current_user),
):
    """Set the open/closed override, pause the store, or replace the schedule."""
    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")
    if restaurant.merchant_id != str(current_user.id):
        raise HTTPException(
            status_code=403, detail="Not authorized to edit this restaurant"
        )

    provided = status_in.model_dump(exclude_unset=True)

    if "hours" in provided:
        try:
            week = normalise_week(status_in.hours or [])
        except (InvalidHours, ValueError) as e:
            raise HTTPException(status_code=400, detail=str(e))
        restaurant.hours = week
        # Keep the legacy display string in step so older clients stay correct.
        restaurant.operating_hours = describe_week(week) or None

    if "timezone" in provided and status_in.timezone:
        restaurant.timezone = status_in.timezone

    if "is_open_override" in provided:
        restaurant.is_open_override = status_in.is_open_override

    if status_in.pause_minutes is not None and status_in.pause_until is not None:
        raise HTTPException(
            status_code=400, detail="Send either pause_minutes or pause_until, not both"
        )
    if status_in.resume:
        restaurant.pause_until = None
    elif status_in.pause_minutes is not None:
        restaurant.pause_until = utc_now() + timedelta(minutes=status_in.pause_minutes)
    elif "pause_until" in provided:
        pause_until = status_in.pause_until
        if pause_until is not None and pause_until.tzinfo is not None:
            pause_until = pause_until.astimezone(dt_timezone.utc).replace(tzinfo=None)
        restaurant.pause_until = pause_until

    if status_in.accepts_scheduled_orders is not None:
        restaurant.accepts_scheduled_orders = status_in.accepts_scheduled_orders

    if status_in.is_active is not None:
        restaurant.is_active = status_in.is_active

    await restaurant.save()
    return _availability_payload(restaurant)


@router.post("/restaurants/{restaurant_id}/menu", response_model=Restaurant)
async def add_menu_item(restaurant_id: str, item_in: MenuItemCreate, current_user: User = Depends(get_current_user)):
    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")
        
    if restaurant.merchant_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to edit this restaurant")
        
    new_item = MenuItem(
        name=item_in.name,
        description=item_in.description,
        price_usd=item_in.price_usd,
        category=item_in.category,
        image_url=item_in.image_url,
        images=item_in.images,
        is_available=True,
        approval_percent=item_in.approval_percent,
        approval_count=item_in.approval_count,
        is_great_price=item_in.is_great_price,
    )
    
    restaurant.menu.append(new_item)
    await restaurant.save()
    return restaurant

@router.put("/restaurants/{restaurant_id}/menu/{item_id}", response_model=Restaurant)
async def update_menu_item(restaurant_id: str, item_id: str, item_in: MenuItemUpdate, current_user: User = Depends(get_current_user)):
    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")
        
    if restaurant.merchant_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to edit this restaurant")
    
    item_found = False
    for item in restaurant.menu:
        if item.id == item_id:
            item_found = True
            if item_in.is_available is not None:
                item.is_available = item_in.is_available
            if item_in.name:
                item.name = item_in.name
            if item_in.price_usd is not None:
                item.price_usd = item_in.price_usd
            if item_in.category:
                item.category = item_in.category
            if item_in.description:
                item.description = item_in.description
            if item_in.image_url:
                item.image_url = item_in.image_url
            if item_in.images is not None:
                item.images = item_in.images
            if item_in.approval_percent is not None:
                item.approval_percent = item_in.approval_percent
            if item_in.approval_count is not None:
                item.approval_count = item_in.approval_count
            if item_in.is_great_price is not None:
                item.is_great_price = item_in.is_great_price
            break
            
    if not item_found:
        raise HTTPException(status_code=404, detail="Menu item not found")
        
    await restaurant.save()
    return restaurant

@router.delete("/restaurants/{restaurant_id}/menu/{item_id}", response_model=Restaurant)
async def delete_menu_item(restaurant_id: str, item_id: str, current_user: User = Depends(get_current_user)):
    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")

    if restaurant.merchant_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to edit this restaurant")

    original_len = len(restaurant.menu)
    restaurant.menu = [item for item in restaurant.menu if item.id != item_id]

    if len(restaurant.menu) == original_len:
        raise HTTPException(status_code=404, detail="Menu item not found")

    await restaurant.save()
    return restaurant


def _candidate_query(q: str) -> dict:
    """Mongo pre-filter for search.

    A broad, index-friendly `$or` over the same fields the ranker scores. It is
    deliberately *recall-oriented*: the regex catches substrings the text index
    would miss, and the Python ranker does the precise, typo-tolerant scoring
    on the resulting pool. Each token is matched separately so "cheese burger"
    still finds "Cheeseburger Palace".
    """
    tokens = [t for t in search_service.tokenize(q) if len(t) >= 2][:4]
    if not tokens:
        tokens = [q.strip()]
    clauses = []
    for token in tokens:
        pattern = re.escape(token)
        clauses.extend(
            [
                {"name": {"$regex": pattern, "$options": "i"}},
                {"description": {"$regex": pattern, "$options": "i"}},
                {"categories": {"$regex": pattern, "$options": "i"}},
                {"dietary_tags": {"$regex": pattern, "$options": "i"}},
                {"menu.name": {"$regex": pattern, "$options": "i"}},
                {"menu.category": {"$regex": pattern, "$options": "i"}},
            ]
        )
    return {"$or": clauses}


@router.get("/search", response_model=List[Restaurant])
async def search_catalog(
    q: str = "",
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    radius_km: float = 10.0,
    dietary: Optional[str] = None,
    category: Optional[str] = None,
    free_delivery: bool = False,
    min_rating: Optional[float] = None,
    max_delivery_minutes: Annotated[Optional[int], Query(ge=1)] = None,
    price_band: Annotated[Optional[int], Query(ge=1, le=4)] = None,
    open_now: bool = False,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
):
    """Typo-tolerant search across restaurant name, cuisine, and menu items.

    Each result carries a `discovery` block (`score`, `relevance`,
    `distance_km`, `matched_menu_items`) and an `availability` block, so the
    UI can explain *why* a restaurant is in the list and whether it is open.
    The ranking formula is documented in `app.catalog.search_service`.
    """
    if not q or len(q.strip()) < search_service.MIN_QUERY_LENGTH:
        return []

    restaurants = await _apply_page(
        Restaurant.find(_candidate_query(q)), 0, _pool_size(offset, limit)
    ).to_list()

    restaurants = [r for r in restaurants if getattr(r, "is_active", True)]
    restaurants = _apply_filters(
        restaurants,
        free_delivery=free_delivery,
        min_rating=min_rating,
        dietary=dietary,
        category=category,
        max_delivery_minutes=max_delivery_minutes,
        price_band=price_band,
        open_now=open_now,
    )

    ranked = search_service.rank(
        restaurants, query=q, lat=lat, lng=lng, radius_km=radius_km
    )
    page = ranked[offset : offset + limit]
    return [search_service.attach_discovery(entry) for entry in page]


@router.get("/restaurants/{restaurant_id}/search", response_model=List[MenuItem])
async def search_restaurant_items(
    restaurant_id: str,
    q: str = "",
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = 50,
):
    """Typo-tolerant search within a single restaurant's menu, best match first."""
    if not q or len(q.strip()) < search_service.MIN_QUERY_LENGTH:
        return []

    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")

    tokens = search_service.tokenize(q)
    scored = []
    for item in restaurant.menu:
        haystacks = [
            (search_service.normalise(item.name), 1.0),
            (search_service.normalise(item.category), 0.7),
            (search_service.normalise(item.description), 0.5),
        ]
        total = 0.0
        for token in tokens:
            best = max(
                search_service.token_score(token, text) * weight
                for text, weight in haystacks
            )
            if best <= 0:
                total = 0.0
                break
            total += best
        if total > 0:
            scored.append((total / max(len(tokens), 1), item))

    scored.sort(key=lambda pair: (-pair[0], pair[1].name))
    return [item for _score, item in scored[offset : offset + limit]]


# ────────────────────────────────────────────────────────────────────
# Promotions CRUD
# ────────────────────────────────────────────────────────────────────

class PromotionCreate(BaseModel):
    title: str
    subtitle: str
    description: Optional[str] = None
    icon: str = "local_offer"
    promo_type: str = "percentage"  # percentage | flat | free_delivery | free_item
    discount_value: float = 0.0
    min_order_usd: float = 0.0
    max_discount_usd: Optional[float] = None
    free_item_id: Optional[str] = None
    free_item_name: Optional[str] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    max_uses: Optional[int] = None
    max_uses_per_user: int = 1
    code: Optional[str] = None
    restaurant_id: Optional[str] = None
    #: Restrict the promo to consumers who have never completed an order.
    first_order_only: bool = False


async def _assert_owns_restaurant(restaurant_id: Optional[str], current_user: User) -> None:
    """A merchant may only scope a promotion to a restaurant they own.

    Without this a merchant could publish a promo that burns a *competitor's*
    margin, because promo scoping is what order creation checks at redemption.
    """
    if not restaurant_id:
        return
    try:
        restaurant = await Restaurant.get(restaurant_id)
    except Exception:
        restaurant = None
    if restaurant is None or restaurant.merchant_id != str(current_user.id):
        raise HTTPException(
            status_code=403,
            detail="Not authorized to create promotions for this restaurant",
        )


async def _assert_code_is_free(code: Optional[str], promo_id: Optional[str] = None) -> None:
    """Promo codes must be globally unique — they are the redemption key.

    Two promos sharing a code means `compute_discount` and `record_redemption`
    can pick different documents, so one is validated and the other charged.
    """
    if not code:
        return
    existing = await Promotion.find_one({"code": code})
    if existing is not None and str(existing.id) != str(promo_id or ""):
        raise HTTPException(
            status_code=409, detail=f"Promo code '{code}' is already in use"
        )


class PromotionUpdate(BaseModel):
    title: Optional[str] = None
    subtitle: Optional[str] = None
    description: Optional[str] = None
    icon: Optional[str] = None
    promo_type: Optional[str] = None
    discount_value: Optional[float] = None
    min_order_usd: Optional[float] = None
    max_discount_usd: Optional[float] = None
    free_item_id: Optional[str] = None
    free_item_name: Optional[str] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    is_active: Optional[bool] = None
    max_uses: Optional[int] = None
    max_uses_per_user: Optional[int] = None
    code: Optional[str] = None
    restaurant_id: Optional[str] = None
    first_order_only: Optional[bool] = None


# ── Public: consumer-facing active promotions ──────────────────────

@router.get(
    "/promotions",
    response_model=List[Promotion],
    response_model_exclude={"__all__": {"redeemed_by", "redemptions_by_user"}},
)
async def list_active_promotions(
    restaurant_id: Optional[str] = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
):
    """Return all currently active promotions visible to consumers."""
    now = utc_now()
    query: dict = {"is_active": True}

    # Only include promos that haven't expired
    query["$or"] = [
        {"ends_at": None},
        {"ends_at": {"$gt": now}},
    ]

    # Filter promos that have already started
    query["starts_at"] = {"$lte": now}

    # Optionally filter by restaurant
    if restaurant_id:
        query["$and"] = [
            {"$or": [{"restaurant_id": restaurant_id}, {"restaurant_id": None}]}
        ]

    promotions = await _apply_page(
        Promotion.find(query).sort("-created_at"), 0, _pool_size(offset, limit)
    ).to_list()

    # Exclude promos that have hit their usage cap
    live = [p for p in promotions if p.max_uses is None or p.current_uses < p.max_uses]
    return live[offset : offset + limit]


class PromoValidateRequest(BaseModel):
    code: str
    order_subtotal_usd: float
    # Cart lines ({"id"?, "name", "price", "quantity"}) — required to preview a
    # `free_item` promo, ignored by every other promo type.
    items: List[dict] = []
    # Restaurant the cart is for — either a Restaurant document id or a
    # Restaurant.merchant_id. Required to preview a restaurant-scoped promo;
    # omitting it previews as if no restaurant were known, so a scoped promo
    # is (correctly) rejected.
    restaurant_id: Optional[str] = None


@router.post("/promotions/validate")
async def validate_promo_code(
    req: PromoValidateRequest, current_user: User = Depends(get_current_user)
):
    """Validate a promo code and return the discount the consumer would get.

    This is a read-only preview; redemption is recorded when an order using the
    code is actually created.
    """
    from app.catalog.promotion_service import (
        validate_and_compute,
        resolve_restaurant_id,
        PromotionError,
    )
    try:
        discount, free_delivery = await validate_and_compute(
            req.code,
            str(current_user.id),
            req.order_subtotal_usd,
            req.items,
            restaurant_id=await resolve_restaurant_id(req.restaurant_id),
        )
    except PromotionError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {
        "code": req.code,
        "discount_usd": discount,
        "free_delivery": free_delivery,
    }


# ── Merchant: CRUD for own promotions ──────────────────────────────

@router.get("/promotions/merchant", response_model=List[Promotion])
async def list_merchant_promotions(
    current_user: User = Depends(get_current_user),
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = DEFAULT_PAGE_SIZE,
):
    """List all promotions belonging to the logged-in merchant."""
    promotions = await _apply_page(
        Promotion.find(Promotion.merchant_id == str(current_user.id)).sort(
            "-created_at"
        ),
        offset,
        limit,
    ).to_list()
    return promotions


@router.post("/promotions", response_model=Promotion, status_code=status.HTTP_201_CREATED)
async def create_promotion(promo_in: PromotionCreate, current_user: User = Depends(get_current_user)):
    """Create a new promotion for this merchant."""
    if current_user.role != "merchant":
        raise HTTPException(status_code=403, detail="Only merchants can create promotions")

    if promo_in.promo_type not in SUPPORTED_PROMO_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"promo_type must be one of {', '.join(SUPPORTED_PROMO_TYPES)}",
        )
    if promo_in.promo_type == "free_item" and not (
        promo_in.free_item_id or promo_in.free_item_name
    ):
        raise HTTPException(
            status_code=400,
            detail="free_item promotions require free_item_id or free_item_name",
        )
    await _assert_owns_restaurant(promo_in.restaurant_id, current_user)
    await _assert_code_is_free(promo_in.code)

    promo = Promotion(
        merchant_id=str(current_user.id),
        restaurant_id=promo_in.restaurant_id,
        title=promo_in.title,
        subtitle=promo_in.subtitle,
        description=promo_in.description,
        icon=promo_in.icon,
        promo_type=promo_in.promo_type,
        discount_value=promo_in.discount_value,
        min_order_usd=promo_in.min_order_usd,
        max_discount_usd=promo_in.max_discount_usd,
        free_item_id=promo_in.free_item_id,
        free_item_name=promo_in.free_item_name,
        starts_at=promo_in.starts_at or utc_now(),
        ends_at=promo_in.ends_at,
        max_uses=promo_in.max_uses,
        max_uses_per_user=promo_in.max_uses_per_user,
        code=promo_in.code,
        first_order_only=promo_in.first_order_only,
        is_active=True,
    )
    await promo.insert()
    return promo


@router.get(
    "/promotions/{promo_id}",
    response_model=Promotion,
    response_model_exclude={"redeemed_by", "redemptions_by_user"},
)
async def get_promotion(promo_id: str):
    """Get a single promotion by its document ID."""
    promo = await Promotion.get(promo_id)
    if not promo:
        raise HTTPException(status_code=404, detail="Promotion not found")
    return promo


@router.put("/promotions/{promo_id}", response_model=Promotion)
async def update_promotion(promo_id: str, promo_in: PromotionUpdate, current_user: User = Depends(get_current_user)):
    """Update a promotion. Only the owning merchant can edit."""
    promo = await Promotion.get(promo_id)
    if not promo:
        raise HTTPException(status_code=404, detail="Promotion not found")
    if promo.merchant_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to edit this promotion")

    update_data = promo_in.model_dump(exclude_unset=True)
    if "restaurant_id" in update_data:
        await _assert_owns_restaurant(update_data["restaurant_id"], current_user)
    if "code" in update_data:
        await _assert_code_is_free(update_data["code"], promo_id=promo.id)
    new_type = update_data.get("promo_type")
    if new_type is not None and new_type not in SUPPORTED_PROMO_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"promo_type must be one of {', '.join(SUPPORTED_PROMO_TYPES)}",
        )
    for field, value in update_data.items():
        setattr(promo, field, value)
    promo.updated_at = utc_now()
    await promo.save()
    return promo


@router.delete("/promotions/{promo_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_promotion(promo_id: str, current_user: User = Depends(get_current_user)):
    """Delete a promotion. Only the owning merchant can delete."""
    promo = await Promotion.get(promo_id)
    if not promo:
        raise HTTPException(status_code=404, detail="Promotion not found")
    if promo.merchant_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized to delete this promotion")

    await promo.delete()
    return None


@router.patch("/promotions/{promo_id}/toggle", response_model=Promotion)
async def toggle_promotion(promo_id: str, current_user: User = Depends(get_current_user)):
    """Toggle a promotion's active status."""
    promo = await Promotion.get(promo_id)
    if not promo:
        raise HTTPException(status_code=404, detail="Promotion not found")
    if promo.merchant_id != str(current_user.id):
        raise HTTPException(status_code=403, detail="Not authorized")

    promo.is_active = not promo.is_active
    promo.updated_at = utc_now()
    await promo.save()
    return promo


# --- Dev admin ---
@router.post("/admin/reset-locations")
async def reset_restaurant_locations(
    force_all: bool = True, _: User = Depends(get_current_admin)
):
    """Dev-only: reset all restaurant locations to the default emulator area.

    Requires both the `DEV_ALLOW_ADMIN_ENDPOINTS` flag *and* an admin caller —
    it rewrites every restaurant's coordinates, which would be catastrophic if
    it were reachable by anyone who guessed the URL.
    """
    if not settings.DEV_ALLOW_ADMIN_ENDPOINTS:
        raise HTTPException(status_code=403, detail="Admin endpoints disabled")
    await backfill_restaurant_locations(force_all=force_all)
    return {"status": "ok", "force_all": force_all}
