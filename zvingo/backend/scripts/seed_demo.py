#!/usr/bin/env python3
"""Seed a Zvingo backend with realistic demo data.

Talks to the API over HTTP rather than to the database, so it works against
anything: `docker compose up`, a bare uvicorn, or a deployed staging host. Pure
standard library — no dependencies to install.

    python backend/scripts/seed_demo.py
    python backend/scripts/seed_demo.py --base-url http://localhost:8000
    ZVINGO_API=http://localhost:8000 python backend/scripts/seed_demo.py

Re-running is safe: accounts are signed in rather than re-registered, and
restaurants that already exist are skipped. Orders are *not* deduplicated --
each run adds a couple more to the board, which is what you want for a demo.

Never point this at production. It creates accounts with a known password.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_BASE_URL = os.environ.get("ZVINGO_API", "http://127.0.0.1:8000")

#: Same password for every demo account, so a demo is easy to drive by hand.
DEMO_PASSWORD = "ZvingoDev2026!"

HARARE = (-17.8292, 31.0522)


# ── HTTP ────────────────────────────────────────────────────────────────

class ApiError(RuntimeError):
    def __init__(self, status: int, body: str):
        super().__init__(f"HTTP {status}: {body[:400]}")
        self.status = status
        self.body = body


def request(base: str, method: str, path: str, *, token=None, json_body=None, form=None):
    url = f"{base.rstrip('/')}{path}"
    headers = {"Accept": "application/json"}
    data = None

    if json_body is not None:
        data = json.dumps(json_body).encode()
        headers["Content-Type"] = "application/json"
    elif form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"

    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    # A demo seeder must not be routed through a corporate proxy to reach
    # localhost; an empty handler set bypasses the environment's proxy config.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(req, timeout=30) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, e.read().decode()) from None


# ── Accounts ────────────────────────────────────────────────────────────

def sign_in_or_register(base: str, *, full_name: str, phone: str, email: str, role: str) -> str:
    """Return an access token, registering the account only if it is new.

    Sign-in is tried *first*. Registration is rate-limited per IP (correctly --
    it is how you stop bulk account creation), and a seeder re-run from one
    machine burns that budget immediately. Asking to log in first means a
    re-run costs nothing, and registration is only attempted for an account
    that genuinely does not exist yet.
    """
    # Login is OAuth2 form-encoded at /auth/token, not JSON at /auth/login.
    try:
        body = request(base, "POST", "/auth/token",
                       form={"username": phone, "password": DEMO_PASSWORD})
        print(f"  signed in  {role:<9} {full_name} ({phone})")
        return body["access_token"]
    except ApiError as e:
        if e.status not in (400, 401, 403, 404, 422):
            raise

    try:
        body = request(
            base, "POST", "/auth/register",
            json_body={
                "full_name": full_name,
                "phone": phone,
                "email": email,
                "password": DEMO_PASSWORD,
                "role": role,
            },
        )
        print(f"  registered {role:<9} {full_name} ({phone})")
        return body["access_token"]
    except ApiError as e:
        if e.status == 429:
            raise SystemExit(
                f"\nRegistration is rate-limited for this IP, and {phone} does not\n"
                f"exist yet so it cannot be signed in either. Wait for the window to\n"
                f"expire, or clear the limiter:  redis-cli --scan --pattern "
                f"'rate_limit:register:*' | xargs redis-cli del\n"
            ) from None
        raise


def user_id(base: str, token: str) -> str:
    me = request(base, "GET", "/auth/me", token=token)
    return me.get("id") or me.get("_id")


# ── Catalog ─────────────────────────────────────────────────────────────

RESTAURANTS = [
    {
        "name": "Kombi Cafe",
        "description": "Zimbabwean street food, fast and generous.",
        "cuisine": "Zimbabwean",
        "address": "12 Samora Machel Ave, Harare",
        "lat": -17.8292, "lng": 31.0522,
        "delivery_fee": 2.50,
        "menu": [
            ("Sadza & Beef Stew", "Slow-cooked beef, house sadza", 6.50, "Mains"),
            ("Sadza & Road Runner", "Free-range chicken", 7.50, "Mains"),
            ("Grilled Chicken & Chips", "Half chicken, hand-cut chips", 8.00, "Mains"),
            ("Maheu", "Traditional maize drink", 1.50, "Drinks"),
            ("Mazoe Orange Crush", "300ml", 1.20, "Drinks"),
        ],
    },
    {
        "name": "Avondale Grill House",
        "description": "Flame-grilled steaks and burgers.",
        "cuisine": "Grill",
        "address": "5 King George Rd, Avondale, Harare",
        "lat": -17.8005, "lng": 31.0350,
        "delivery_fee": 3.00,
        "menu": [
            ("Rump Steak 300g", "Served with chips and salad", 14.00, "Grills"),
            ("Boerewors Roll", "Farm sausage, onion relish", 5.50, "Grills"),
            ("Double Cheeseburger", "Two patties, cheddar", 9.00, "Burgers"),
            ("Peri-Peri Wings", "Six wings, medium heat", 6.00, "Starters"),
        ],
    },
    {
        "name": "Borrowdale Pizza Co.",
        "description": "Wood-fired pizza and pasta.",
        "cuisine": "Italian",
        "address": "Sam Levy's Village, Borrowdale, Harare",
        "lat": -17.7550, "lng": 31.0900,
        "delivery_fee": 3.50,
        "menu": [
            ("Margherita", "Tomato, mozzarella, basil", 8.00, "Pizza"),
            ("Pepperoni Pizza", "Double pepperoni", 10.50, "Pizza"),
            ("Four Seasons", "Ham, mushroom, olive, pepper", 11.50, "Pizza"),
            ("Spaghetti Bolognese", "Slow beef ragu", 9.50, "Pasta"),
        ],
    },
]


def seed_catalog(base: str, token: str) -> list[dict]:
    existing = {
        r["name"]: (r.get("_id") or r.get("id"))
        for r in (request(base, "GET", "/catalog/restaurants", token=token) or [])
    }

    seeded = []
    for spec in RESTAURANTS:
        if spec["name"] in existing:
            print(f"  exists     {spec['name']}")
            seeded.append({"id": existing[spec["name"]], "name": spec["name"]})
            continue

        created = request(
            base, "POST", "/catalog/restaurants", token=token,
            json_body={
                "name": spec["name"],
                "description": spec["description"],
                "cuisine": spec["cuisine"],
                "address": spec["address"],
                "lat": spec["lat"],
                "lng": spec["lng"],
                "delivery_fee": spec["delivery_fee"],
            },
        )
        rid = created.get("_id") or created.get("id")

        for name, description, price, category in spec["menu"]:
            request(
                base, "POST", f"/catalog/restaurants/{rid}/menu", token=token,
                json_body={
                    "name": name,
                    "description": description,
                    "price_usd": price,
                    "category": category,
                    "is_available": True,
                },
            )
        print(f"  created    {spec['name']} with {len(spec['menu'])} menu items")
        seeded.append({"id": rid, "name": spec["name"]})

    return seeded


# ── Orders ──────────────────────────────────────────────────────────────

def place_order(base: str, consumer_token: str, restaurant_id: str, merchant_token: str):
    """One order, priced exactly the way checkout expects."""
    restaurant = request(base, "GET", f"/catalog/restaurants/{restaurant_id}",
                         token=merchant_token)
    menu = restaurant.get("menu") or []
    if not menu:
        return None

    item = menu[0]
    item_id = item.get("id") or item.get("_id")
    price = item.get("price_usd") or item.get("price") or 0
    quantity = 2

    subtotal = round(price * quantity, 2)
    delivery_fee = restaurant.get("delivery_fee") or 2.50
    service_fee = round(subtotal * 0.05, 2)

    result = request(
        base, "POST", "/orders/checkout", token=consumer_token,
        json_body={
            "baskets": [{
                "merchant_id": restaurant_id,
                "items": [{
                    "menu_item_id": item_id,
                    "name": item["name"],
                    "quantity": quantity,
                    "price": price,
                }],
                "subtotal": subtotal,
                "delivery_fee": delivery_fee,
                "service_fee": service_fee,
            }],
            # Location is GeoJSON: [longitude, latitude], in that order.
            "dropoff": {"type": "Point", "coordinates": [31.0400, -17.8450]},
            "delivery_instructions": "Gate 3, blue door. Call on arrival.",
        },
    )
    total = round(subtotal + delivery_fee + service_fee, 2)
    print(f"  order      {quantity}x {item['name']} from {restaurant['name']} "
          f"-> ${total:.2f}")
    return result


# ── Entry point ─────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL,
                        help=f"API base URL (default {DEFAULT_BASE_URL})")
    args = parser.parse_args()
    base = args.base_url

    try:
        health = request(base, "GET", "/health")
    except Exception as e:
        print(f"Cannot reach the API at {base}: {e}", file=sys.stderr)
        print("Is the backend running? `docker compose up` or "
              "`uvicorn app.main:app --reload`", file=sys.stderr)
        return 1
    print(f"API at {base} -> {health}\n")

    print("Accounts")
    merchant = sign_in_or_register(
        base, full_name="Tendai Moyo", phone="+263771234567",
        email="tendai@kombicafe.co.zw", role="merchant")
    consumer = sign_in_or_register(
        base, full_name="Rudo Chirwa", phone="+263772223333",
        email="rudo@example.co.zw", role="consumer")
    driver = sign_in_or_register(
        base, full_name="Farai Ncube", phone="+263773334444",
        email="farai@example.co.zw", role="driver")

    print("\nCatalog")
    restaurants = seed_catalog(base, merchant)

    print("\nOrders")
    for restaurant in restaurants[:2]:
        try:
            place_order(base, consumer, restaurant["id"], merchant)
        except ApiError as e:
            print(f"  skipped    {restaurant['name']}: {e}")

    merchant_id = user_id(base, merchant)
    print(f"""
Done.

  Merchant   +263771234567  /  {DEMO_PASSWORD}
  Consumer   +263772223333  /  {DEMO_PASSWORD}
  Driver     +263773334444  /  {DEMO_PASSWORD}

  Merchant user id: {merchant_id}
  Dashboard:        http://localhost:3000/login
""")
    _ = driver
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
