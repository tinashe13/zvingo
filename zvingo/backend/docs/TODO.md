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

---

## 2. Product backlog (code can be done, not yet started)

- [ ] **Scheduled order dispatch refinement**
  - Orders with `scheduled_at` are currently dispatched by the retry loop once
    due. Consider a dedicated scheduler or tighter latency guarantees.
- [ ] **Ratings — driver aggregate**
  - Restaurant rating aggregation is implemented. Add a `driver_rating` /
    `review_count` aggregate on the `User` document so driver ratings surface
    on the driver profile/ratings screen.
- [ ] **In-app chat — real-time stream**
  - Chat currently persists messages and publishes to Redis, but there is no
    SSE/WebSocket chat subscription endpoint yet. Add
    `GET /chat/orders/{order_id}/stream` mirroring the notification SSE.
- [ ] **Promotions — `free_item` type**
  - `promo_type="free_item"` is declared in docs but `promotion_service.py`
    rejects unknown types. Implement free-item redemption if needed.
- [ ] **Admin panel**
  - `get_current_admin` (role `admin`) and the admin-only refund/rates paths are
    in place. There is no admin dashboard or user/order management API yet.
- [ ] **Multi-restaurant cart**
  - The consumer cart groups items by restaurant, but the checkout/order flow
    needs end-to-end verification across multiple restaurants.
- [ ] **Realtime driver location over WebSocket**
  - Consumer tracking currently uses SSE/polling. Consolidate onto the existing
    WebSocket channel if desired.

---

## 3. Ops / observability (nice-to-have, not blocking)

- [ ] Structured request/error tracing (request IDs, latency logging).
- [ ] Metrics (Prometheus endpoint or similar) for orders, dispatch, payments.
- [ ] Alerting on stuck orders, failed payments, and dispatch retry exhaustion.

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
