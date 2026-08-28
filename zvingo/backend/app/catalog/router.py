from fastapi import APIRouter, HTTPException, Depends, status
from typing import List, Optional
from app.catalog.models import Restaurant, MenuItem, Location
from app.catalog.maintenance import get_default_restaurant_coords, backfill_restaurant_locations
from app.config import settings
from app.catalog.promotion_models import Promotion
from app.catalog.promotion_service import SUPPORTED_PROMO_TYPES
from app.auth.router import get_current_user, User
from pydantic import BaseModel
import re
from datetime import datetime
from app.time_utils import utc_now

router = APIRouter()

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

@router.get("/restaurants", response_model=List[Restaurant])
async def list_restaurants(
    lat: Optional[float] = None,
    lon: Optional[float] = None,
    merchant_id: Optional[str] = None,
    radius_km: float = 10.0,
    sort_by: Optional[str] = None,  # "rating", "delivery_time", "delivery_fee"
    dietary: Optional[str] = None,  # comma-separated: "Vegetarian,Vegan"
    category: Optional[str] = None,  # comma-separated: "Pizza,Burgers"
    free_delivery: bool = False,
    min_rating: Optional[float] = None,
    has_promotions: bool = False,
):
    if merchant_id:
        restaurants = await Restaurant.find(Restaurant.merchant_id == merchant_id).to_list()
    elif lat is not None and lon is not None:
        # Geospatial query using 2dsphere index
        restaurants = await Restaurant.find(
            {
                "location": {
                    "$near": {
                        "$geometry": {"type": "Point", "coordinates": [lon, lat]},
                        "$maxDistance": radius_km * 1000
                    }
                },
                "is_active": True
            }
        ).to_list()
    else:
        restaurants = await Restaurant.find(Restaurant.is_active == True).to_list()

    # Apply filters
    if free_delivery:
        restaurants = [r for r in restaurants if r.delivery_fee_usd == 0]
    if min_rating is not None:
        restaurants = [r for r in restaurants if r.rating >= min_rating]
    if dietary:
        tags = [t.strip() for t in dietary.split(",")]
        restaurants = [r for r in restaurants if any(t in r.dietary_tags for t in tags)]
    if category:
        cats = [c.strip().lower() for c in category.split(",")]
        restaurants = [r for r in restaurants if any(c in [x.lower() for x in r.categories] for c in cats)]
    if has_promotions:
        restaurants = [r for r in restaurants if r.promotions]

    # Apply sorting
    if sort_by == "rating":
        restaurants.sort(key=lambda r: r.rating, reverse=True)
    elif sort_by == "delivery_time":
        restaurants.sort(key=lambda r: r.delivery_time_min)
    elif sort_by == "delivery_fee":
        restaurants.sort(key=lambda r: r.delivery_fee_usd)

    return restaurants

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
    if restaurant_in.address is not None:
        restaurant.address = restaurant_in.address

    if (restaurant_in.lat is None) ^ (restaurant_in.lng is None):
        raise HTTPException(status_code=400, detail="Both lat and lng are required to update location")
    if restaurant_in.lat is not None and restaurant_in.lng is not None:
        restaurant.location = Location(coordinates=[restaurant_in.lng, restaurant_in.lat])
        
    await restaurant.save()
    return restaurant

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


@router.get("/search")
async def search_catalog(q: str = ""):
    if not q or len(q) < 2:
        return []
    
    # Search restaurants by name (case-insensitive)
    pattern = re.compile(re.escape(q), re.IGNORECASE)
    restaurants = await Restaurant.find(
        {"$or": [
            {"name": {"$regex": pattern.pattern, "$options": "i"}},
            {"description": {"$regex": pattern.pattern, "$options": "i"}},
            {"categories": {"$regex": pattern.pattern, "$options": "i"}},
            {"menu.name": {"$regex": pattern.pattern, "$options": "i"}},
        ]}
    ).to_list()
    
    return restaurants

@router.get("/restaurants/{restaurant_id}/search", response_model=List[MenuItem])
async def search_restaurant_items(restaurant_id: str, q: str = ""):
    if not q or len(q) < 2:
        return []
    
    restaurant = await Restaurant.get(restaurant_id)
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")
        
    # Filter menu items (case-insensitive)
    items = []
    pattern = re.compile(re.escape(q), re.IGNORECASE)
    
    for item in restaurant.menu:
        if (pattern.search(item.name) or
            (item.description and pattern.search(item.description)) or
            pattern.search(item.category)):
            items.append(item)

    return items


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


# ── Public: consumer-facing active promotions ──────────────────────

@router.get("/promotions", response_model=List[Promotion])
async def list_active_promotions(restaurant_id: Optional[str] = None):
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

    promotions = await Promotion.find(query).sort("-created_at").to_list()

    # Exclude promos that have hit their usage cap
    return [p for p in promotions if p.max_uses is None or p.current_uses < p.max_uses]


class PromoValidateRequest(BaseModel):
    code: str
    order_subtotal_usd: float
    # Cart lines ({"id"?, "name", "price", "quantity"}) — required to preview a
    # `free_item` promo, ignored by every other promo type.
    items: List[dict] = []


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
        PromotionError,
    )
    try:
        discount, free_delivery = await validate_and_compute(
            req.code, str(current_user.id), req.order_subtotal_usd, req.items
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
async def list_merchant_promotions(current_user: User = Depends(get_current_user)):
    """List all promotions belonging to the logged-in merchant."""
    promotions = await Promotion.find(
        Promotion.merchant_id == str(current_user.id)
    ).sort("-created_at").to_list()
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
        is_active=True,
    )
    await promo.insert()
    return promo


@router.get("/promotions/{promo_id}", response_model=Promotion)
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
async def reset_restaurant_locations(force_all: bool = True):
    """Dev-only: reset all restaurant locations to default emulator area."""
    if not settings.DEV_ALLOW_ADMIN_ENDPOINTS:
        raise HTTPException(status_code=403, detail="Admin endpoints disabled")
    await backfill_restaurant_locations(force_all=force_all)
    return {"status": "ok", "force_all": force_all}
