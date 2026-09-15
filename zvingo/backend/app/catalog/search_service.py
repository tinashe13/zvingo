"""Catalog search: typo-tolerant matching and a documented ranking formula.

Search has to answer one question well: *given what the consumer typed and
where they are standing, which restaurants should they see first?*

Matching
--------
The query is normalised (lower-cased, accent-stripped, punctuation removed,
trailing plurals trimmed) and split into tokens. Every token is matched
independently against four fields of a restaurant — **name**, **cuisine /
categories**, **menu item names**, and **description** — so "pizza" finds a
restaurant that sells pizza even when "pizza" is nowhere in its name. A token
that matches nothing exactly falls back to fuzzy matching
(`difflib.SequenceMatcher` ratio >= ``FUZZY_THRESHOLD``), which absorbs the
usual typos: "piza", "chiken", "burgur".

A restaurant matches only when **every** query token matches something
(AND semantics); the relevance score is the mean of the per-token scores.

Ranking
-------
Five normalised [0, 1] signals are combined into a weighted sum and then scaled
by an availability multiplier:

    base  = 0.45 * relevance
          + 0.20 * proximity
          + 0.15 * quality
          + 0.12 * speed
          + 0.08 * promotion

    score = base * availability_multiplier

* **relevance**  best field match per token, averaged (see ``FIELD_WEIGHTS``).
                 1.0 for an exact restaurant-name hit, ~0.45 for a description
                 hit, scaled down by fuzzy distance.
* **proximity**  ``1 - distance_km / radius_km`` clamped to [0, 1]; 1.0 when the
                 consumer sent no location (nothing to prefer).
* **quality**    Bayesian-smoothed star rating,
                 ``(C * PRIOR + rating * n) / (C + n) / 5`` with ``C = 20``
                 reviews of prior weight, so a single 5-star review cannot
                 outrank a well-reviewed 4.6.
* **speed**      ``1 - (delivery_time_min - 10) / 50`` clamped, so a 10-minute
                 promise scores 1.0 and an hour scores 0.
* **promotion**  1.0 when the restaurant has an active promo or free delivery.
* **availability** 1.0 open, 0.55 closed but accepting scheduled orders,
                 0.35 hard-closed. Closed restaurants are *demoted and
                 flagged*, never hidden — a consumer looking for their usual
                 Friday takeaway should still find it and see "Opens 17:00".

Browsing (empty query) uses the same formula with ``relevance`` fixed at 1.0,
which reduces it to distance × rating × speed × promo × open-now.
"""

from __future__ import annotations

import math
import re
import unicodedata
from difflib import SequenceMatcher
from typing import Iterable, List, Optional, Sequence, Tuple

from app.catalog.hours import availability_of

# ── Tunables ────────────────────────────────────────────────────────

WEIGHT_RELEVANCE = 0.45
WEIGHT_PROXIMITY = 0.20
WEIGHT_QUALITY = 0.15
WEIGHT_SPEED = 0.12
WEIGHT_PROMOTION = 0.08

#: Per-field ceiling for an exact token hit.
FIELD_WEIGHTS = {
    "name": 1.00,
    "category": 0.78,
    "menu": 0.72,
    "description": 0.45,
}

#: Minimum SequenceMatcher ratio treated as a typo rather than a different word.
FUZZY_THRESHOLD = 0.72

#: Bayesian prior for the quality signal.
RATING_PRIOR = 4.2
RATING_PRIOR_WEIGHT = 20

#: Delivery-promise band used by the speed signal (minutes).
FASTEST_MINUTES = 10
SLOWEST_MINUTES = 60

AVAILABILITY_MULTIPLIER = {
    "open": 1.0,
    "scheduled": 0.55,
    "closed": 0.35,
}

MIN_QUERY_LENGTH = 2

#: Apostrophes are *removed* rather than turned into a space, so a search for
#: "nandos" matches "Nando's" instead of splitting it into "nando" + "s".
_APOSTROPHE = re.compile(r"['’ʼ]")
_PUNCT = re.compile(r"[^a-z0-9\s]+")
_WS = re.compile(r"\s+")

EARTH_RADIUS_KM = 6371.0


