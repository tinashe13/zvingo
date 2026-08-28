# Backend Refactor & Persona Test Findings

> Scope: consolidate the duplicated `Location` model, switch `OrderCreate` to a
> nested location contract (backward compatible), and verify the backend happy
> path with persona-driven tests.
>
> Date: 27 August 2026

## 1. Refactor — shared `Location` model

### Problem

`pickup_lat` / `pickup_lng` / `dropoff_lat` / `dropoff_lng` were four flat floats
on `OrderCreate`, while the persisted `Order` document already stored GeoJSON
dicts (`pickup_location` / `dropoff_location`). `Location` was duplicated in
`app/auth/models.py` and `app/catalog/models.py`, and every read site manually
swapped `coordinates[0]` (lng) / `coordinates[1]` (lat) — a recurring
off-by-order footgun.

### Change

- New shared model: `app/location/models.py` — `Location` with `lat` / `lng`
  properties, `Location.from_lat_lng(lat, lng)`, and `is_null_island`.
- `app/auth/models.py` and `app/catalog/models.py` now import that single model
  (duplicate definitions removed).
- `Order.pickup_location` / `Order.dropoff_location` are now
  `Optional[Location]` instead of raw `dict`.
- `OrderCreate` accepts **both** nested `pickup` / `dropoff` (`Location`) and the
  legacy flat fields, normalized by a Pydantic `model_validator`. This is
  backward compatible — the Flutter consumer app still sends flat fields and
  works unchanged.
- All location read/write sites (`order/service.py`, `order/router.py`,
  `finance/router.py`, `notification/service.py`, `dispatch/retry_service.py`)
  now use `.lat` / `.lng` instead of `coordinates[0]` / `coordinates[1]`.

## 2. Hiccup found & fixed — unauthenticated order state transition

### Finding (merchant persona agent)

`PUT /orders/{order_id}/state` (`app/order/router.py:update_order_state`)
performed **no authorization or ownership check**:

- It depended on `oauth2_scheme` (a raw token string) but never validated it.
- It trusted `driver_id` from the request body, so any caller with a valid token
  could assign themselves as the driver of any order — or transition any order
  through any state.

### Fix

- Replaced the raw token dependency with `get_current_user` (full JWT validation).
- Added `_assert_order_access` — the caller must be the order's consumer, the
  assigned driver, or the owning merchant (else `403`).
- `OrderUpdateState` no longer accepts a `driver_id` field.
- `OrderService.transition_state` now separates the **actor** (audit trail) from
  the **driver assignment**. Driver assignment only happens when `driver_id` is
  explicitly passed, which is done only by the driver-accept flows
  (`DispatchService.accept_offer`, the SMS `ACCEPT` command). A merchant or
  consumer transitioning an order can no longer become its driver.

### Behavioral note

The merchant dashboard's "Accept" button transitions `CREATED → ACCEPTED`. After
this fix it does so without assigning a driver (driver assignment still happens
separately via dispatch). This was already the de-facto behavior because the
dashboard never sent `driver_id`, but the endpoint previously *allowed* a caller
to inject one — that hole is now closed.

## 3. Persona test coverage added

- `tests/test_location_model.py` — `Location` model + `OrderCreate` normalization.
- `tests/test_consumer_happy_path.py` — consumer create (nested + legacy +
  pickup resolution), list/cancel own order, confirm delivery.
- `tests/test_driver_happy_path.py` — dashing, schedule, vehicle, accept/decline
  offer, location update.
- `tests/test_merchant_happy_path.py` — restaurant create/update (new fields),
  add menu item, list own orders, advance order state.

## 4. Verification

- Local: `pytest` — **110 passed**, `--cov` gate **100.00%** reached.
- Docker (`python:3.12-slim` + `poetry install --with dev`): **110 passed**,
  **100.00%** coverage.

## 5. Other observations (not changed)

- `app/dispatch/service.py:update_location` imports `notification_service` and
  `json` inside the method but does not use `notification_service` (dead import).
- `app/dispatch/service.py:geoadd` is called as `geoadd("driver_locations",
  [lng, lat, driver_id])` — a single-list calling convention rather than
  positional args; harmless but worth normalizing later.
