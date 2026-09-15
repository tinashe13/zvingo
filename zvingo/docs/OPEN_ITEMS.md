# Zvingo — Open Items After the Hardening Pass

State at the end of the pass. Everything below is **known and deliberate**: it is
either blocked on a decision, blocked on an external account, or genuinely unbuilt.
Nothing here is a surprise waiting in the code.

Verified green at time of writing:

| Surface | Result |
|---|---|
| Backend | **811 tests passing** (baseline was 214) |
| Consumer app | 0 errors, 0 warnings, 0 hand-written analyzer issues, 44 tests passing |
| Driver app | `flutter analyze`: **no issues at all**, 89 tests passing |
| Merchant dashboard | `tsc` clean, lint clean (0/0), build green across 13 routes |

No dead buttons, "coming soon" strings, or widget-tree TODOs remain in any shipping
file on any surface.

---

## 1. Decisions only you can make

| # | Decision | Why it matters |
|---|---|---|
| D1 | **Rotate the OpenRouteService key.** `5b3ce35978…` was hardcoded in the driver app and is in pushed git history. | It is public. Free tier is 2,000 req/day; a real fleet exhausts it regardless. |
| D2 | **Settle the production domain.** The repo contradicts itself: `pindira.com`, `zvingo.com`, and a third default in the consumer app. | The API host is **compiled into the app binaries**. This must be settled before any store build. |
| D3 | **`PROMO_DISCOUNT_FUNDED_BY`** ships as `platform` (Zvingo absorbs promo discounts, merchant paid in full). The alternative is `merchant`. | Decides who loses money on every discounted order. |
| D4 | **Driver payouts are pinned to USD**; the platform carries the FX difference. | Right for driver trust in a volatile-currency market, but it moves exchange-rate risk onto you. |
| D5 | **Who bears Zimbabwe's 2% IMTT** — merchant or payer. | Materially changes your take rate. Get it from Paynow in writing. |
| D6 | **Map tiles**: all four surfaces use keyless CARTO/OSM tiles. | CARTO's terms (Aug 2026) frame the free tier around holding an API key. Pick one keyed provider for all four surfaces at once. |
| D7 | **Cash on delivery**: is it supported? | There is no collection ledger and no driver-float model. Today no `CASH` method exists at all. |

---

## 2. Launch blockers

### Needs an external account (start these first — they are pure waiting)
- **Africa's Talking** live account + sender ID (1–3 weeks, Zimbabwean company KYC).
  Without it OTP sign-in *and* password reset silently do nothing on both apps.
- **Paynow** merchant account (needs a Zimbabwean bank account). No payment, no dispatch.
- **Apple Developer** (1–3 weeks) and **Google Play as an organization** — a personal
  Play account triggers the 12-testers-for-14-days rule, per app.

### Needs code
| # | Item | Notes |
|---|---|---|
| B1 | **`DELETE /auth/me`** — account deletion. | Google Play **requires** in-app deletion. Both apps ship the full client flow and handle a missing endpoint honestly; the endpoint itself does not exist. Anonymise rather than hard-delete: order/payment/ledger rows carry `consumer_id` and must be retained for tax and AML. |
| B2 | **Privacy policy and terms of service.** | Both stores require them; neither document exists anywhere. The screens are built and render a hosted URL — someone has to write and host the documents. No legal text was generated. |
| B3 | **iOS `Info.plist` location keys.** | `NSLocationWhenInUseUsageDescription` is absent while `geolocator` is a dependency — iOS **terminates the process** on first location request. Exact entries are in the D1 agent report. |
| B4 | **Push notifications are dead end-to-end.** | Neither app depends on `firebase_messaging`, and nothing calls the fcm-token endpoint, so the stored token is always null. Configuring Firebase alone changes nothing — the client half is unbuilt. Matters most on iOS, where a foreground service cannot compensate. |

---

## 3. Backend endpoints the clients need

