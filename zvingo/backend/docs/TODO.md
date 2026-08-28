# Backend TODO — human/external steps & ongoing backlog

This file is the single source of truth for what still needs a **human** or an
**external service**, and for the remaining product backlog. Code-level items
should be removed from here once implemented; agents should keep appending as
the project progresses.

> Last updated: 27 August 2026

---

## 1. External credentials / services (blocked on humans, not code)

These are implemented in code but will not work live until real keys/accounts
are provided. Do **not** mark them "done" without a live test.

- [ ] **Paynow (payments) — go live**
  - Set `PAYMENT_MOCK_MODE=false`.
  - Provide `PAYNOW_INTEGRATION_ID` and `PAYNOW_INTEGRATION_KEY` in `.env`.
  - Set `PAYNOW_RETURN_URL` and `PAYNOW_RESULT_URL` to real HTTPS URLs.
  - Run an end-to-end EcoCash / OneMoney / InnBucks payment and confirm the
    webhook reaches `/api/payment/webhook`.

- [ ] **Paynow (refunds) — go live**
  - The `paynow` SDK has no public refund helper. Wire the provider's refund
    endpoint in `app/payment/paynow_client.py::refund` (currently returns an
    explicit failure in live mode so the DB never falsely marks REFUNDED).
  - Test a real refund round-trip.

- [ ] **Africa's Talking (SMS) — go live**
  - Set `SMS_MOCK_MODE=false`.
  - Provide `AFRICASTALKING_USERNAME` and `AFRICASTALKING_API_KEY`.
  - Confirm OTP, password-reset, and offer SMS deliver to real numbers.

- [ ] **Firebase Cloud Messaging — enable push**
  - Create a Firebase project, download the service-account JSON, and set
    `FIREBASE_CREDENTIALS_PATH` (or bake it into the image per `DEPLOYMENT.md`).
  - Verify consumer and driver push notifications arrive.

- [ ] **Card payments**
  - `PaymentMethod.CARD` exists in the enum but has no provider integration.
    Choose a card processor (Paynow card endpoint, Stripe, etc.) and implement
    the `initiate`/`check_status`/`refund` paths for cards.

- [ ] **Domain / TLS / deployment**
  - Replace `zvingo.example.com` in `nginx/nginx.prod.conf` and `.env` with the
    real domain; obtain Let's Encrypt certs per `DEPLOYMENT.md`.
  - Provision the production server and run the prod compose stack.

- [ ] **First admin account**
  - The admin API (`/admin/*`) requires `role == "admin"`, but nothing can mint
    the first admin — `POST /auth/register` will not grant that role. Promote a
    user directly in Mongo once, then manage the rest through
    `PATCH /admin/users/{id}`:
    `db.users.updateOne({phone: "+263..."}, {$set: {role: "admin"}})`.

- [ ] **Alert delivery sink**
  - `AlertService` raises alerts as structured logs, publishes them to the Redis
    `alerts` channel, and serves them at `GET /admin/alerts`. Nothing yet
    *delivers* them. Pick a destination (email, SMS to an ops number, Slack,
    PagerDuty) and add a subscriber; needs an account/credentials.

- [ ] **Metrics scraping**
  - `GET /metrics` exposes Prometheus text exposition. nginx already denies
    `/api/metrics` from the public internet, so stand up Prometheus (or a hosted
    agent) inside the compose network and point it at
    `http://backend:8000/metrics`. Set `METRICS_TOKEN` if you also want bearer
    auth on the endpoint itself.

---

## 2. Product backlog (code can be done, not yet started)

- [ ] **Multi-restaurant cart — cancellation & fee policy**
  - `POST /orders/checkout` creates one order per restaurant sharing a
    `group_id`. Two product decisions remain: (a) cancelling one order in a
    group currently leaves its siblings live — decide whether cancelling should
    cascade; (b) each basket is charged its own delivery fee since each has its
    own driver — decide whether to bundle or discount grouped deliveries.

- [ ] **Multi-restaurant checkout is not atomic**
  - `create_checkout` writes each basket in turn. If a later basket is rejected
    (unresolvable pickup location, for instance) the earlier ones are already
    persisted. `idempotency_key` makes a client retry safe, but a checkout that
    is never retried leaves a partial group. Either pre-resolve every basket's
    pickup before writing anything, or roll the group back on failure.