# ── Text normalisation ──────────────────────────────────────────────


def normalise(text: Optional[str]) -> str:
    """Lower-case, strip accents and punctuation, collapse whitespace."""
    if not text:
        return ""
    decomposed = unicodedata.normalize("NFKD", str(text))
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    stripped = _APOSTROPHE.sub("", stripped.lower())
    return _WS.sub(" ", _PUNCT.sub(" ", stripped)).strip()


def _singular(token: str) -> str:
    """Crude de-pluralisation so "burgers" and "burger" are one token."""
    if len(token) > 3 and token.endswith("ies"):
        return token[:-3] + "y"
    if len(token) > 3 and token.endswith("es") and token[-3] in "sxzh":
        return token[:-2]
    if len(token) > 3 and token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def tokenize(text: Optional[str]) -> List[str]:
    return [_singular(t) for t in normalise(text).split() if t]


def token_score(token: str, haystack: str) -> float:
    """Match quality in [0, 1] of one query token against one field value.

    1.00  the field equals the token
    0.95  a word in the field equals the token
    0.88  a word in the field starts with the token
    0.70  the token appears anywhere in the field
    fuzzy scaled into [0.30, 0.68] for near-misses above FUZZY_THRESHOLD
    """
    if not token or not haystack:
        return 0.0
    if haystack == token:
        return 1.0

    words = [_singular(w) for w in haystack.split()]
    if token in words:
        return 0.95
    if any(w.startswith(token) for w in words):
        return 0.88
    if token in haystack:
        return 0.70

    best = 0.0
    for word in words or [haystack]:
        ratio = SequenceMatcher(None, token, word).ratio()
        if ratio > best:
            best = ratio
    if best >= FUZZY_THRESHOLD:
        # Map [FUZZY_THRESHOLD, 1.0] onto [0.30, 0.68].
        span = (best - FUZZY_THRESHOLD) / (1.0 - FUZZY_THRESHOLD)
        return 0.30 + 0.38 * span
    return 0.0


# ── Field extraction ────────────────────────────────────────────────


def _menu_entries(restaurant) -> List[Tuple[str, str]]:
    """(display name, normalised searchable text) for each available menu item."""
    entries = []
    for item in getattr(restaurant, "menu", None) or []:
        name = getattr(item, "name", None) if not isinstance(item, dict) else item.get("name")
        if not name:
            continue
        available = (
            item.get("is_available", True)
            if isinstance(item, dict)
            else getattr(item, "is_available", True)
        )
        if not available:
            continue
        category = (
            item.get("category", "") if isinstance(item, dict) else getattr(item, "category", "")
        )
        entries.append((name, normalise(f"{name} {category or ''}")))
    return entries


def score_relevance(restaurant, tokens: Sequence[str]) -> Tuple[float, List[str]]:
    """Relevance in [0, 1] plus the menu item names that matched.

    Returns ``(0.0, [])`` when any token matches nothing, which is how the
    caller filters non-matches out of the result set.
    """
    if not tokens:
        return 1.0, []

    name = normalise(getattr(restaurant, "name", ""))
    description = normalise(getattr(restaurant, "description", ""))
    categories = [normalise(c) for c in (getattr(restaurant, "categories", None) or [])]
    dietary = [normalise(c) for c in (getattr(restaurant, "dietary_tags", None) or [])]
    menu = _menu_entries(restaurant)

    total = 0.0
    matched_items: List[str] = []
    for token in tokens:
        best = token_score(token, name) * FIELD_WEIGHTS["name"]

        for value in categories + dietary:
            best = max(best, token_score(token, value) * FIELD_WEIGHTS["category"])

        best_item: Optional[str] = None
        best_item_score = 0.0
        for display, haystack in menu:
            hit = token_score(token, haystack) * FIELD_WEIGHTS["menu"]
            if hit > best_item_score:
                best_item_score, best_item = hit, display
        best = max(best, best_item_score)
        if best_item:
            matched_items.append(best_item)

        best = max(best, token_score(token, description) * FIELD_WEIGHTS["description"])

        if best <= 0.0:
            return 0.0, []
        total += best

    # De-duplicate while preserving order.
    seen: set = set()
    unique_items = [i for i in matched_items if not (i in seen or seen.add(i))]
    return round(total / len(tokens), 6), unique_items[:5]


