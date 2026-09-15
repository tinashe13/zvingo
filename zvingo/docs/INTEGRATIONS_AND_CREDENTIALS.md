# Zvingo — Integrations, Credentials & Go-Live Requirements

**Every external account, API key, certificate and paid service Zvingo needs to go live, and
exactly how to get each one.**

Audience: the product owner. It assumes you have never set any of these up before.
Everything in the "status today" column was derived by reading the code, not the docs —
where `SYSTEM_DOCUMENTATION.md` §18 disagrees, this file is right and §18 is stale.

Last verified against the codebase: **2026-09-15**.
Anything I could not confirm from a primary source is marked **UNVERIFIED** with a note on
how to check it yourself.

---

## Table of contents

1. [Go-live readiness scorecard](#1-go-live-readiness-scorecard)
2. [Provider-by-provider setup](#2-provider-by-provider-setup)
   - [2.1 Paynow Zimbabwe — payments](#21-paynow-zimbabwe--payments)
   - [2.2 Africa's Talking — SMS / OTP](#22-africas-talking--sms--otp)
   - [2.3 Firebase Cloud Messaging — push notifications](#23-firebase-cloud-messaging--push-notifications)
   - [2.4 CARTO Basemaps — map tiles](#24-carto-basemaps--map-tiles)
   - [2.5 OpenStreetMap Nominatim — address search](#25-openstreetmap-nominatim--address-search)
   - [2.6 Platform geocoder (Android/iOS) — reverse geocoding](#26-platform-geocoder-androidios--reverse-geocoding)
   - [2.7 Domain name and DNS](#27-domain-name-and-dns)
   - [2.8 TLS certificates — Let's Encrypt](#28-tls-certificates--lets-encrypt)
   - [2.9 Hosting — DigitalOcean](#29-hosting--digitalocean)
   - [2.10 MongoDB and Redis](#210-mongodb-and-redis)
   - [2.11 Google Maps — NOT used](#211-google-maps--not-used-do-not-buy-a-key)
3. [Complete environment-variable reference](#3-complete-environment-variable-reference)
4. [Mobile app store release requirements](#4-mobile-app-store-release-requirements)
5. [Secrets management](#5-secrets-management)
6. [Prioritised "do this first" checklist](#6-prioritised-do-this-first-checklist)
7. [Cost summary](#7-cost-summary)
8. [Code-level problems found while writing this](#8-code-level-problems-found-while-writing-this)
9. [Sources](#sources)

---

## 1. Go-live readiness scorecard

Status values mean:

- **LIVE** — talks to the real third party today.
- **SANDBOX** — talks to the provider's test environment; no real money, no real SMS.
- **MOCK** — never leaves our server; fabricated success responses.
- **NOT CONFIGURED** — the integration exists in code but is inert with no credential.
- **NOT BUILT** — there is no client-side code at all.

| # | Integration | Status today | Evidence in code | What breaks in production | Launch blocker? |
|---|---|---|---|---|---|
| 1 | **Paynow — payments** (EcoCash / OneMoney / InnBucks) | **MOCK** | `PAYMENT_MOCK_MODE: bool = True` in `backend/app/config.py`; `PaynowClient.send_mobile` returns `mock://poll/...` and `_mock_auto_complete` marks the order PAID after 3 s | Every order is "paid" with zero money collected. The app cannot start at all with `ENVIRONMENT=production` and mock mode on — the settings validator raises. | 🔴 **YES** |
| 2 | **Paynow — webhook authenticity** | **UNVERIFIED SIGNATURE** | `backend/app/payment/router.py` `POST /webhook` reads `reference`/`status`/`pollurl` from the form and never validates Paynow's `hash` field | Anyone on the internet can `POST` `reference=<guess>&status=paid` and mark an order paid without paying. | 🔴 **YES** (security) |
| 3 | **Paynow — refunds** | **NOT IMPLEMENTED** | `PaynowClient.refund` returns `success=False, error="Live refund requires Paynow refund endpoint integration"` outside mock mode | `POST /api/payment/refund/{id}` always fails in production. Refunds must be issued by hand in the Paynow merchant portal. | 🟠 Not a blocker, but you need a manual refund runbook on day 1 |
| 4 | **Africa's Talking — SMS** (signup OTP, password reset) | **MOCK**, defaulting to the **sandbox** username | `SMS_MOCK_MODE: bool = True`, `AFRICASTALKING_USERNAME = "sandbox"` in `config.py`; `SMSGateway` picks `api.sandbox.africastalking.com` whenever the username is literally `sandbox` | Nobody can sign up or reset a password — the OTP is only written to the log. As with Paynow, production start-up is blocked by the validator. | 🔴 **YES** |
| 5 | **Africa's Talking — second, orphaned code path** | **DIFFERENT ENV VARS** | `backend/app/sms/router.py` reads `AT_USERNAME` / `AT_API_KEY` via `os.getenv` — names that exist nowhere in `config.py`, any `.env.example`, or any compose file | `POST /api/sms/send` silently mocks forever even with correct `AFRICASTALKING_*` values set. | 🟡 Code bug — see §"Code-level problems" |
| 6 | **Firebase Cloud Messaging — server side** | **NOT CONFIGURED** | `FIREBASE_CREDENTIALS_PATH: Optional[str] = None`; `init_firebase()` logs "Firebase not configured" and returns | Push sends are logged and dropped. Drivers get no offer notification when the app is backgrounded. | 🟠 High — dispatch still works over WebSocket while the app is foregrounded |
| 7 | **Firebase Cloud Messaging — client side** | **NOT BUILT** | Neither `consumer_app/pubspec.yaml` nor `driver_app/pubspec.yaml` lists `firebase_core` / `firebase_messaging`; there is no `google-services.json` or `GoogleService-Info.plist`; nothing calls `POST /api/auth/fcm-token` | `User.fcm_token` is never populated, so **push is dead end-to-end even after you buy/configure Firebase**. Configuring the server alone achieves nothing. | 🟠 High — see §2.3 |
| 8 | **CARTO Basemaps — map tiles** | **LIVE, keyless** | `https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png` at 5 call sites across both apps | Works today. CARTO's Basemap Terms (updated 26 Aug 2026) describe free basemaps as being for customers using **a CARTO-issued API key**, and reserve the right to rate-limit or cut off access without notice. Every map in both apps goes blank if they do. | 🟠 High — commercial/continuity risk, not a hard blocker |
| 9 | **CARTO / OSM attribution** | **PARTIAL — non-compliant** | Only `consumer_app/lib/features/restaurant/restaurant_map_screen.dart` has a `RichAttributionWidget`. The other four maps (`order_tracking_screen.dart`, `order_live_map.dart`, driver `offer_screen.dart`, driver `home_screen.dart`, driver `navigation_map.dart`) render tiles with no attribution at all | Breach of both the CARTO Basemap Terms and the ODbL attribution requirement for OpenStreetMap data. | 🟠 High — a licence breach shipping to two app stores |
| 10 | **Nominatim — address search** | **LIVE, keyless, uncached, unthrottled, unauthenticated** | `backend/app/location/service.py` → `https://nominatim.openstreetmap.org/search`, `User-Agent: "Zvingo/1.0"`; exposed at `GET /api/location/geocode` with **no auth and no rate limit** (`backend/app/location/router.py`) | The OSMF usage policy caps you at **1 request/second absolute**, forbids "heavy uses", requires results to be cached on your side, and requires a User-Agent that actually identifies you. We breach caching and throttling, and one bored user hammering our open endpoint gets our server IP banned — killing address search for every customer at once. | 🔴 **YES** (compliance + single point of failure) |
| 11 | **Platform geocoder** (`geocoding` Flutter package) | **LIVE, free, no key** | `geocoding: ^3.0.0` in `consumer_app/pubspec.yaml`, used by `address_provider.dart` for reverse geocoding | Fine. Uses Android's system geocoder / iOS CoreLocation. No account needed. | ✅ No |
| 12 | **Domain name** | **NOT OWNED / INCONSISTENT** | nginx and the compose examples say `pindira.com` / `api.pindira.com` / `app.pindira.com`; both `BUILD.md` files say `api.zvingo.com`; `consumer_app/lib/core/app_config.dart` defaults to `http://api.pindira.com/api` | You cannot get a TLS certificate, and release builds point at whichever of the two names you didn't buy. | 🔴 **YES** |
| 13 | **TLS certificates** | **NOT ISSUED**, renewal is manual | `docker-compose.prod.yml` bind-mounts `./nginx/certs`; `DEPLOYMENT.md` §4 runs `certbot certonly --standalone` then copies files by hand | nginx will not start without `fullchain.pem` + `privkey.pem`. Android release builds refuse cleartext HTTP (`network_security_config.xml`), and `AppConfig.validate()` in the consumer app throws on a non-HTTPS URL in release. No TLS ⇒ no working mobile app. | 🔴 **YES** |
| 14 | **Hosting — DigitalOcean droplet** | **NOT PROVISIONED** | `DEPLOYMENT.md` §1 targets Ubuntu 24.04, 2 GB minimum / 4 GB recommended | Nothing to deploy to. | 🔴 **YES** |
| 15 | **MongoDB / Redis** | **Self-hosted in compose, credentials unset** | `docker-compose.prod.yml` uses `${MONGO_INITDB_ROOT_PASSWORD:?}` / `${REDIS_PASSWORD:?}` — compose refuses to start if empty | Compose fails fast. Good. But there is **no managed backup** — see §2.10. | 🔴 **YES** (generate the passwords) |
| 16 | **`SECRET_KEY`** | **Default placeholder `"changethis"`** | `config.py` `KNOWN_INSECURE_SECRETS` blocks it in production | Anyone could forge a JWT for any user. Blocked at start-up, so it is a config chore, not a live risk. | 🔴 **YES** |
| 17 | **Google Play Console** | **NO ACCOUNT** | — | Cannot ship either Android app. | 🔴 **YES** |
| 18 | **Apple Developer Program** | **NO ACCOUNT** | `consumer_app/ios/.../project.pbxproj` has `CODE_SIGN_STYLE = Automatic` and no `DEVELOPMENT_TEAM` | Cannot ship either iOS app. Note the iOS driver app is **not shippable as-is** — see #19. | 🔴 **YES** |
| 19 | **iOS driver app — location permission string** | **MISSING** | `driver_app/ios/Runner/Info.plist` has **no** `NSLocationWhenInUseUsageDescription`, yet the app depends on `geolocator` | iOS **terminates the app** the moment it requests location without the usage string. The iOS driver app crashes on first use and would be rejected. | 🔴 **YES** (code fix, outside this document's file boundary) |
| 20 | **Android release keystores** | **NOT CREATED** | `consumer_app/android/app/build.gradle` fails the build without `android/key.properties`; the driver app silently falls back to **debug signing** | Consumer: build fails (good). Driver: you can accidentally produce a debug-signed AAB that Play will reject. | 🔴 **YES** |
| 21 | **Background location** | **NOT REQUESTED anywhere** | Neither `AndroidManifest.xml` declares `ACCESS_BACKGROUND_LOCATION` or a foreground service; neither `Info.plist` declares `UIBackgroundModes: location` | Driver tracking stops the moment the driver's phone screen locks or they switch apps — which is most of a delivery. See §4.4: adding it later is the single hardest store review to pass, so decide **now**. | 🟠 High — product decision with a long review tail |
| 22 | **Prometheus `/metrics`** | **Public route denied at nginx, no token** | `METRICS_TOKEN: Optional[str] = None`; `nginx.prod.conf` has `location = /api/metrics { deny all; }` | Acceptable. Set a token if you ever scrape from outside the compose network. | ✅ No |
| 23 | **BinProto UDP/TCP (9090/9091)** | **LIVE, plaintext, published to the internet** | `docker-compose.prod.yml` publishes `9090/udp` and `9091` directly, bypassing nginx and TLS | Driver GPS telemetry crosses the public internet unencrypted, and the DigitalOcean firewall in `DEPLOYMENT.md` must be opened for it. | 🟠 High — privacy exposure; flagged for the backend team |
| 24 | **Privacy policy** | **STUB in the driver app, NONE in the consumer app, NO public URL** | `driver_app/lib/core/router.dart` renders a two-paragraph `InfoScreen` at `/account/privacy`; `consumer_app` has no privacy text at all; nothing is hosted on the web | Both stores require a **publicly reachable privacy policy URL** on the listing — an in-app screen does not satisfy it. Two paragraphs also cannot cover what these apps actually do (precise location shared with another user, phone numbers, photos, payment metadata). | 🔴 **YES** |
| 25 | **Account deletion** | **NOT BUILT** | No `DELETE` route for a user account in the backend (the only `@router.delete` handlers are menu items and promotions in `catalog/router.py`); no screen in either app | Google Play requires an in-app deletion path *and* a public web URL for any app with account creation. Listing rejected without it. | 🔴 **YES** |

---

## 2. Provider-by-provider setup

### 2.1 Paynow Zimbabwe — payments

#### What it does for Zvingo

Paynow is the payment gateway. It is the **only** way money enters the platform. It fronts
EcoCash, OneMoney and InnBucks mobile money via "Express Checkout" — the customer gets a
push prompt on their handset and enters their mobile-money PIN.

Features that die without it:

- Checkout in the consumer app (`POST /api/payment/initiate`).
- The whole order pipeline downstream of payment: `PaymentService._on_payment_success`
  transitions the order to `OFFERED`, which is what triggers driver dispatch. **No payment,
  no dispatch, no order.**
- Driver earnings and merchant payouts, which are all derived from `Payment` records.

Code: `backend/app/payment/paynow_client.py`, `backend/app/payment/service.py`.
The backend uses the official Python SDK, `paynow ^1.0.8` (already in
`backend/pyproject.toml` and `poetry.lock` — nothing to install).

`METHOD_PROVIDER_MAP` in `service.py` maps our enum to Paynow's method strings:
`ECOCASH → "ecocash"`, `ONEMONEY → "onemoney"`, `INNBUCKS → "innbucks"`.

#### Step-by-step signup

1. **Register a merchant account** at <https://www.paynow.co.zw/Customer/Register>.
   Minimum requirement: a working email address and **one or more Zimbabwean bank accounts**
   to settle into. You do **not** need a special merchant account with your bank, and you do
   not fill in bank forms — you register your settlement account details inside Paynow.
2. **Complete email validation**, then log in.
3. **Register your settlement bank account** — the account Paynow deposits your takings into.
4. **If you also want Visa/Mastercard**: your business must be **formally registered in
   Zimbabwe**, and you must supply company details plus the **national ID number of the CEO
   or owner**. Mobile money alone (which is all Zvingo currently uses) has the lighter
   requirement. Budget for the company registration if you don't have it — that is a
   Registrar of Companies process, not something Paynow can shortcut.
5. **Create an integration**: go to the **"Other Ways To Get Paid"** page in the merchant
   dashboard. When creating it you choose:
   - a name to identify the integration (use e.g. `Zvingo Production` and a separate
     `Zvingo Test`),
   - whether you **absorb the transaction fees** or pass them to the customer,
   - the email address that receives transaction updates,
   - **which payment methods this integration may use** — tick EcoCash, OneMoney and
     InnBucks, or Zvingo's payment method picker will offer options that fail.
6. **Get the Integration ID** — shown on the integration page. It is unique **per
   integration**, not per account, so several integrations mean several IDs.
7. **Get the Integration Key** — for security it is **never displayed on screen**. Click
   **[Email Key To Company Address]** and it is mailed to the company address on file.
   Treat that email as a secret: forward it nowhere, and delete it once the key is in your
   secret store.

**Time to approval: UNVERIFIED.** Account creation itself is self-service and immediate;
the delay is bank-account verification and (for cards) company verification. Ask Paynow
support directly when you register, and plan for **days, not hours**. Start this first.

#### Cost

| Item | Cost |
|---|---|
| Account / integration setup | No published setup fee (**UNVERIFIED** — confirm on <https://www.paynow.co.zw/Home/Fees>) |
| EcoCash merchant payment fee | **~1.4%** per transaction (**UNVERIFIED for your specific merchant tier** — Paynow's own margin may sit on top) |
| Who pays it | Your choice at integration-creation time: absorb, pass to customer, or split 50/50 |
| Zimbabwe IMTT (government levy) | **2% on USD transfers**, 1.5% on ZiG; exempt under ~US$5 |

**Realistic estimate at 1,000 orders/month**, average basket US$10 ⇒ US$10,000 processed:

- Gateway/mobile-money fees at ~1.4% ≈ **US$140/month**
- IMTT at 2% if it lands on your leg of the transaction ≈ **US$200/month** (**UNVERIFIED** —
  whether IMTT is charged to the payer or the merchant on a Paynow merchant collection is
  exactly the question to put to Paynow in writing before you price your delivery fee)

Budget **US$140–US$340/month** at that volume and treat it as cost-of-goods, not overhead.
Verify the split before setting your commission rate — getting this wrong is the difference
between a 3% and a 5% take rate.

#### Env vars the code reads

| Var | Where it goes | Notes |
|---|---|---|
| `PAYNOW_INTEGRATION_ID` | backend `.env` / compose `environment:` | required in production (`config.py` validator) |
| `PAYNOW_INTEGRATION_KEY` | backend `.env` | **secret** |
| `PAYNOW_RETURN_URL` | backend `.env` | browser redirect after payment, e.g. `https://api.pindira.com/payment/return` |
| `PAYNOW_RESULT_URL` | backend `.env` | server-to-server webhook, **must** be `https://<api host>/api/payment/webhook` |
| `PAYMENT_MOCK_MODE` | backend `.env` | must be `false` in production; compose pins it |

Set the same values in the Paynow integration page itself — Paynow will only call a result
URL it knows about.

> ℹ️ **About the `/api` prefix.** `config.py` defines `API_V1_STR = "/api/v1"`, but that
> value is **only** used for the OpenAPI schema URL — no router is mounted under it
> (`backend/app/main.py` mounts them at `/payment`, `/auth`, `/location`, …). The `/api`
> prefix comes from nginx, which does `rewrite ^/api/(.*) /$1 break` before proxying. So the
> correct public webhook URL really is **`https://<api host>/api/payment/webhook`**, exactly
> as the `.env` examples say. Do not "fix" it to `/api/v1/...`.
>
> Getting this wrong means payments succeed at Paynow and your orders never leave
> `AWAITING_DELIVERY`. Verify by sending a test payment and watching the backend log.

#### How to test it, and how to tell sandbox from production

Paynow's model is **not** a separate sandbox host. A new integration starts in **test mode**
on the same account:

- In test mode no money moves, and you need no EcoCash/OneMoney/Visa access.
- After creating a transaction, **only the merchant account that owns the integration** can
  log in and fake the payment: choose **[TESTING: Faked Success]** → **[Make Payment]**, and
  Paynow calls your result URL as though it were real.
- For mobile-money Express Checkout there are **four pre-configured test mobile numbers**
  that simulate: success after 5 s, success after 30 s (slow user), failure after 30 s (user
  cancels), and an immediate "insufficient balance" failure at initiation. The exact numbers
  are on the Paynow Developer Hub test-mode page — **UNVERIFIED here** because
  `developers.paynow.co.zw` is unreachable from this environment; read them at
  <https://developers.paynow.co.zw/docs/paynow/test_mode/> before you test.
- The `authemail` we send is `order-{order_id}@zvingo.co.zw` (`service.py`). **In test mode
  Paynow requires `authemail` to be a login email on your merchant account** — so a raw test
  through our API will not be completable until you either switch the integration to live or
  temporarily point that field at your merchant email. Flag this to the backend team.

**Telling them apart at a glance:**

| Signal | Mock (ours) | Paynow test mode | Live |
|---|---|---|---|
| `poll_url` | starts `mock://` | a real `paynow.co.zw` URL | a real `paynow.co.zw` URL |
| Log line at boot | `Paynow client initialized in MOCK mode` | `Paynow client initialized (LIVE mode)` | same as test — **the log cannot tell you**; check the integration's mode in the Paynow dashboard |
| Money moves | no | no | yes |
| Payment completes after | exactly 3 s, always | you click "Faked Success" | the customer's PIN |

The 3-second auto-approve is the tell for mock mode: `PaymentService._mock_auto_complete`.

#### Gotchas and compliance

- **The webhook is unauthenticated today.** Paynow signs every inbound status update with a
  `hash` field: concatenate all values except `hash` (URL-decoding each first), append your
  Integration Key, SHA-512 it, uppercase the hex, and compare. `backend/app/payment/router.py`
  does none of this. Until it does, **do not go live** — the endpoint is an open "mark my
  order paid" button. This is the single highest-severity finding in this document.
- The webhook is also **not idempotent-guarded** beyond the payment status check, and looks
  the payment up by `paynow_reference`, which we set to `ZVINGO-{last 8 chars of ObjectId}`.
  Eight hex characters is guessable; combined with the missing hash check, an attacker can
  brute-force references.
- **Refunds do not work in production** (`PaynowClient.refund` returns an explicit failure so
  the DB is never falsely marked `REFUNDED` — a deliberate, correct choice). You must refund
  from the Paynow merchant portal by hand. Write that runbook before launch.
- `PaymentMethod.CARD` exists in the enum but is not implemented. Make sure the app's
  payment picker does not offer it.
- Keep the Integration Key out of git, out of Slack and out of the app bundle. It is a
  server-side secret only.

---

### 2.2 Africa's Talking — SMS / OTP

#### What it does for Zvingo

Transactional SMS. Exactly two messages are sent (`backend/app/auth/router.py`):

1. `Your Zvingo verification code is: {otp}` — **the signup and login OTP.**
2. `Your Zvingo password reset code: {token[:8]}`

Without it **nobody can create an account or log in.** It is not a "nice to have
notification channel"; it is the front door of the product.

Code: `backend/app/sms/gateway.py`. Posts form-encoded to
`https://api.africastalking.com/version1/messaging` with an `ApiKey` header, falling back to
`https://api.sandbox.africastalking.com/...` whenever `AFRICASTALKING_USERNAME == "sandbox"`.

#### Step-by-step signup

1. Create an account at <https://account.africastalking.com/>.
2. You land in the **Sandbox** app by default — click the orange **Go To Sandbox App**
   button. The sandbox username is *always* the literal string `sandbox`.
3. **Generate an API key**: in the app dashboard, Settings → API Key.
   **Copy it immediately** — it is shown once and never again. Losing it means generating a
   new one and redeploying.
4. **Create a production ("live") app** in the dashboard. It gets its **own username** —
   that username is what routes your request to the live network. Mixing a sandbox key with
   a live username (or vice versa) produces authentication errors, not a helpful message.
5. **Complete KYC to go live.** Africa's Talking' terms require you to comply with their KYC
   documentation, explicitly including **a form from the relevant companies registry showing
   your shareholder and director structure**. In practice: you need a **registered Zimbabwean
   company** with its CR14/CR6-equivalent documents, plus a completed Service Order Form.
   There is no consumer-grade path to live SMS.
6. **Register a Sender ID** (the alphanumeric name recipients see instead of a number —
   e.g. `ZVINGO`). Raise the request from the dashboard.
   - Max **11 characters**, the global standard.
   - Zimbabwe's regulator **POTRAZ** governs SMS; sender IDs must be registered or carriers
     filter your traffic. Africa's Talking handles the carrier submission, but the
     documentation is on you.
7. **Fund your account.** Africa's Talking is pre-paid — an empty balance means silent
   delivery failure, and `SMSGateway._send_africastalking` only logs the error and returns
   `False`. Nobody signs up and nothing alerts you.

**Realistic time to approval: 1–3 weeks**, dominated by KYC and sender-ID carrier approval.
**Start this on day 1.** (Exact Zimbabwe turnaround: **UNVERIFIED** — ask their support when
you open the account.)

#### Cost

| Item | Cost |
|---|---|
| Account | Free |
| Sandbox SMS | Free (never delivered to a real handset) |
| **Sender ID setup fee** | **US$35 one-off** (raising the request is free; the setup fee applies) |
| Per-SMS to Zimbabwe | **UNVERIFIED** — the rate is on <https://africastalking.com/pricing>, which is unreachable from this environment. Zimbabwe A2P rates from comparable providers sit in the **US$0.02–US$0.06** band; budget the top of it. |
| Billing model | Pre-paid credit |

**Message length matters and will surprise you.** 160 GSM-7 characters = 1 message. A single
special character (including a curly quote or an emoji) flips the message to UCS-2 and the
limit drops to **70 characters**, doubling your cost. Our OTP text — `Your Zvingo
verification code is: 123456` — is 39 plain ASCII characters, so it is safely one segment.
Keep it that way; do not let anyone add an em-dash.

**Realistic estimate at 1,000 orders/month:** assume ~300 new signups plus password resets
and retries ⇒ **~500–1,200 SMS/month**. At US$0.02–0.06 ⇒ **US$10–US$72/month**. Budget
**US$50/month** plus the one-off US$35 sender ID.

#### Env vars the code reads

| Var | Where it goes | Notes |
|---|---|---|
| `AFRICASTALKING_USERNAME` | backend `.env` | your **live app username** — not `sandbox` |
| `AFRICASTALKING_API_KEY` | backend `.env` | **secret**; required in production |
| `SMS_MOCK_MODE` | backend `.env` | must be `false` in production |
| `SMS_GATEWAY_URL` | backend `.env` | **development only** — the local `sms-mock` container in `docker-compose.yml`. Never set in production. |
| `AT_USERNAME`, `AT_API_KEY` | ⚠️ **read by `backend/app/sms/router.py` only** | Not in `config.py` or any `.env.example`. See the bug note below. |

#### How to test it

- **Sandbox:** set `SMS_MOCK_MODE=false`, `AFRICASTALKING_USERNAME=sandbox`, and your
  sandbox API key. The gateway auto-switches to `api.sandbox.africastalking.com`. Messages
  appear in the sandbox dashboard's simulator, not on a phone.
- **Live smoke test:** set the live username + key, then request an OTP for **your own
  number** in E.164 form (`+263...`). A successful send logs `SMS sent` with the provider's
  JSON, which includes a per-recipient `status` — check it says `Success` and not
  `InsufficientBalance` or `UserInBlacklist`.
- **Telling them apart:** `SMSGateway.__init__` picks the URL purely from the username
  string. If `AFRICASTALKING_USERNAME` is the literal `sandbox`, you are on sandbox no
  matter what key you supply. There is no other switch.

#### Gotchas

- **Silent failure mode.** A send failure is logged and swallowed (returns `False`); the OTP
  endpoint still returns success to the client. A user gets "code sent" and no code. Add an
  alert on the `SMS send failed` log event before launch, and watch your credit balance.
- **`backend/app/sms/router.py` is a dead second integration.** It initialises its own
  Africa's Talking client from `AT_USERNAME` / `AT_API_KEY` — env names that exist nowhere
  else in the repo. `POST /api/sms/send` will therefore mock forever even when the rest
  of the app is live. Either delete that router or make it use `settings`. Reported to the
  backend team; **do not "fix" it by adding `AT_*` to your `.env`** — that duplicates a
  secret under two names.
- Phone numbers must be **E.164** (`+263...`). The repo already uses `phonenumbers` for this.
- Zimbabwe A2P traffic is regulated; unregistered sender IDs get filtered by Econet/NetOne
  rather than bounced, so "some users don't get the OTP" is the failure you should expect if
  sender-ID registration is incomplete.

---

### 2.3 Firebase Cloud Messaging — push notifications

#### What it does for Zvingo

Push notifications to a **backgrounded or closed** app. `backend/app/notification/service.py`
calls `send_push_notification` in two places — order-status changes for consumers and offer
notifications for drivers.

> **Read this before you spend an hour on it.** Configuring Firebase on the server today
> achieves **nothing**, because there is **no client**. Neither Flutter app depends on
> `firebase_core` / `firebase_messaging`, neither has a `google-services.json` or
> `GoogleService-Info.plist`, and nothing anywhere calls `POST /api/auth/fcm-token`. So
> `User.fcm_token` is always `None`, and `service.py` skips the push before it ever reaches
> the FCM code. The server side is a correctly-built half of a bridge to nowhere.
>
> Firebase setup is still worth doing — it is free and takes 15 minutes — but schedule the
> **client-side work** (add the plugins, register the token on login, handle the
> notification tap) as a real engineering task or push will never work.

While there is no push, driver offers still arrive over the WebSocket channel **whenever the
driver app is in the foreground**. A driver who locks their phone misses offers. That is the
practical business impact.

#### Step-by-step signup

1. Go to <https://console.firebase.google.com/> and sign in with a Google account you
   control as a business (not a personal Gmail you might lose).
2. **Add project** → name it `zvingo` → you can disable Google Analytics.
3. **Register the apps** (needed for the client work):
   - **⚙️ Project settings → General → Your apps → Add app → Android.**
     Package name must exactly match `applicationId` in `android/app/build.gradle`:
     `com.zvingo.consumer_app` and `com.zvingo.driver_app`. Download
     `google-services.json` into `android/app/` for each.
   - **Add app → iOS.** Bundle IDs are `com.zvingo.consumerApp` and `com.zvingo.driverApp`
     (from `ios/Runner.xcodeproj/project.pbxproj`). Download `GoogleService-Info.plist` into
     `ios/Runner/`.
   - For iOS push you must additionally upload an **APNs Authentication Key (.p8)** from the
     Apple Developer portal — Firebase cannot deliver to iPhones without it. See §4.2.
4. **Get the server credential**: **⚙️ Project settings → Service accounts →
   Generate new private key** → downloads a JSON file.
5. Save it as `backend/firebase-credentials.json`. The backend `Dockerfile` copies it to
   `/app`, which is why `FIREBASE_CREDENTIALS_PATH=firebase-credentials.json` (a relative
   path) is the right default.
6. **Confirm it is gitignored.** That JSON is a service-account private key — it can send
   push to every one of your users. Check `backend/.dockerignore` and `.gitignore` before
   you put the file on disk.

**Time to approval: immediate.** No verification, no business documents.

#### Cost

**US$0.** Firebase Cloud Messaging is free and unlimited on both the Spark (free) and Blaze
(pay-as-you-go) plans, at any volume. Stay on Spark — Zvingo uses no other Firebase product,
so there is nothing to meter.

#### Env vars the code reads

| Var | Where it goes | Notes |
|---|---|---|
| `FIREBASE_CREDENTIALS_PATH` | backend `.env` | path **inside the container**. Default `firebase-credentials.json`. If the file is missing, push is disabled with a log line and everything else still works. |

The `firebase-admin ^6.4` dependency is already in `pyproject.toml`.

#### How to test it

1. Start the backend and look for `Firebase initialized successfully` at boot. If you see
   `Firebase not configured (no FIREBASE_CREDENTIALS_PATH)` or `Firebase init failed`, stop
   there.
2. Once the client work exists: log in on a real device, confirm `User.fcm_token` is
   populated in Mongo, background the app, and trigger an order-status change.
3. Log line `FCM sent` with a message ID = success. `FCM send failed` = a real error;
   `FCM not available, logging notification` = you never initialised.

There is no sandbox/production split in FCM. One project, one credential.

#### Gotchas

- The service-account JSON is as powerful as your backend. Rotate it (Service accounts →
  the key → delete, then generate new) if it is ever emailed, pasted or committed.
- FCM tokens rotate. The client must re-register on every app start, not only at signup, or
  push quietly stops for returning users.
- Android 13+ requires the **`POST_NOTIFICATIONS`** runtime permission. Neither
  `AndroidManifest.xml` declares it. It must be added alongside the client work or push is
  invisible on every modern Android device.

---

### 2.4 CARTO Basemaps — map tiles

#### What it does for Zvingo

Every map image in both apps. `flutter_map` is only the renderer — the actual map pictures
come from CARTO's "Voyager" raster tiles:

```
https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png
```

Five call sites: consumer `restaurant_map_screen.dart`, `order_tracking_screen.dart`,
`order_live_map.dart`; driver `offer_screen.dart`, `home_screen.dart`, `navigation_map.dart`.

Features that break if tiles stop: restaurant map view, live order tracking, the driver's
offer preview, the driver home map, and turn-by-turn navigation. That is most of the visual
product.

#### Step-by-step signup

The app currently uses the tiles **with no API key and no account**, which works today.
The CARTO Basemap Terms and Conditions (last updated **26 August 2026**) describe the free
tier as available "to any Customer who **requests and uses a CARTO-issued API key**", subject
to a fair-use limit, and reserve the right to "suspend, rate-limit, or terminate" access
"at any time, in its sole discretion and for any or no reason, without prior notice".

**Recommended action: get an API key so you are a known customer rather than anonymous
traffic.**

1. Sign up at <https://carto.com/signup> (free tier).
2. Create an API key in the workspace and note the exact keyed tile URL CARTO gives you.
3. Hand that URL to the mobile team to replace the five hard-coded `urlTemplate` strings.

**UNVERIFIED:** whether the keyless `{s}.basemaps.cartocdn.com` endpoint remains served
indefinitely, and the exact form of the keyed URL — `carto.com` and `docs.carto.com` are
unreachable from this environment. Read <https://docs.carto.com/faqs/carto-basemaps> and
<https://carto.com/legal/basemap-terms/> directly before implementing.

#### Cost

| Item | Cost |
|---|---|
| Free tier | **US$0** up to a fair-use limit of **5,000,000 tile requests per calendar month** |
| Above that | Paid plan; CARTO does not publish a public per-tile price — **UNVERIFIED**, contact sales |

**Estimate at 1,000 orders/month:** a live-tracking screen open for a 20-minute delivery,
panning and zooming, pulls on the order of a few hundred tiles. At 1,000 orders plus browsing
and driver navigation, assume **500–1,500 tiles per order** ⇒ **0.5M–1.5M tiles/month**.
Comfortably inside the free tier, but **within one order of magnitude of it** — at 5,000
orders/month you will cross it. Add tile-request telemetry before you scale, and cache tiles
on-device (`flutter_map` supports a tile provider with caching; we currently use the default
network provider with no cache).

#### Env vars

**None today** — the URL is hard-coded in five Dart files. If you adopt an API key, ask the
mobile team to route it through `--dart-define` and `AppConfig`, the same mechanism
`API_BASE_URL` already uses, rather than hard-coding a second secret into the binary.
(Note: a tile API key shipped in an app bundle is extractable by anyone. That is normal and
accepted for basemap keys — restrict it by bundle ID/referrer in the CARTO console rather
than trying to hide it.)

#### Compliance — attribution (this one is a real breach today)

Both the CARTO Basemap Terms and the OpenStreetMap ODbL licence require visible credit on
**every** map:

- **"© OpenStreetMap contributors"** — required by ODbL for the underlying data.
- **"© CARTO"** with a link to <https://carto.com/> — required by the basemap terms.
- If the style derives from the OpenMapTiles schema, **"OpenMapTiles"** with a link to
  <http://openmaptiles.org/> is also required.

Today **only** `consumer_app/lib/features/restaurant/restaurant_map_screen.dart` renders a
`RichAttributionWidget`. The other five maps show tiles with **no attribution at all**.
Shipping that to the App Store and Play Store is a licence breach on both counts.

**Fix (for the mobile agents, not this document):** add the same `RichAttributionWidget` to
every `FlutterMap` that has a `TileLayer`, with both `TextSourceAttribution` entries and
working `onTap` links. `flutter_map`'s attribution widget collapses to a small "ⓘ" badge, so
it costs almost no screen space — there is no design reason to omit it.

The `userAgentPackageName` is already correctly set to `com.zvingo.consumer` /
`com.zvingo.driver` at each call site. Note those strings do **not** match the real
application IDs (`com.zvingo.consumer_app` / `com.zvingo.driver_app`) — worth aligning.

---

### 2.5 OpenStreetMap Nominatim — address search

#### What it does for Zvingo

Forward geocoding: turning what a customer types ("Borrowdale Village") into coordinates.

- `backend/app/location/service.py` → `GET https://nominatim.openstreetmap.org/search`
  with `countrycodes=zw`, `limit=5`, `User-Agent: "Zvingo/1.0"`.
- Exposed as `GET /api/location/geocode?q=...`.
- Consumed by `consumer_app/lib/features/address/address_search_sheet.dart`.

If it breaks, **customers cannot search for a delivery address** — they fall back to
dropping a pin, which the app does support, so it degrades rather than dies.

#### Signup

**There is no signup. That is precisely the problem.** The public Nominatim instance is a
donation-funded service run by the OpenStreetMap Foundation for casual use, and its
[Usage Policy](https://operations.osmfoundation.org/policies/nominatim/) is a hard
condition of use, not a suggestion:

- **Absolute maximum 1 request per second. No heavy uses.**
- Scripts that run for longer than a day or on a schedule are limited to **4 requests per
  minute**.
- **Results must be cached on your side.**
- You must send a **valid `User-Agent` or `Referer` that identifies your application** —
  stock library user agents are explicitly not acceptable.
- Attribution of OpenStreetMap data is required.
- Breach gets your **server's IP blocked**, with no warning and no appeal queue you can rely
  on.

**How Zvingo breaches it today:**

| Requirement | Zvingo today |
|---|---|
| ≤ 1 req/sec | **No throttle at all.** `GET /api/location/geocode` is **unauthenticated** and un-rate-limited, so any user typing in the address box — or any stranger with curl — issues one upstream request per keystroke-debounce, from our single server IP. |
| Cache results | **No cache.** `LocationService.geocode` opens a fresh `httpx.AsyncClient` per call. |
| Identifying User-Agent | `"Zvingo/1.0"` — better than a stock UA, but it carries **no contact URL or email**, which is what OSMF actually needs to reach you before blocking. |
| Not a heavy use | A food-delivery app's address box at any real scale **is** a heavy use. |

**This is a launch blocker.** Not because of a bill, but because one afternoon of traffic can
have OSMF block your droplet's IP, and address search then fails for every customer
simultaneously with no fallback and no way to fix it quickly.

#### What to do instead (pick one before launch)

| Option | Cost | Effort | Notes |
|---|---|---|---|
| **A. Keep Nominatim, but comply** | Free | Medium | Add auth to `/location/geocode`, add a Redis cache (query→results, ~24h TTL — addresses don't move), add a server-side 1 req/sec token bucket, and change the User-Agent to `Zvingo/1.0 (+https://<your-domain>; ops@<your-domain>)`. Still fragile: you have one shared quota for the whole business, and it is still arguably a "heavy use". |
| **B. Self-host Nominatim** | ~US$24/mo extra droplet (needs ~8 GB RAM for a country extract) | High | Full control, no rate limit, no licence risk beyond attribution. A Zimbabwe-only extract is small. Best long-term answer. |
| **C. Commercial geocoder** | From ~US$0 (free tiers) | Low | LocationIQ, Geoapify and MapTiler all sell OSM-based geocoding with generous free tiers and a proper SLA. Drop-in: one URL and one API key in `LocationService.geocode`. **Pricing UNVERIFIED** — check each provider's current page. |

**Recommendation: (C) for launch, (B) when volume justifies it.** Option (A) is the one that
looks cheapest and is most likely to take address search down on your busiest day.

Whatever you choose, **add auth + caching + throttling to `/api/location/geocode`
regardless** — an open, uncached, unthrottled proxy to *anyone's* geocoder is a bill or a ban
waiting to happen.

#### Env vars

**None today** — the URL is a module constant (`NOMINATIM_URL`). Moving it (and a future API
key) into `config.py` is the change to request from the backend team; suggested names
`GEOCODER_URL`, `GEOCODER_API_KEY`, `GEOCODER_USER_AGENT`.

---

### 2.6 Platform geocoder (Android/iOS) — reverse geocoding

`consumer_app` depends on `geocoding: ^3.0.0`, used in `address_provider.dart` to turn the
device's GPS fix into a street name.

- **Account needed: none. Cost: US$0.**
- On Android it calls the system `Geocoder` (backed by Google Play Services); on iOS it calls
  CoreLocation. No API key, no quota you can see.
- **Gotcha:** on Android devices without Google Play Services (some cheap handsets, and any
  Huawei device) the system geocoder returns nothing and the address silently comes back
  empty. Make sure the UI has a sensible fallback — this is a real segment of the Zimbabwean
  handset market, not an edge case.

---

### 2.7 Domain name and DNS

#### What it does for Zvingo

Everything public hangs off it: the API host the mobile apps are compiled against, the
merchant dashboard, the TLS certificate, and the Paynow return/result URLs.

#### ⚠️ The repo currently disagrees with itself about the domain

| Where | Value |
|---|---|
| `nginx/nginx.prod.conf`, `.env.production.example` | `pindira.com` |
| `nginx/nginx.api.conf`, `.env.backend.example` | `api.pindira.com` |
| `nginx/nginx.dashboard.conf`, `.env.dashboard.example` | `app.pindira.com` |
| `consumer_app/lib/core/app_config.dart` default | `http://api.pindira.com/api` |
| `consumer_app/BUILD.md`, `driver_app/BUILD.md` | `https://api.zvingo.com` |
| `driver_app/lib/core/app_config.dart` default | `http://10.0.2.2:8000` (emulator) |

**Pick one name and make every file agree before anything else.** A release build compiled
against the wrong hostname is a store resubmission, not a config change. (Both `BUILD.md`
files in this document's boundary have been corrected to use a single placeholder; the Dart
defaults are outside it and are flagged for the mobile agents.)

#### Step-by-step

1. **Choose the TLD.**
   - **`.co.zw`** — signals a Zimbabwean business, which matters for consumer trust and for
     Paynow/AT verification. Registered through a ZISPA-accredited registrar; you cannot
     register directly with ZISPA. Registrars include <https://www.name.co.zw/pricing> and
     Techzim.
   - **`.com`** — universal, ~US$12/year at any registrar, no residency questions.
   - Consider buying both and redirecting one.
2. **Register it** and enable registrar-level 2FA and domain lock. A stolen domain is a
   stolen business.
3. **Create DNS records** (per `DEPLOYMENT.md` §2):
   - Single-host layout: `A  @  → <droplet IPv4>` (plus `AAAA` if you have IPv6).
   - Split layout: `A  api → <backend droplet IP>` and `A  app → <dashboard droplet IP>`.
4. **Wait for propagation** (minutes to a few hours) and verify with
   `dig +short api.your-domain.com` before running certbot — certbot fails if DNS hasn't
   caught up.
5. **Update `server_name` in the nginx config you are using** — both the `:80` and `:443`
   server blocks. `DEPLOYMENT.md` gives a `sed` one-liner.

#### Cost

| Item | Cost |
|---|---|
| `.co.zw` | **~US$5–25/year** depending on registrar; ZISPA charges more for non-resident registrants |
| `.com` | ~US$12/year |
| DNS hosting | US$0 (registrar's, or DigitalOcean's free DNS) |

**Time: under an hour**, plus DNS propagation. Do it today — the TLS certificate, the Paynow
result URL, and both mobile release builds all depend on it.

---

### 2.8 TLS certificates — Let's Encrypt

#### What it does for Zvingo

HTTPS on the API and dashboard hosts. This is not optional:

- `consumer_app` release builds **throw at start-up** on a non-HTTPS `API_BASE_URL`
  (`AppConfig.validate()`).
- Both Android apps set `cleartextTrafficPermitted="false"` for everything except
  `10.0.2.2`, `10.0.3.2`, `localhost`, `127.0.0.1` (`network_security_config.xml`).
- iOS App Transport Security blocks cleartext by default.
- nginx will not start without `fullchain.pem` and `privkey.pem` in `./nginx/certs`.

#### Step-by-step

Per `DEPLOYMENT.md` §4, on the droplet with DNS already pointing at it:

```sh
sudo apt install -y certbot
# stop anything on port 80 first, then:
sudo certbot certonly --standalone -d api.your-domain.com
mkdir -p nginx/certs
sudo cp /etc/letsencrypt/live/api.your-domain.com/{fullchain,privkey}.pem nginx/certs/
```

Repeat for the dashboard host in a split deployment.

**Renewal — read this, it is the thing that takes you down 90 days after launch.**
Let's Encrypt certificates last **90 days**. The compose files share a `certbot_webroot`
volume and nginx serves `/.well-known/acme-challenge/` from it, so renewal works
**webroot-style without downtime**:

```sh
docker run --rm \
  -v zvingo_certbot_webroot:/var/www/certbot \
  certbot/certbot renew --webroot -w /var/www/certbot
# then copy the renewed certs into nginx/certs/ and reload nginx
```

But that copy-and-reload is **manual today**. Put it in a cron job on day 1:

```sh
# /etc/cron.d/zvingo-certs  — 03:17 on the 1st and 15th
17 3 1,15 * * root docker run --rm -v zvingo_certbot_webroot:/var/www/certbot certbot/certbot renew --webroot -w /var/www/certbot && cp /etc/letsencrypt/live/api.your-domain.com/{fullchain,privkey}.pem /opt/zvingo/nginx/certs/ && docker compose -f /opt/zvingo/docker-compose.backend.yml exec nginx nginx -s reload
```

Also set up the **expiry reminder emails** certbot registers for you, and add an external
uptime check that alerts on certificate expiry — you want to hear it from a monitor, not
from a driver whose app stopped working.

#### Cost

**US$0.** Let's Encrypt is free, forever, with no account fee.

**Time: 10 minutes**, once DNS resolves.

#### Gotchas

- `--standalone` needs port 80 free — stop nginx/compose first or it fails.
- Rate limit: **5 duplicate certificates per exact name set per week.** Do not loop on
  failures; use `--dry-run` while you're debugging.
- nginx mounts `./nginx/certs` **read-only** (`:ro`) — copy files in from the host, don't try
  to write from inside the container.

---

### 2.9 Hosting — DigitalOcean

#### What it does for Zvingo

Runs everything server-side: FastAPI, MongoDB, Redis, nginx and (optionally) the Next.js
merchant dashboard.

#### Step-by-step

1. Create an account at <https://www.digitalocean.com/> (card required; there are usually
   new-account credits worth checking).
2. **Create a Droplet**: Ubuntu 24.04 LTS, **Basic** plan.
   - `DEPLOYMENT.md` is explicit: **2 GB RAM minimum, 4 GB recommended.** A 512 MB droplet
     cannot build *or* run the stack. The Next.js dashboard build alone needs ~1.5 GB.
3. **Use SSH-key authentication**, not a password. Paste your public key during creation.
4. **Add a DigitalOcean Cloud Firewall** (`DEPLOYMENT.md` §1 warns that Docker punches
   through host `iptables`, so a UFW rule alone will *not* protect a published container
   port). Allow inbound:
   - `22/tcp` — SSH, ideally restricted to your own IP
   - `80/tcp`, `443/tcp` — HTTP/HTTPS
   - `9090/udp`, `9091/tcp` — **BinProto driver telemetry** (these bypass nginx by design)
   - Deny everything else. Note Mongo (27017) and Redis (6379) are deliberately **not**
     published in the production compose files — keep it that way.
5. Install Docker + Docker Compose, clone the repo (use a **read-only deploy key** for a
   private repo, not your personal key), fill in `.env`, and
   `docker compose -f docker-compose.backend.yml up -d --build`.
6. **Turn on automated backups** (see §2.10).

#### Which layout?

| Layout | Droplets | Cost | When |
|---|---|---|---|
| **Single host** (`docker-compose.prod.yml`) | 1 × 4 GB | **US$24/mo** | Launch. Everything on one box behind one nginx, dashboard at `/`. |
| **Split** (`docker-compose.backend.yml` + `docker-compose.dashboard.yml`) | 1 × 4 GB + 1 × 2 GB | **US$24 + US$12 = US$36/mo** | When the dashboard build starts competing with the API for RAM, or you want them to fail independently. Needs two certs and `CORS_ORIGINS` set correctly. |

#### Cost

| Item | Cost |
|---|---|
| Basic droplet, 2 GB / 1 vCPU | **US$12/mo** (2 TB transfer) |
| Basic droplet, 2 GB / 2 vCPU | **US$18/mo** (3 TB transfer) |
| Basic droplet, 4 GB / 2 vCPU | **US$24/mo** (4 TB transfer) — the recommended size |
| Automated backups | **+20%** of droplet cost (~US$4.80/mo on a 4 GB) |
| Outbound bandwidth over the included allowance | US$0.01/GiB |
| Pricing by region | Flat — same price everywhere |

**Realistic estimate: US$29–US$45/month** (one 4 GB droplet with backups, or the split
layout). Billing is per-second since 1 Jan 2026 and capped at the monthly price.

**Time: under an hour.** No approval, no waiting. But the closest DigitalOcean regions to
Zimbabwe are in Europe (AMS/FRA/LON) — **UNVERIFIED** whether DO has an African region today;
check the region list when you create the droplet. Expect **~150–200 ms** of latency to
Harare from Europe. That is fine for HTTP, and the WebSocket/BinProto channels are designed
for it, but it is worth measuring before you blame the app for feeling slow.

---

### 2.10 MongoDB and Redis

Self-hosted inside Docker Compose. **No third-party account, no cost** beyond the droplet.

**What you must do:**

1. **Generate credentials** — they have no defaults and compose refuses to start without
   them:
   ```sh
   openssl rand -hex 24   # → MONGO_INITDB_ROOT_PASSWORD
   openssl rand -hex 24   # → REDIS_PASSWORD
   ```
2. Note that in production compose, **neither service publishes a host port** — they are
   reachable only on the internal Docker network. Do not "temporarily" add a `ports:` entry
   to debug; use `docker compose exec`.
3. **Back up.** This is the gap. `DEPLOYMENT.md` §8 documents a manual `mongodump` against
   the volume. At minimum:
   - Turn on **DigitalOcean automated droplet backups** (+20% of droplet cost) — weekly
     snapshots, easy restore, but coarse.
   - Add a nightly `mongodump` to object storage (DigitalOcean Spaces is ~US$5/mo for 250 GB)
     so you can restore a single collection without rolling back the whole box.
   - **Test a restore before launch.** An untested backup is a hope.

**Managed alternative (optional):** MongoDB Atlas has a free M0 tier and paid tiers from
~US$9/mo, which buys you backups and failover you don't have to operate. `MONGODB_URL` is a
plain connection string, so switching is a one-line change. **Current Atlas pricing:
UNVERIFIED** — check <https://www.mongodb.com/pricing>.

---

### 2.11 Google Maps — NOT used (do not buy a key)

I checked: there is **no** reference to `maps.googleapis.com`, `google_maps_flutter`, a Maps
SDK, or a `MAPS_API_KEY` meta-data entry anywhere in the repo. Zvingo renders maps with
`flutter_map` + CARTO tiles (§2.4) and geocodes with Nominatim (§2.5) and the platform
geocoder (§2.6).

**You do not need a Google Maps Platform account or a billing-enabled GCP project.** If
anyone tells you otherwise, they are reading a stale doc. The one Google account you do need
is a **Firebase** project (§2.3), which is free and separate.

---

## 3. Complete environment-variable reference

Derived from `backend/app/config.py` (the `Settings` class is the single source of truth for
the backend), the four `docker-compose*.yml` files, `merchant-dashboard/`, and the two
Flutter `app_config.dart` files. **Every example value below is fake. Never paste a real
secret into a file that is tracked in git.**

Legend: **R** = required (start-up fails without it) · **R-prod** = required when
`ENVIRONMENT=production` · **O** = optional

### 3.1 Backend — core

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `ENVIRONMENT` | O | `development` | `production` | `config.py` validator, `main.py` logging | `production` switches on the safety validator (rejects mock modes, placeholder `SECRET_KEY`, missing Paynow/AT creds) and forces JSON logs. |
| `MONGODB_URL` | **R** | *none — start-up fails* | `mongodb://zvingo_admin:REPLACE_ME@mongo:27017/zvingo?authSource=admin` | Beanie/motor | Database connection string. Production compose builds it from the Mongo root user/password. |
| `MONGODB_DB_NAME` | O | `zvingo` | `zvingo` | Beanie init | Database name. |
| `REDIS_URL` | **R** | *none — start-up fails* | `redis://:REPLACE_ME@redis:6379/0` | dispatch pub/sub, OTP store, rate limiter, exchange rates | Note the leading `:` before the password — Redis AUTH with no username. |
| `PROJECT_NAME` | O | `Zvingo` | `Zvingo` | OpenAPI title | Cosmetic. |
| `API_V1_STR` | O | `/api/v1` | `/api/v1` | **only** the OpenAPI schema URL in `main.py` | ⚠️ Misleading name: **no router is mounted under this prefix.** Routers sit at `/auth`, `/payment`, `/location`, … and the public `/api` prefix is added by nginx (`rewrite ^/api/(.*) /$1 break`). Changing this changes only where `openapi.json` is served. |

### 3.2 Backend — security

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `SECRET_KEY` | **R-prod** | `changethis` ⚠️ | `4f1c…64 hex chars…9ab2` | JWT signing (`auth/service.py`) | **MUST CHANGE BEFORE PRODUCTION.** `openssl rand -hex 32`. Values in `KNOWN_INSECURE_SECRETS` (`changethis`, `changeme`, `secret`, `generate-a-random-64-char-string-here`) are rejected outright. |
| `ALGORITHM` | O | `HS256` | `HS256` | JWT | Leave alone. |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | O | `11520` (8 days) | `11520` | JWT | Token lifetime. Long by design so drivers aren't logged out mid-shift. |
| `CORS_ORIGINS` | **R-prod** | `""` | `https://app.pindira.com,https://pindira.com` | `main.py` CORS middleware | Comma-separated browser origins. Empty ⇒ `*` **in development only**; in production empty means **no origin is allowed** and every dashboard request fails CORS. `*` is not legal here because the backend sends credentials. |
| `METRICS_TOKEN` | O | *(unset)* | `9f2a…32 hex…` | `GET /metrics` | When set, requires `Authorization: Bearer <token>`. Optional because nginx already denies `/api/metrics` publicly. |

### 3.3 Backend — payments (Paynow)

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `PAYMENT_MOCK_MODE` | **R-prod** | `true` ⚠️ | `false` | `PaynowClient` | **MUST BE `false` IN PRODUCTION.** `true` auto-approves every payment after 3 s without contacting Paynow. Production start-up refuses while it is on. |
| `PAYNOW_INTEGRATION_ID` | **R-prod** | *(unset)* | `12345` | `PaynowClient` | From the Paynow merchant dashboard → Other Ways To Get Paid. |
| `PAYNOW_INTEGRATION_KEY` | **R-prod** | *(unset)* | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` | `PaynowClient` | **SECRET.** Emailed to you via [Email Key To Company Address]; never shown on screen. |
| `PAYNOW_RETURN_URL` | O (set it) | `http://localhost/payment/return` | `https://api.pindira.com/payment/return` | `PaynowClient` | Where Paynow redirects the customer's browser after payment. |
| `PAYNOW_RESULT_URL` | O (set it) | `http://localhost/api/payment/webhook` | `https://api.your-domain.com/api/payment/webhook` | `PaynowClient` | Server-to-server status callback. **Must be reachable from the public internet over HTTPS.** The `/api` prefix is added by nginx, which rewrites it away before proxying — see §2.1. |

### 3.4 Backend — SMS (Africa's Talking)

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `SMS_MOCK_MODE` | **R-prod** | `true` ⚠️ | `false` | `SMSGateway` | **MUST BE `false` IN PRODUCTION.** `true` logs the OTP instead of sending it. |
| `AFRICASTALKING_USERNAME` | **R-prod** | `sandbox` ⚠️ | `zvingo_live` | `SMSGateway` | The literal string `sandbox` routes to `api.sandbox.africastalking.com`. Anything else routes live. This is the **only** sandbox/live switch. |
| `AFRICASTALKING_API_KEY` | **R-prod** | *(unset)* | `atsk_0123456789abcdef0123456789abcdef` | `SMSGateway` | **SECRET.** Shown once at generation. |
| `SMS_GATEWAY_URL` | O | *(unset)* | `http://sms-mock:8000` | `SMSGateway._send_mock` | **Development only** — the `sms-mock` container in `docker-compose.yml`. Never set in production. |
| `AT_USERNAME` | ⚠️ orphan | `sandbox` | — | `backend/app/sms/router.py` **only** | Not part of `Settings`. Do **not** set it; fix the code instead (§8). |
| `AT_API_KEY` | ⚠️ orphan | `""` | — | `backend/app/sms/router.py` **only** | Same. Setting it duplicates a secret under a second name. |

### 3.5 Backend — push (Firebase)

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `FIREBASE_CREDENTIALS_PATH` | O | *(unset)* | `firebase-credentials.json` | `notification/fcm.py` | Path **inside the container** to the service-account JSON. Relative paths resolve against `/app`, where the Dockerfile copies `backend/firebase-credentials.json`. Unset ⇒ push disabled with a log line; nothing else breaks. |

### 3.6 Backend — uploads

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `UPLOAD_BASE_URL` | O (set it) | `http://localhost:8000` | `https://api.pindira.com` | `upload/router.py` | Prefix for returned image URLs. **Must be the host that actually serves `/static/uploads/`.** Wrong value ⇒ every menu photo 404s in the app. |
| `MAX_UPLOAD_SIZE_BYTES` | O | `5242880` (5 MB) | `5242880` | `upload/router.py` | Per-file cap. Keep it in step with nginx's `client_max_body_size`. |

### 3.7 Backend — dispatch, scheduling, finance

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `DISPATCH_RETRY_INTERVAL_SECONDS` | O | `120` | `120` | `dispatch/retry_service.py` | How often stuck orders are re-offered. |
| `DISPATCH_MAX_RETRY_ATTEMPTS` | O | `10` | `10` | `dispatch/retry_service.py` | Gives up after this many re-offers and raises an alert. |
| `SCHEDULED_POLL_INTERVAL_SECONDS` | O | `15` | `15` | scheduled-order poller | How often to look for due scheduled orders. |
| `SCHEDULED_DISPATCH_LEAD_MINUTES` | O | `15` | `15` | scheduled-order poller | How far ahead of the requested slot to release an order, so the driver *arrives* on time rather than *setting off* then. |
| `DRIVER_SHARE_RATIO` | O | `0.85` | `0.85` | `finance/fee_calculator.py` | Fraction of the delivery fee the driver keeps. **This is a commercial lever — decide it deliberately.** |
| `LOCATION_UPDATE_RATE_LIMIT` | O | `30` | `30` | `rate_limiter.py` | Max driver location updates per window. The driver app reports every ~3 s (~20/min), so 30 leaves headroom. |
| `LOCATION_UPDATE_WINDOW_SECONDS` | O | `60` | `60` | `rate_limiter.py` | The window for the above. |
| `BINPROTO_UDP_PORT` | O | `9090` | `9090` | `main.py` lifespan | Binary location protocol, UDP. Published directly, **bypassing nginx and TLS**. |
| `BINPROTO_TCP_PORT` | O | `9091` | `9091` | `main.py` lifespan | Same, TCP. |

### 3.8 Backend — observability and alerting

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `LOG_LEVEL` | O | `INFO` | `INFO` | structlog | `DEBUG`\|`INFO`\|`WARNING`\|`ERROR`. |
| `LOG_JSON` | O | `false` | `false` | structlog | One JSON object per line. **Always on when `ENVIRONMENT=production`** regardless of this value. |
| `METRICS_ENABLED` | O | `true` | `true` | `GET /metrics` | Prometheus text-format endpoint. |
| `ALERTS_ENABLED` | O | `true` | `true` | alert monitor | Background monitor publishing to the Redis `alerts` channel and `GET /api/admin/alerts`. |
| `ALERT_POLL_INTERVAL_SECONDS` | O | `300` | `300` | alert monitor | How often it runs. |
| `ALERT_STUCK_ORDER_MINUTES` | O | `30` | `30` | alert monitor | An order in one state this long raises an alert. |
| `ALERT_FAILED_PAYMENT_THRESHOLD` | O | `5` | `5` | alert monitor | Failed payments within the window before alerting. **Tune this down for launch** — 5 failures is a lot when you're doing 30 orders a day. |
| `ALERT_WINDOW_MINUTES` | O | `60` | `60` | alert monitor | The window for the above. |
| `ALERT_HISTORY_SIZE` | O | `100` | `100` | alert monitor | In-memory ring buffer of recent alerts. |

### 3.9 Backend — development helpers (must stay off in production)

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `DEV_ALLOW_ADMIN_ENDPOINTS` | O | `false` | `false` | admin routes | ⚠️ **Never `true` in production.** Unlocks unauthenticated admin helpers. |
| `DEV_FORCE_DEFAULT_RESTAURANT_LOCATION` | O | `false` | `false` | catalog | Forces every restaurant to a synthetic location for demos. |
| `DEV_DEFAULT_BASE_LAT` | O | `37.4219983` ⚠️ | `-17.8292` | catalog | **The default is Mountain View, California**, not Harare. Only used when the flag above is on, but it is a trap waiting for someone. |
| `DEV_DEFAULT_BASE_LNG` | O | `-122.084` ⚠️ | `31.0522` | catalog | Same. |
| `DEV_DEFAULT_OFFSET_MILES` | O | `5.0` | `5.0` | catalog | Scatter radius for the above. Note: **miles**, in a metric country. |

### 3.10 Docker Compose — infrastructure (not read by the app)

These are consumed by `docker-compose*.yml` itself. Every one marked `${VAR:?}` makes compose
**fail fast** rather than start insecurely.

| Variable | Req | Default | Example | Used by | What it does |
|---|---|---|---|---|---|
| `MONGO_INITDB_ROOT_USERNAME` | **R** | *(none)* | `zvingo_admin` | `mongo` service | Mongo root user, created on first boot of an empty volume. |
| `MONGO_INITDB_ROOT_PASSWORD` | **R** | *(none)* | `REPLACE_ME_openssl_rand_hex_24` | `mongo` service | **SECRET.** `openssl rand -hex 24`. Changing it later does **not** change the existing user — you must alter it inside Mongo. |
| `REDIS_PASSWORD` | **R** | *(none)* | `REPLACE_ME_openssl_rand_hex_24` | `redis` service | **SECRET.** Becomes `redis-server --requirepass`. |
| `DOMAIN` | O | `pindira.com` | `your-domain.com` | `.env.production.example` | Documentation only — you must still edit `server_name` in the nginx conf by hand. |
| `API_DOMAIN` | O | `api.pindira.com` | `api.your-domain.com` | `.env.backend.example` | Same, for the split backend host. |
| `DASHBOARD_DOMAIN` | O | `app.pindira.com` | `app.your-domain.com` | `.env.dashboard.example` | Same, for the split dashboard host. |
| `NODE_BUILD_MEMORY_MB` | O | `1536` | `1536` | dashboard build arg | Caps the V8 heap during `next build`. Lower it on a small droplet so Node garbage-collects instead of being OOM-killed. |

### 3.11 Merchant dashboard (Next.js)

⚠️ **`NEXT_PUBLIC_*` values are inlined into the browser bundle at BUILD time.** Changing
them requires `docker compose … up -d --build`, not a restart. And because they ship to the
browser, **never put a secret in a `NEXT_PUBLIC_*` variable.**

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `NEXT_PUBLIC_API_URL` | **R** | `/api` (api.ts) / `http://localhost:8000` (uploads) | `https://api.pindira.com/api` | `merchant-dashboard/lib/api.ts` | Base URL the browser calls, **including the `/api` prefix**. Leaving it blank makes the upload path fall back to `http://localhost:8000` — which in a visitor's browser means *their own machine*, so image uploads silently break. |
| `API_PROXY_URL` | O | `http://localhost:80` | `http://nginx:80` (single host) / `https://api.pindira.com/api` (split) | `merchant-dashboard/next.config.ts` | Server-side rewrite target for server-rendered fetches. **Never `localhost` in a container** — that is the dashboard container itself. |
| `NEXT_PUBLIC_DEFAULT_RESTAURANT_LAT` | O | `-17.82` (in code) | `-17.8292` | `app/dashboard/menu/page.tsx` | Initial centre of the restaurant location picker. |
| `NEXT_PUBLIC_DEFAULT_RESTAURANT_LNG` | O | `31.05` (in code) | `31.0522` | `app/dashboard/menu/page.tsx` | Same. |
| `NODE_ENV` | O | `production` in compose | `production` | Next.js + `app/dashboard/settings/page.tsx` (`IS_DEV`) | Standard Next.js switch; gates a dev-only settings block. |

### 3.12 Flutter apps — compile-time (`--dart-define`)

These are **not** runtime env vars. They are baked into the binary at build time, so a
change means a **new build and a new store submission**.

| Variable | Req | Default | Example | Consumed by | What it does |
|---|---|---|---|---|---|
| `API_BASE_URL` (consumer) | O (set it) | `http://api.pindira.com/api` ⚠️ | `https://api.your-domain.com/api` | `consumer_app/lib/core/app_config.dart` | **Includes the `/api` suffix.** `AppConfig.validate()` throws in release builds if the scheme isn't `https`. ⚠️ The current *debug* default is cleartext `http://` to a public domain, which Android's `network_security_config.xml` blocks — so debug builds against the default fail. Flagged for the mobile team. |
| `API_BASE_URL` (driver) | O (set it) | `http://10.0.2.2:8000` | `https://api.your-domain.com` | `driver_app/lib/core/app_config.dart` | **No `/api` suffix** — the server root. `wsBaseUrl` is derived by swapping `http`→`ws`. ⚠️ Different convention from the consumer app; passing the consumer-style value silently produces broken URLs. |

### 3.13 Android release signing (`android/key.properties`)

A **properties file, not env vars**, at `consumer_app/android/key.properties` and
`driver_app/android/key.properties`. Gitignored — and it must stay that way.

| Key | Example | What it does |
|---|---|---|
| `storeFile` | `/home/you/keys/zvingo-consumer.jks` | Absolute path to the keystore. Keep it off the build machine's repo directory. |
| `storePassword` | `REPLACE_ME` | **SECRET.** Keystore password. |
| `keyAlias` | `consumer` | Alias inside the keystore. |
| `keyPassword` | `REPLACE_ME` | **SECRET.** Key password. |

Plus one build-time escape hatch, **consumer app only**:

| Flag | Example | What it does |
|---|---|---|
| `ZVINGO_ALLOW_DEBUG_RELEASE_SIGNING` (env) or `-PallowDebugReleaseSigning=true` (Gradle) | `true` | Allows a release-mode build **without** a real keystore, for local smoke tests. The artifact is debug-signed and **must never be uploaded to a store.** |

⚠️ The **driver app has no such guard**: `driver_app/android/app/build.gradle` silently falls
back to `signingConfigs.debug` when `key.properties` is absent, so a `flutter build appbundle
--release` on a fresh machine produces a debug-signed AAB that looks fine and is rejected at
upload. Match the consumer app's `gradle.taskGraph.whenReady` guard — flagged for the mobile
team.

---

## 4. Mobile app store release requirements

Two apps × two stores = four listings: **Zvingo** (consumer) and **Zvingo Driver**.

### 4.1 Google Play Console

| Item | Detail |
|---|---|
| **URL** | <https://play.google.com/console/signup> |
| **Cost** | **US$25 one-off**, no annual renewal. Non-refundable even if verification fails. |
| **Account type** | **Organization** strongly recommended (see the tester rule below) |
| **Personal account needs** | Government photo ID (current, legible, full legal name) + a credit card in the same name |
| **Organization account needs** | A **D-U-N-S number** (free, from Dun & Bradstreet, **1–5 business days**) + business documents + the ID above |
| **Verification time** | **2–5 business days** typically |

> 🔴 **The rule that will cost you two weeks.** Personal developer accounts created after
> 13 Nov 2023 must run a **closed test with at least 12 unique testers opted in for 14
> consecutive days** before they may apply for production access. Twelve distinct Google
> accounts, joined via your opt-in link, installed on **real devices** — emulators and
> duplicate accounts don't count. (It was 20 testers until Google reduced it to 12 on
> 11 Dec 2024.) **Organization accounts and accounts older than Nov 2023 are exempt.**
>
> **Register as an organization.** The D-U-N-S number takes a few days; the tester rule takes
> a fortnight *plus* the effort of recruiting 12 real people twice (once per app).

**Steps:** create the account and pay → complete identity/D-U-N-S verification → create the
app listing → upload a signed **AAB** (`flutter build appbundle --release --dart-define=...`)
→ complete the **Data safety** form → complete the **permissions declaration** → set up
store listing assets → closed test if required → apply for production.

**You must also:**

- **Enroll in Play App Signing** (effectively mandatory for new apps). Google holds the app
  signing key; your `key.properties` keystore becomes the *upload* key. **This is a relief,
  not a risk** — if you lose the upload key Google can reset it. If you opt out and lose your
  key, you can never update the app again. Opt in.
- Provide a **privacy policy URL** on a page you host. Both apps collect location and a phone
  number, so it is mandatory, not optional.
  **What exists today is not enough:** the driver app renders a two-paragraph `InfoScreen`
  at `/account/privacy` (`driver_app/lib/core/router.dart`), the consumer app has nothing,
  and **nothing is hosted on the web**. Stores check a URL, not a screen. Someone must write
  a real policy — covering precise location, the fact that the **driver's location is shared
  with the customer**, phone numbers, photos, payment metadata, retention and deletion — and
  host it at a stable URL. **This is a launch blocker nobody remembers until submission day.**
- Provide a **support email address**.

### 4.2 Apple Developer Program

| Item | Detail |
|---|---|
| **URL** | <https://developer.apple.com/programs/enroll/> |
| **Cost** | **US$99/year**, recurring |
| **Organization enrolment needs** | A **D-U-N-S number** (free, 1–5 business days), a legal entity, and signing authority for it |
| **Verification time** | **24 hours to 2 weeks**; allow **1–3 weeks** end to end for an organization, including a possible verification phone call |

Enrol as an **organization**, not an individual — an individual account publishes under your
personal name, and transferring later is painful.

**Then:**

1. In **Certificates, Identifiers & Profiles**, register the two App IDs. They must match
   the Xcode project exactly: **`com.zvingo.consumerApp`** and **`com.zvingo.driverApp`**.
2. Set `DEVELOPMENT_TEAM` in Xcode (currently unset; `CODE_SIGN_STYLE = Automatic`).
3. For push (when the client work lands): **Keys → + → Apple Push Notifications service
   (APNs)** → download the **`.p8`** file and upload it to Firebase (§2.3). You can download
   a `.p8` **exactly once** — store it like a password.
4. Create the two apps in **App Store Connect** and submit builds via Xcode or Transporter.

### 4.3 What both stores demand for a food-delivery app with location

#### Google Play — Data safety form

Declare, per app, what you collect, whether it is shared, whether it is encrypted in transit,
and whether users can request deletion. For Zvingo, truthfully:

| Data type | Consumer app | Driver app | Purpose |
|---|---|---|---|
| **Precise location** | Collected | Collected | App functionality (nearby restaurants, delivery address, live tracking) |
| **Approximate location** | Collected | Collected | Same |
| Phone number | Collected | Collected | Account management, OTP authentication |
| Name | Collected | Collected | Account management |
| Delivery address | Collected | — | App functionality |
| Purchase history | Collected | — | App functionality |
| Photos | Collected (menu/profile uploads) | Collected | App functionality |
| Approximate/precise location **shared with other users** | ⚠️ **Yes** — the driver's live location is streamed to the consumer | ⚠️ **Yes** | Delivery tracking |

That last row is the one people get wrong. The driver's location **is shared with a third
party** (the customer). Declaring it honestly is far cheaper than a policy strike.

Also declare: **data is encrypted in transit** (true — TLS everywhere, **except** the
BinProto UDP/TCP telemetry on ports 9090/9091, which is plaintext. Either put that behind
encryption or be careful how you answer, because answering "yes" while shipping plaintext GPS
is a false declaration).

> 🔴 **You must also offer account deletion, and Zvingo has none.** Google requires any app
> that lets users create an account to provide both an **in-app deletion path** and a
> **publicly reachable web URL** for requesting deletion, and to honour it. I searched the
> backend: there is **no `DELETE` route for a user account anywhere** (the only `@router.delete`
> handlers are for menu items and promotions in `catalog/router.py`). This needs a backend
> endpoint, a screen in both apps, and a web form before either Android app can be published.
> It is a launch blocker that is very easy to discover on the day you submit.

#### Apple — App Privacy ("nutrition label") + Privacy Manifest

1. **App Privacy** in App Store Connect — the same disclosure as Play's Data safety.
2. **Privacy manifest (`PrivacyInfo.xcprivacy`)** — since **1 May 2024** App Store Connect
   **rejects** apps that use a "required reason API" without declaring the reason in a
   privacy manifest.
   ⚠️ **Neither app has a `PrivacyInfo.xcprivacy` file** (I checked; there are none in the
   repo). Flutter plugins like `geolocator`, `connectivity_plus` and `hive` touch
   required-reason APIs (file timestamps, disk space, user defaults). One must be created for
   each app before the first iOS submission, and each third-party SDK must ship its own.
   Flagged for the mobile team.
3. **Usage-description strings** in `Info.plist`, which are shown verbatim in the permission
   dialog. Vague strings get rejected.
   - ✅ Consumer app has: *"Zvingo uses your location to show nearby restaurants and deliver
     orders to the right address."* Good — specific and user-benefit-framed.
   - 🔴 **Driver app has NO location usage string at all**, while depending on `geolocator`.
     **iOS terminates the process** the instant it requests location without one. The iOS
     driver app cannot work and cannot ship until this is added. Launch blocker.

### 4.4 Background location — the hard one

**Current state: Zvingo does not request background location anywhere.** No
`ACCESS_BACKGROUND_LOCATION` in either `AndroidManifest.xml`, no foreground service, no
`UIBackgroundModes: location` in either `Info.plist`.

**The product consequence:** driver tracking stops when the driver locks their phone or
switches apps — which is most of a delivery. Customers watch a driver freeze mid-route.

So this is a decision to take **now**, because adding it later means a fresh review cycle on
both stores:

#### If you add it on Android

1. Declare `ACCESS_BACKGROUND_LOCATION`, **and** run a **foreground service** with
   `foregroundServiceType="location"` and a persistent notification (required on Android 10+
   for sustained background location; Android 14 tightened this further).
2. Complete the **Play Console permissions declaration form**:
   - Explain why the core feature needs background location.
   - Confirm the feature is visible to the user.
   - **Submit a video of 30 seconds or less** showing how to log in and invoke the background
     location feature. If the feature isn't visible on screen, the video must demonstrate it
     working anyway.
3. Expect the reviewer to be sceptical. Google's own guidance lists *"delivery/service
   tracking (food, packages, a ride) **for users**"* as an acceptable case — note the
   phrasing is about the **consumer** watching a delivery, not the courier being tracked.
   **Your justification must be framed around the customer's experience**: "the customer
   cannot see where their food is unless the courier app reports location while backgrounded,
   which it does only during an active delivery the courier has accepted."
4. **Only request it while a delivery is active**, and stop the service the moment the
   delivery completes. Requesting it at app launch, or holding it between shifts, is the
   fastest route to rejection.
5. Google's location-permissions policy has updates effective **28 October 2026** —
   **UNVERIFIED** in detail from here; read
   <https://support.google.com/googleplay/android-developer/answer/9799150> before you submit.

#### If you add it on iOS

1. Add **`NSLocationAlwaysAndWhenInUseUsageDescription`** (and fix the missing
   `NSLocationWhenInUseUsageDescription`), plus `UIBackgroundModes: ["location"]`.
2. Apple requires the *purpose string* to be concrete. Something like: *"Zvingo Driver shares
   your location with the customer while you are delivering their order, so they can see
   their delivery arrive. Location is only used during an active delivery."*
3. Apple shows users a "Zvingo Driver has used your location N times in the background" alert.
   If your usage doesn't match your stated purpose, users revoke it and you get reviewed.

#### Reviewer justifications to have written down before you submit

| Permission | App | Justification |
|---|---|---|
| Fine location (foreground) | Consumer | Show nearby restaurants and pre-fill the delivery address |
| Fine location (foreground) | Driver | Match the driver to nearby orders and provide navigation |
| **Background location** | **Driver only** | Stream the courier's position to the paying customer during an **active, accepted delivery** so they can track their order in real time — the app's core advertised feature. Not collected outside an active delivery. |
| `POST_NOTIFICATIONS` | Both | Order status updates (consumer); new delivery offers (driver) |
| Camera / photo library | Consumer, merchant | Profile and menu photos |

**Never request background location in the consumer app.** There is no justification for it,
and asking will get the listing rejected.

### 4.5 Store assets you will need for each of the four listings

Not credentials, but they block submission just as hard:

- App icon (512×512 PNG for Play; 1024×1024 for App Store — the iOS `AppIcon.appiconset`
  assets already exist in both repos).
- Feature graphic 1024×500 (Play).
- Screenshots: at least 2 phone screenshots per store; App Store wants 6.7" and 6.5" sizes.
- Short (80 char) and full (4000 char) descriptions.
- **Privacy policy URL** — mandatory for both stores (see §4.1).
- Content rating questionnaire (Play) / age rating (App Store).
- Support email and, for Play, a physical contact address that is shown publicly.

---

## 5. Secrets management

### 5.1 Generating strong secrets

| Secret | Command | Length |
|---|---|---|
| `SECRET_KEY` (JWT) | `openssl rand -hex 32` | 64 hex chars / 256 bits |
| `MONGO_INITDB_ROOT_PASSWORD` | `openssl rand -hex 24` | 48 hex chars |
| `REDIS_PASSWORD` | `openssl rand -hex 24` | 48 hex chars |
| `METRICS_TOKEN` (optional) | `openssl rand -hex 16` | 32 hex chars |
| Android keystore passwords | `openssl rand -base64 24` | store in a password manager |

Generate them **on the droplet or on your own machine**, never in a chat window, a shared
terminal, a CI log, or anything a colleague can scroll back through. `config.py` explicitly
rejects `changethis`, `changeme`, `secret` and `generate-a-random-64-char-string-here` in
production — do not try to be clever and pick a memorable phrase, because a human-chosen JWT
key is a brute-forceable JWT key.

### 5.2 Where secrets live in production

**Never in git.** The repo tracks only `.env*.example` files with empty values. The filled-in
`.env` must never be committed. Verify before your first deploy:

```sh
grep -n "^\.env" .gitignore backend/.gitignore
git check-ignore -v .env backend/.env    # must print a matching ignore rule
```

**Recommended layout on the droplet:**

```sh
# The .env sits next to the compose file and is readable only by root
sudo install -o root -g root -m 600 /dev/null /opt/zvingo/.env
sudo nano /opt/zvingo/.env          # paste values
sudo chmod 600 /opt/zvingo/.env

# Firebase service account: same treatment
sudo chmod 600 /opt/zvingo/backend/firebase-credentials.json
```

Mode `600` matters: anything `644` is readable by every user and every other container that
bind-mounts the directory.

**The master copy belongs in a password manager** (1Password, Bitwarden — a shared vault the
business owns, not one person's personal account). The droplet is a *deployment* of the
secrets, not the *record* of them. If the droplet dies you must be able to rebuild without
re-registering with Paynow.

**What must never leave the server:**

`SECRET_KEY` · `PAYNOW_INTEGRATION_KEY` · `AFRICASTALKING_API_KEY` ·
`firebase-credentials.json` · `MONGO_INITDB_ROOT_PASSWORD` · `REDIS_PASSWORD` ·
Android keystores and their passwords · the Apple APNs `.p8`.

**What is safe to be public** (and will be, whether you like it or not): `NEXT_PUBLIC_*`
values, `API_BASE_URL`, `PAYNOW_INTEGRATION_ID` (the ID, **not** the key), and any map tile
API key — all of these ship inside a browser bundle or an app binary that anyone can unpack.
Design accordingly: restrict them at the provider by referrer/bundle ID rather than trying to
keep them hidden.

**Do not use build args for secrets.** `docker compose` build args are baked into image
layers and readable via `docker history`. The compose files correctly use build args only for
the non-secret `NEXT_PUBLIC_*` values — keep it that way.

### 5.3 Rotation schedule

| Secret | Rotate | How | Blast radius |
|---|---|---|---|
| `SECRET_KEY` | Every 6–12 months, or immediately on suspicion | Change the value, restart the backend | **Every user is logged out** — all existing JWTs become invalid. Do it at 03:00, not at lunchtime. |
| `PAYNOW_INTEGRATION_KEY` | On staff change or suspicion | Paynow dashboard → re-issue via [Email Key To Company Address] | Payments fail until the new value is deployed. Have the new value in hand *before* you rotate. |
| `AFRICASTALKING_API_KEY` | On staff change or suspicion | AT dashboard → generate new key | OTPs stop, so **nobody can log in**. Deploy the new key in the same maintenance window. |
| Firebase service account | Annually | Firebase → Service accounts → generate new key, then **delete the old one** | Push stops until redeployed. |
| Mongo / Redis passwords | Annually | Change inside the DB **and** in `.env` together | The app cannot connect between the two steps — plan a short outage. |
| Android keystore | **Never** | — | If you use Play App Signing, a lost *upload* key can be reset by Google. Without it, you can never update the app. Back the keystore up in two places. |
| TLS certificate | Automatic, every 90 days | certbot (see §2.8) | Site down if it lapses. |

### 5.4 If a key leaks

Act in this order. The goal is to make the leaked value worthless, then work out what it
touched.

1. **Revoke first, investigate second.** Re-issue the credential at the provider immediately.
   A leaked key that still works is an ongoing incident; a leaked key that is dead is a
   post-mortem.
2. **Deploy the replacement** and confirm the service works.
3. **If it was committed to git**, rotating is not enough — the value is in the history and
   in every clone and fork. Rotate at the provider *regardless*, then scrub history with
   `git filter-repo` and force-push, and treat every existing clone as compromised.
   (Note: this repo's swarm rules forbid agents running git; a human must do this.)
4. **Assess the damage per key:**
   - `SECRET_KEY` → attackers can forge a JWT for **any user, including admins**. Rotate,
     which invalidates every token, then audit recent admin actions and order-state changes.
   - `PAYNOW_INTEGRATION_KEY` → they can forge webhook hashes and mark orders paid.
     Reconcile every order against the Paynow transaction list for the exposure window.
   - `AFRICASTALKING_API_KEY` → they can drain your SMS credit and send messages **as you**
     from your registered sender ID. Check the balance and the outbound log; this one also
     has reputational and POTRAZ consequences.
   - `firebase-credentials.json` → they can push a notification to every installed app.
   - Mongo/Redis passwords → only exploitable if the ports are reachable. Confirm they are
     still unpublished (`docker compose ps`), then rotate.
5. **Tell the provider.** Paynow and Africa's Talking both have fraud/abuse contacts, and
   telling them early is the difference between a reversal and a loss.
6. **Write it down.** What leaked, how, when it was rotated, what you changed so it cannot
   recur.

---

## 6. Prioritised "do this first" checklist

Ordered by **lead time**, not by importance — the point is to start the slow things today so
they finish while you do the fast things.

### Week 0 — start today, because these take days or weeks of *waiting*

| # | Task | Lead time | Cost | Blocks |
|---|---|---|---|---|
| 1 | **Confirm/complete Zimbabwean company registration.** Paynow (for cards) and Africa's Talking (KYC) both need registry documents showing shareholders and directors. Everything below depends on it. | Weeks, if not already done | Varies | 2, 3 |
| 2 | **Apply for a Paynow merchant account** + register your settlement bank account. Create a `Zvingo Test` integration immediately so engineering can start on test mode while verification runs. | Days–weeks (**UNVERIFIED**) | Free to open | 🔴 Launch |
| 3 | **Open an Africa's Talking account**, submit KYC, create the live app, and **raise the sender ID request** (`ZVINGO`). This is the longest single pole. | **1–3 weeks** | US$35 sender ID | 🔴 Launch |
| 4 | **Request a D-U-N-S number** from Dun & Bradstreet (free). Needed for *both* an Apple organization enrolment *and* a Google Play organization account. One number covers both. | **1–5 business days** | Free | 5, 6 |
| 5 | **Enrol in the Apple Developer Program** as an organization. | **1–3 weeks** | US$99/yr | 🔴 iOS launch |
| 6 | **Create the Google Play Console account** as an **organization** (this is what exempts you from the 12-tester/14-day rule). | **2–5 business days** | US$25 one-off | 🔴 Android launch |
| 7 | **Decide the domain name and buy it.** Pick between `pindira.com` and `zvingo.com` — the repo currently contradicts itself — and buy `.co.zw` too if you want local trust. | Hours | ~US$5–25/yr | 🔴 Everything |

> If you *cannot* register Play as an organization, start the **12-tester closed test the day
> you have a signed build**, and recruit the testers now. Fourteen consecutive days with 12
> real devices is a project, not a formality — and you need it for **both** apps.

### Week 1 — fast, self-service, no waiting

| # | Task | Lead time | Cost |
|---|---|---|---|
| 8 | Point **DNS** at the (soon-to-exist) droplet; verify with `dig`. | 1 hour + propagation | Free |
| 9 | **Create the DigitalOcean droplet** (Ubuntu 24.04, 4 GB), SSH keys only, Cloud Firewall allowing 22/80/443 + 9090-udp/9091-tcp. **Turn on automated backups.** | 1 hour | US$24–29/mo |
| 10 | **Issue TLS certificates** with certbot, and **install the renewal cron job at the same time** (§2.8). Do not leave renewal for later-you. | 30 min | Free |
| 11 | **Create the Firebase project**, register all four app identifiers, download the service-account JSON to `backend/firebase-credentials.json`, `chmod 600`. | 30 min | Free |
| 12 | **Generate every secret** (`SECRET_KEY`, Mongo, Redis) and store the master copies in a shared password manager. Fill in `.env` on the droplet at mode `600`. | 30 min | Free |
| 13 | **Create both Android keystores** and their `key.properties` files. Back the `.jks` files up to two places — losing one is unrecoverable without Play App Signing. | 30 min | Free |
| 14 | **Write and host a real privacy policy** covering location collection, **sharing the driver's location with the customer**, phone numbers, photos, payment metadata, retention and deletion. Both stores need a **public URL** — the driver app's two-paragraph in-app screen does not count, and the consumer app has nothing. | Half a day | Free |
| 15 | **Sign up for CARTO** and obtain a basemap API key so your tiles aren't anonymous traffic (§2.4). | 30 min | Free |

### Week 1–2 — engineering work that must land before you can go live

These are **not in this document's file boundary**; they are requests for the other teams,
listed here so the owner can track them.

| # | Task | Owner | Blocks |
|---|---|---|---|
| 16 | 🔴 **Validate the Paynow webhook hash** (SHA-512 of all non-hash values + integration key, uppercase hex) in `backend/app/payment/router.py`. Until this ships, going live means anyone can mark orders paid. | Backend | 🔴 Launch |
| 17 | 🔴 **Add `NSLocationWhenInUseUsageDescription` to `driver_app/ios/Runner/Info.plist`.** The iOS driver app crashes without it. | Mobile | 🔴 iOS launch |
| 18 | 🔴 **Fix the geocoding endpoint**: add auth, a Redis cache, and a 1 req/sec throttle to `GET /api/location/geocode` — or move to a commercial geocoder. Today it is an open, uncached proxy that will get the server IP banned by OSMF. | Backend | 🔴 Launch |
| 19 | 🟠 **Add map attribution to all five unattributed `FlutterMap` widgets** (CARTO + OpenStreetMap). Licence breach as it stands. | Mobile | 🟠 Store review risk |
| 20 | 🟠 **Reconcile the domain** across `nginx/*.conf`, both `app_config.dart` defaults, and both `BUILD.md` files. A wrong hostname in a release build is a resubmission. | Mobile + DevOps | 🔴 Launch |
| 21 | 🔴 **Build account deletion.** Confirmed missing: no `DELETE` route for a user account exists in the backend. Google Play requires an in-app path *and* a public web URL for any app with account creation. Needs a backend endpoint, a screen in both apps, and a hosted web form. | Backend + Mobile | 🔴 Android launch |
| 22 | 🟠 **Build the FCM client**: add `firebase_core`/`firebase_messaging` to both apps, drop in `google-services.json` / `GoogleService-Info.plist`, register the token via `POST /api/auth/fcm-token` on every launch, declare `POST_NOTIFICATIONS` on Android 13+. Without this, push is dead however well the server is configured. | Mobile | 🟠 High |
| 23 | 🟠 **Add the release-signing guard to `driver_app/android/app/build.gradle`**, mirroring the consumer app, so a debug-signed AAB can't be produced by accident. | Mobile | 🟠 |
| 24 | 🟠 **Create `PrivacyInfo.xcprivacy` for both iOS apps.** App Store Connect rejects submissions without it. | Mobile | 🔴 iOS launch |
| 25 | 🟡 **Delete or fix `backend/app/sms/router.py`**, which reads the orphan `AT_USERNAME`/`AT_API_KEY` vars. | Backend | 🟡 |
| 26 | 🟡 **Decide on background location** (§4.4) and, if yes, build the foreground service + record the 30-second demo video before you submit. | Product + Mobile | 🟠 |
| 27 | 🟡 **Encrypt or firewall BinProto (9090/9091)** — driver GPS currently crosses the internet in plaintext, which also affects how you must answer the Play Data-safety encryption question. | Backend | 🟠 |

### Week 2–3 — integration testing

| # | Task |
|---|---|
| 28 | Run a **Paynow test-mode transaction** end to end: initiate → fake success → confirm the webhook fires → confirm the order moves to `OFFERED` and dispatch runs. |
| 29 | Run a **sandbox SMS** through Africa's Talking, then one **live SMS to your own +263 number** once the sender ID is approved. |
| 30 | Deploy with `ENVIRONMENT=production` and confirm the app **starts**. The validator will tell you exactly which credential is missing — treat a failed start as the checklist doing its job. |
| 31 | Build both release apps against the real domain, install on real devices, and complete one **real** order paying real money to yourselves. Nothing else proves the integration chain. |
| 32 | **Test a database restore** from backup. |

---

## 7. Cost summary

### One-off

| Item | Cost |
|---|---|
| Google Play Console registration | **US$25** |
| Africa's Talking sender ID setup | **US$35** |
| D-U-N-S number | Free |
| Firebase project | Free |
| TLS certificates | Free |
| **Total one-off** | **≈ US$60** |

### Annual

| Item | Cost |
|---|---|
| Apple Developer Program | **US$99/year** |
| Domain (`.com` and/or `.co.zw`) | **US$5–37/year** |
| **Total annual fixed** | **≈ US$104–136/year** |

### Monthly, at 1,000 orders/month (≈ US$10,000 processed)

| Item | Low | High | Note |
|---|---|---|---|
| DigitalOcean droplet(s) + backups | US$29 | US$45 | one 4 GB host, or the split 4 GB + 2 GB layout |
| Object-storage backups (Spaces) | US$0 | US$5 | strongly recommended |
| Africa's Talking SMS | US$10 | US$72 | per-SMS rate **UNVERIFIED**; ~500–1,200 messages |
| Paynow / mobile-money fees | US$140 | US$340 | ~1.4% + possible 2% IMTT — **UNVERIFIED**, confirm who bears IMTT |
| Firebase Cloud Messaging | US$0 | US$0 | free at any volume |
| CARTO basemap tiles | US$0 | US$0 | free under 5M tiles/month |
| Nominatim / geocoding | US$0 | US$25 | US$0 only if you keep the (non-compliant) free tier; budget for a commercial geocoder |
| **Monthly total** | **≈ US$180** | **≈ US$490** | |

**Headline: about US$60 one-off, US$104–136/year fixed, and US$180–490/month at 1,000
orders** — of which the overwhelming majority is payment processing that scales with revenue,
not fixed overhead. The fixed infrastructure bill is only about **US$35–50/month**.

**The critical path is time, not money.** The slowest items — Africa's Talking KYC + sender
ID (1–3 weeks), the Apple organization enrolment (1–3 weeks), and (if you end up on a
personal Play account) the 14-day closed test — all run in parallel and all start with
paperwork you can submit today.

---

## 8. Code-level problems found while writing this

Reported here for the other teams; none of these were changed by this document, which only
owns `docs/INTEGRATIONS_AND_CREDENTIALS.md`, the `.env.*.example` files, and the two
`BUILD.md` files.

| Severity | File | Problem |
|---|---|---|
| 🔴 Critical | `backend/app/payment/router.py` | The Paynow webhook does not validate Paynow's SHA-512 `hash`. Combined with a guessable 8-hex-char `paynow_reference`, anyone can mark orders paid. |
| 🔴 Critical | `driver_app/ios/Runner/Info.plist` | No `NSLocationWhenInUseUsageDescription` while depending on `geolocator`. iOS terminates the app on the first location request. |
| 🔴 High | `backend/app/location/router.py` + `service.py` | `GET /location/geocode` is unauthenticated, uncached and unthrottled, proxying to OSM Nominatim — a documented breach of the usage policy and a route to an IP ban that kills address search for everyone. |
| 🟠 High | 5 × `FlutterMap` call sites | Map tiles rendered with no CARTO/OpenStreetMap attribution. Licence breach in shipped apps. |
| 🟠 High | both apps | No FCM client at all: no `firebase_messaging` dependency, no `google-services.json`/`GoogleService-Info.plist`, nothing calls `POST /auth/fcm-token`. The server-side push code can never fire. |
| 🔴 High | backend + both apps | **No account-deletion capability at all** — no `DELETE` user route in the backend, no screen in either app, no web form. Google Play requires all three for any app with account creation. |
| 🔴 High | `driver_app/lib/core/router.dart`, `consumer_app` | Privacy policy is a two-paragraph in-app `InfoScreen` in the driver app and absent from the consumer app, with **no publicly hosted URL**. Both stores require a URL on the listing. |
| 🟠 High | both apps | No `PrivacyInfo.xcprivacy`; App Store Connect rejects submissions using required-reason APIs without one. |
| 🟠 High | `docker-compose.prod.yml`, `docker-compose.backend.yml` | BinProto 9090/udp + 9091/tcp are published to the internet in plaintext, carrying driver GPS. Affects the Play Data-safety "encrypted in transit" answer. |
| 🟠 Medium | `driver_app/android/app/build.gradle` | Silently falls back to debug signing when `key.properties` is absent; the consumer app correctly fails the build instead. Mirror the consumer app's `gradle.taskGraph.whenReady` guard. |
| 🟠 Medium | `consumer_app/lib/core/app_config.dart` | Debug default is `http://api.pindira.com/api` — cleartext to a public domain, which `network_security_config.xml` blocks. Debug builds against the default cannot reach the API. Should default to the emulator host. |
| 🟡 Medium | `consumer_app` vs `driver_app` `app_config.dart` | The two apps use **different `API_BASE_URL` conventions** (consumer includes `/api`, driver does not). Easy to get wrong in a release build; worth unifying. |
| 🟡 Medium | `backend/app/sms/router.py` | Reads `AT_USERNAME`/`AT_API_KEY` via `os.getenv` — names absent from `config.py` and every `.env.example`. `POST /sms/send` mocks forever. Delete it or point it at `settings`. |
| 🟡 Low | `backend/app/config.py`, `main.py` | `API_V1_STR = "/api/v1"` is dead weight — it is used only for the OpenAPI schema URL and no router is mounted under it. Its name strongly implies a versioned API that does not exist, and it misled this audit. Either delete it or actually version the API. |
| 🟡 Medium | `backend/app/config.py` | `DEV_DEFAULT_BASE_LAT/LNG` default to Mountain View, California (37.42, -122.08). Should be Harare (-17.8292, 31.0522). Also `DEV_DEFAULT_OFFSET_MILES` uses miles in a metric country. |
| 🟡 Medium | repo-wide | The domain is inconsistent: `pindira.com` in nginx/compose, `zvingo.com` in both `BUILD.md` files, `api.pindira.com` in the consumer app default. |
| 🟡 Low | `SYSTEM_DOCUMENTATION.md` §18 | Stale. It lists `POST /upload/image` as unauthenticated (it now requires `get_current_user`) and CORS as `["*"]` (now driven by `CORS_ORIGINS` with a production guard). Several §18 "Production Blockers" are already fixed. |

---

## Sources

Verified while writing this document (September 2026):

- [Paynow — Generating Integration Keys](https://developers.paynow.co.zw/docs/paynow/integration_generation/)
- [Paynow — Test Mode](https://developers.paynow.co.zw/docs/paynow/test_mode/)
- [Paynow — Validating a hash on an inbound message](https://developers.paynow.co.zw/docs/paynow/validating_hash/)
- [Paynow — Merchant FAQ](https://www.paynow.co.zw/home/merchanttutorial) · [Sign up](https://www.paynow.co.zw/Customer/Register) · [Fees](https://www.paynow.co.zw/Home/Fees)
- [Africa's Talking — Pricing](https://africastalking.com/pricing) · [Terms of Service](https://africastalking.com/terms_of_service) · [Help Centre: API keys](https://help.africastalking.com/en/articles/1361037-how-do-i-generate-an-api-key) · [Sandbox](https://help.africastalking.com/en/articles/1170660-how-do-i-get-started-on-the-africa-s-talking-sandbox)
- [Nominatim Usage Policy (OSMF)](https://operations.osmfoundation.org/policies/nominatim/)
- [CARTO Basemaps Terms and Conditions](https://carto.com/legal/basemap-terms/) · [CARTO Basemaps FAQ](https://docs.carto.com/faqs/carto-basemaps)
- [Firebase Pricing](https://firebase.google.com/pricing)
- [Google Play — Get started with Play Console](https://support.google.com/googleplay/android-developer/answer/6112435) · [Background location permissions](https://support.google.com/googleplay/android-developer/answer/9799150) · [Declare permissions](https://support.google.com/googleplay/android-developer/answer/9214102) · [The 12-tester requirement](https://support.google.com/googleplay/android-developer/community-guide/255621488/everything-about-the-12-testers-requirement)
- [Apple Developer Program enrolment](https://developer.apple.com/help/account/membership/program-enrollment/)
- [DigitalOcean Droplet pricing](https://www.digitalocean.com/pricing/droplets) · [Droplet pricing docs](https://docs.digitalocean.com/products/droplets/details/pricing/)
- [Name.co.zw pricing (.co.zw domains)](https://www.name.co.zw/pricing)
- [Clickatell — Zimbabwe SMS regulations](https://www.clickatell.com/sms-country-regulations/zimbabwe/)