- [ ] **Chat — read receipts / unread counts**
  - Messages persist and stream (`GET /chat/orders/{id}/stream`), but there is
    no read state, so clients cannot show an unread badge. Add `read_at` per
    participant and an endpoint to mark a conversation read.

- [ ] **Driver rating backfill**
  - `User.driver_rating` / `driver_review_count` are maintained from now on, but
    reviews written before the aggregate existed are not reflected. Add a
    one-off script that recomputes both from the `reviews` collection.

- [ ] **Free-item promos — bind to menu item ids**
  - `free_item` promos match `free_item_id` first and fall back to a
    case-insensitive `free_item_name`. The name fallback silently stops matching
    when a merchant renames a dish. Have the merchant dashboard always send
    `free_item_id`, then make the name a display label only.

- [ ] **Promotions — per-restaurant scoping at redemption**
  - `Promotion.restaurant_id` scopes which promos are *listed*, but
    `compute_discount` does not check it, so a code shown for one restaurant can
    be redeemed against another. Enforce the scope at redemption.

- [ ] **Realtime — retire the per-purpose SSE streams**
  - `GET /ws/orders/{id}/track` now carries order events, driver location, and
    chat on one socket. `GET /location/driver/{id}/track` and
    `GET /notification/events/{channel}` are still there for the existing
    clients. Once the consumer app moves over, remove them.

- [ ] **Platform docs are stale**
  - `zvingo/SYSTEM_DOCUMENTATION.md` (module architecture, startup lifecycle,
    collections, real-time channels) and `zvingo/DEPLOYMENT.md` (env vars,
    routing reference) predate the admin API, observability stack, tracking
    WebSocket, checkout groups, and the new `User` / `Order` / `Promotion`
    fields. Update them — they are repo-level docs, outside the backend tree.

---

## 3. Ops / observability

- [x] Structured request/error tracing — `RequestContextMiddleware` binds a
      correlation id (honouring an inbound `X-Request-ID`) to the structlog
      context, logs method/route/status/latency, and echoes `X-Request-ID` and
      `X-Response-Time-Ms` on every response.
- [x] Metrics — `GET /metrics` in Prometheus text format, covering HTTP traffic,
      order creation and transitions, dispatch offers / no-driver / retry
      exhaustion, payment outcomes, and alerts.
- [x] Alerting — `AlertService` polls for stuck orders, failed-payment spikes,
      and dispatch retry exhaustion; alerts are deduped per window, logged,
      published to Redis, and served at `GET /admin/alerts`.

Open follow-ups:

- [ ] **Metrics are per-process**
  - The registry lives in memory, so a scrape only sees the process that
    answered it. The stack now runs one uvicorn worker per container, so this
    is correct as deployed; if you scale to several backend containers,
    scrape each one rather than load-balancing the scrape.

- [ ] **Log shipping / retention**
  - Production emits one JSON object per line to stdout. Nothing collects it —
    pick a destination (Loki, CloudWatch, an ELK stack) and set retention.

- [ ] **Alert thresholds are guesses**
  - `ALERT_STUCK_ORDER_MINUTES=30` and `ALERT_FAILED_PAYMENT_THRESHOLD=5` were
    chosen without traffic data. Re-tune once there is real order volume.

---

## 4. Completed (for reference)

- [x] Shared `Location` model (`app/location/models.py`).
- [x] `OrderCreate` nested `pickup`/`dropoff` + legacy flat fields.
- [x] Auth fixes: `create_order`, `record_earning`, `update_exchange_rate`,
      `refund_payment`, `update_order_state` now enforce auth/ownership.