# ── Ranking signals ─────────────────────────────────────────────────


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lng / 2) ** 2
    )
    return EARTH_RADIUS_KM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def distance_km(restaurant, lat: Optional[float], lng: Optional[float]) -> Optional[float]:
    if lat is None or lng is None:
        return None
    location = getattr(restaurant, "location", None)
    coords = getattr(location, "coordinates", None) if location is not None else None
    if not coords or len(coords) != 2:
        return None
    return round(haversine_km(lat, lng, coords[1], coords[0]), 3)


def proximity_score(distance: Optional[float], radius_km: float) -> float:
    if distance is None:
        return 1.0
    if radius_km <= 0:
        return 0.0
    return max(0.0, min(1.0, 1.0 - (distance / radius_km)))


def quality_score(restaurant) -> float:
    rating = float(getattr(restaurant, "rating", 0) or 0)
    count = int(getattr(restaurant, "review_count", 0) or 0)
    smoothed = (RATING_PRIOR * RATING_PRIOR_WEIGHT + rating * count) / (
        RATING_PRIOR_WEIGHT + count
    )
    return max(0.0, min(1.0, smoothed / 5.0))


def speed_score(restaurant) -> float:
    minutes = float(getattr(restaurant, "delivery_time_min", SLOWEST_MINUTES) or SLOWEST_MINUTES)
    span = SLOWEST_MINUTES - FASTEST_MINUTES
    return max(0.0, min(1.0, 1.0 - (minutes - FASTEST_MINUTES) / span))


def promotion_score(restaurant) -> float:
    if getattr(restaurant, "promotions", None):
        return 1.0
    fee = getattr(restaurant, "delivery_fee_usd", None)
    if fee is not None and float(fee) <= 0:
        return 1.0
    return 0.0


def availability_bucket(availability: dict) -> str:
    if availability.get("is_open"):
        return "open"
    if availability.get("accepts_scheduled"):
        return "scheduled"
    return "closed"


def rank(
    restaurants: Iterable,
    *,
    query: str = "",
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    radius_km: float = 10.0,
    now=None,
) -> List[dict]:
    """Score and order restaurants. Returns ``[{restaurant, score, ...}, …]``.

    Non-matching restaurants are dropped; closed ones are kept (and demoted),
    because hiding them makes the marketplace look empty at 07:00.
    """
    tokens = tokenize(query)
    ranked: List[dict] = []
    for restaurant in restaurants:
        relevance, matched_items = score_relevance(restaurant, tokens)
        if relevance <= 0.0:
            continue
        availability = availability_of(restaurant, now=now)
        distance = distance_km(restaurant, lat, lng)
        base = (
            WEIGHT_RELEVANCE * relevance
            + WEIGHT_PROXIMITY * proximity_score(distance, radius_km)
            + WEIGHT_QUALITY * quality_score(restaurant)
            + WEIGHT_SPEED * speed_score(restaurant)
            + WEIGHT_PROMOTION * promotion_score(restaurant)
        )
        multiplier = AVAILABILITY_MULTIPLIER[availability_bucket(availability)]
        ranked.append(
            {
                "restaurant": restaurant,
                "score": round(base * multiplier, 6),
                "relevance": relevance,
                "distance_km": distance,
                "matched_menu_items": matched_items,
                "availability": availability,
            }
        )

    ranked.sort(
        key=lambda r: (
            -r["score"],
            r["distance_km"] if r["distance_km"] is not None else 0.0,
            normalise(getattr(r["restaurant"], "name", "")),
        )
    )
    return ranked


def attach_discovery(entry: dict):
    """Stamp ranking metadata onto the restaurant so it is serialised out."""
    restaurant = entry["restaurant"]
    meta = {
        "score": entry["score"],
        "relevance": entry["relevance"],
        "distance_km": entry["distance_km"],
        "matched_menu_items": entry["matched_menu_items"],
    }
    try:
        restaurant._discovery = meta
    except (AttributeError, ValueError):  # pragma: no cover - defensive
        pass
    return restaurant