Each was requested by a client that is already built against it and degrades honestly today.

| Priority | Gap | Blocks |
|---|---|---|
| High | `MenuItem.modifier_groups` + order lines carrying selected option ids | Item customisation. The dashboard editor is built and self-enables the moment the field lands. |
| High | Fee breakdown on `GET /orders/{id}` | `delivery_fee`, `service_fee`, `tax_amount`, `tip_amount`, `discount_amount`, `promo_code`, `is_pickup`, `currency` are all stored but never serialised, so no client can render an accurate receipt or "amount due". |
| High | `POST /orders/quote` | `service_fee` and `tax_amount` are currently whatever the client sends; nothing validates them server-side. |
| Medium | `driver_phone` (ideally proxied), `driver_vehicle`, `driver_photo_url`, `driver_rating` on the order payload | Courier detail on tracking. `User` has no avatar field at all. |
| Medium | Server-side `eta_minutes` | The client estimator is honest but knows nothing about kitchen load or traffic. |
| Medium | `categories` / `dietary_tags` on `RestaurantUpdate` | A merchant can never fix a cuisine tag. |
| Medium | `X-Total-Count` (or `{items,total}`) and `?state=` on `GET /orders/merchant/{id}` | Real pagination on the orders board. |
| Medium | Optional `reason` on a merchant `CANCELLED` transition | The dashboard says plainly that a reason cannot be passed on yet. |
| Medium | `emergency_contact` on `User` + `GET`/`PUT /driver/emergency-contact` | Driver safety screen persistence. |
| Low | `restaurant_name` on the order payload | Saves one request per order card. |
| Low | `supports_pickup` / `pickup_prep_minutes` on `Restaurant` | Pickup is honest but unfiltered. |
| Low | `GET /catalog/search/trending`; `has_promotions` on `/catalog/search` | Discovery polish. Note `lon` vs `lng` is inconsistent between sibling endpoints. |

---

## 4. Known-and-accepted

- **BinProto UDP 9090 / TCP 9091** are published plaintext in compose and trust an
  8-byte session id with no HMAC and no replay check. Nothing ever issues a session,
  so the protocol is non-functional while both servers still listen. Close the ports
  or finish the protocol.
- **Driver Gradle config silently falls back to debug signing.**
- **Paynow's own transaction fee is not modelled**, so platform revenue is overstated
  on every order.
- **A ZIG exchange rate must be published** or non-USD checkout returns 503 by design.
- **The Paynow webhook hash has never met a live delivery.** The implementation matches
  their SDK's algorithm and is covered by tests, but send a real one and watch it verify.
- **`riverpod_generator` is pinned** by a `hive_generator` conflict, so regenerated
  `.g.dart` files carry 14 deprecation infos. Cosmetic; unpinning needs a dependency upgrade.
- `app/tracking/ws_router.py` exposes a consolidated socket that multiplexes all three
  consumer streams. It is strictly better than three connections but unused, because
  `consumer_app` has no `web_socket_channel` dependency.
- **No widget/golden test for the consumer tracking screen** — its map fetches real
  tiles under `flutter_test` and needs a stubbed tile provider.
- **Single-flight token refresh under concurrent 401s** is the highest-risk code in the
  consumer app and has no test.

---

## 5. Where the documentation lives

| Document | Contents |
|---|---|
| `docs/DESIGN_SYSTEM.md` | Normative cross-surface spec. Colour, type, spacing, motion, component contracts, navigation rules, and the review checklist a screen must pass. |
| `docs/INTEGRATIONS_AND_CREDENTIALS.md` | Every external account and credential, with signup URLs, documents demanded, lead times, costs, env vars, and how to test each one. |
| `SYSTEM_DOCUMENTATION.md` | Architecture overview. **Its §18 tech-debt table is now substantially stale** — much of it was fixed during this pass, and several items in it were never true. Treat the code as the authority. |