- [x] Ratings & reviews (review model + submission + list endpoints).
- [x] In-app chat persistence + Redis publish (message send/list).
- [x] Order reorder endpoint.
- [x] Self-pickup (skip delivery fee + no dispatch).
- [x] Scheduled orders (deferred dispatch via retry loop).
- [x] Promo code validation + redemption + free-delivery.
- [x] Real refund provider call (mock + explicit live failure).
- [x] **Scheduled order dispatch** — `ScheduledOrderService` polls every
      `SCHEDULED_POLL_INTERVAL_SECONDS` (15s) and releases an order
      `SCHEDULED_DISPATCH_LEAD_MINUTES` before its slot, so the driver arrives
      for the slot instead of setting off at it. Released orders are marked
      `scheduled_dispatched` and handed to the ordinary retry loop.
- [x] **Dispatch retry scoping** — the retry loop no longer re-dispatches
      self-pickup orders, and no longer grabs scheduled orders before the
      scheduler has released them.
- [x] **Driver rating aggregate** — `User.driver_rating` /
      `driver_review_count`, folded in on review submission, exposed on
      `/auth/me` and `GET /rating/drivers/{id}/summary` (with a star breakdown).
- [x] **Chat real-time stream** — `GET /chat/orders/{order_id}/stream` (SSE),
      participant-gated, accepting the JWT as a header or `?token=`.
- [x] **`free_item` promotions** — redeemable, matched by menu item id or name,
      discounting the cheapest matching cart line; unsupported `promo_type`
      values are now rejected at creation instead of at redemption.
- [x] **Per-user promo limits** — `max_uses_per_user` is actually enforced via
      `Promotion.redemptions_by_user` (legacy `redeemed_by` still counts as one
      use), and a discount can never exceed the order subtotal.
- [x] **Admin API** — `/admin/stats`, `/admin/users` (+ detail, role/status
      patch with self-lockout guards), `/admin/orders` (+ detail with the event
      trail, force-cancel, re-dispatch), `/admin/payments`,
      `/admin/restaurants` (+ suspend/reinstate), `/admin/alerts`.
- [x] **Deactivated accounts are enforced** — `User.is_active` was previously
      never checked; login and every authenticated request now reject an
      inactive user (403), so an admin deactivation takes effect immediately
      even for tokens minted earlier.
- [x] **Multi-restaurant checkout** — `POST /orders/checkout` creates one order
      per restaurant sharing a `group_id`, splits a promo across the baskets in
      proportion to their value, redeems it once, applies free delivery to a
      single basket, and keeps the tip on one order.
      `GET /orders/group/{group_id}` returns the whole group.
- [x] **Realtime tracking over WebSocket** — `GET /ws/orders/{order_id}/track`
      carries the order snapshot, lifecycle events, driver location, and chat on
      one socket, and starts following the driver's location channel as soon as
      dispatch assigns one.
- [x] **Shared order access check** — `app/order/access.py::can_access_order` is
      the single rule used by order detail, chat, and tracking.
- [x] **Test bootstrap** — `tests/conftest.py` supplies default `MONGODB_URL` /
      `REDIS_URL` so `pytest` runs with no environment setup. The suite is at
      100% line coverage (`fail_under = 100` in `pyproject.toml`).
- [x] **Production stack could not boot** — `PAYMENT_MOCK_MODE` and
      `SMS_MOCK_MODE` default to true in `app/config.py`, and the production
      validator refuses to start while either is on, but
      `docker-compose.prod.yml` never set them. Both are now pinned false there.
- [x] **Single-worker production command** — the prod compose file no longer
      overrides the Dockerfile with `--workers 4`, which would have raced four
      processes onto the BinProto ports and quadrupled every background loop.
- [x] **nginx knows about the new endpoints** — the chat SSE stream gets a
      buffering-off location (it would otherwise have appeared frozen behind
      the generic `/api/` block) and `/api/metrics` is denied publicly. The
      tracking WebSocket is already covered by the existing `/ws/` block.
- [x] **Dashboard build args** — `docker-compose.prod.yml` now passes
      `NEXT_PUBLIC_API_URL` / `API_PROXY_URL` at build time. Without them the
      dashboard shipped with an empty API base and pointed uploads at
      `http://localhost:8000`, i.e. the visitor's own machine.
- [x] **`backend/.dockerignore`** — the Dockerfile does `COPY . .`, so a local
      `.env` (with a live `SECRET_KEY`) was being baked into an image layer.
      Secrets, `.git`, and caches are now excluded.
