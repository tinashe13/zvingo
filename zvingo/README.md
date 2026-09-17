# Zvingo

On-demand food delivery for the Zimbabwe market: a FastAPI backend, two Flutter
apps (consumer and driver), and a Next.js merchant dashboard.

---

## Run it locally

Everything runs on Docker. From the `zvingo/` directory:

### 1. Create the backend environment file

The backend reads `./backend/.env`, which is gitignored and does not exist on a
fresh clone. Copy the example and give it a real signing key:

```bash
cp backend/.env.example backend/.env
python3 -c "import secrets; print('SECRET_KEY=' + secrets.token_urlsafe(48))"
```

Paste that `SECRET_KEY` line into `backend/.env`, replacing the placeholder.
**The app refuses to start with a weak one** — it must be at least 32
characters with at least 12 distinct characters, and must not be a known
placeholder like `changethis`. That check exists because the default was
shipping into production; it is not decoration.

Leave `PAYMENT_MOCK_MODE=true` and `SMS_MOCK_MODE=true` for local work. Both are
refused in production, so no mock can reach real money or real SMS.

### 2. Start the stack

```bash
docker compose up -d
```

| Service | URL | Notes |
|---|---|---|
| Backend API | http://localhost:8000 | direct |
| Nginx | http://localhost | proxies the API under `/api` |
| MongoDB | localhost:27017 | volume `mongo_data` |
| Redis | localhost:6379 | volume `redis_data` |
| SMS mock | http://localhost:8001 | dev only; prints the messages |

Check it came up:

```bash
curl localhost:8000/ready
# {"status":"ready","checks":{"mongodb":"ok","redis":"ok"}}
```

### 3. Seed demo data

```bash
python3 backend/scripts/seed_demo.py
```

Creates three Harare restaurants with menus, three accounts and a couple of
orders. Standard library only, talks to the API over HTTP, and is safe to
re-run — accounts are signed in rather than re-registered.

| Role | Phone | Password |
|---|---|---|
| Merchant | +263771234567 | `ZvingoDev2026!` |
| Consumer | +263772223333 | `ZvingoDev2026!` |
| Driver | +263773334444 | `ZvingoDev2026!` |

### 4. Merchant dashboard

Not in the default compose file. For development, run it directly:

```bash
cd merchant-dashboard
npm install
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000 npm run dev
# http://localhost:3000
```

For a container build, use `docker-compose.dashboard.yml`, which needs
`NEXT_PUBLIC_API_URL` set — the API host is baked in at build time.

### 5. Flutter apps

```bash
cd consumer_app
flutter pub get
flutter run --dart-define=ZV_ENV=local-android   # Android emulator
flutter run --dart-define=ZV_ENV=local           # iOS simulator / desktop

cd driver_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`ZV_ENV` is a consumer-app shorthand; both apps also accept an explicit
`--dart-define=API_BASE_URL=...`. Note the consumer's local default points at
nginx (`http://127.0.0.1:8000/api`) while the driver talks to the backend
directly — they are not interchangeable.

The API host is **compiled into the binary**, so it must be set at build time
for a real device or a store build. See each app's `BUILD.md`. The driver app
also reads `WS_BASE_URL` and `ORS_API_KEY`.

---

## Watch out for

**Login is `POST /auth/token`, OAuth2 form-encoded** — not JSON at
`/auth/login`. `username` is the phone number.

**Routers mount at the root**, not under `/api/v1`. `settings.API_V1_STR` only
names the OpenAPI schema URL. Nginx adds the public `/api` prefix and strips it
again before proxying, so the same endpoint is `/api/auth/token` from a client
and `/auth/token` inside the container.

**Locations are not one shape.** A restaurant takes flat `lat`/`lng`; an order
dropoff takes GeoJSON, `{"type":"Point","coordinates":[lng, lat]}` — longitude
first.

**`Order.merchant_id` holds a restaurant id, not a merchant user id.** Comparing
it to a user id matches nothing and fails silently. Use
`app.auth.authorization.owning_merchant_id()`.

**`Order.total_amount` is the basket subtotal**, before fees, tip and discount.
The amount to charge comes from `fee_calculator.breakdown_for_order()`. Reading
`total_amount` as a grand total undercharges by the whole delivery fee.

**Auth endpoints are rate-limited per IP.** Hitting register in a loop returns
429 for an hour. To clear it locally:

```bash
redis-cli --scan --pattern 'rate_limit:*' | xargs redis-cli del
```

---

## Tests

```bash
cd backend && poetry run pytest -q          # 823 tests
cd consumer_app && flutter analyze && flutter test
cd driver_app   && flutter analyze && flutter test
cd merchant-dashboard && npx tsc --noEmit && npm run lint && npm run build
```

The backend suite uses Redis database 15 and clears the app's key prefixes
before each test, so it does not fight a dev server on database 0.

---

## Documentation

| Document | What it covers |
|---|---|
| [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) | Normative cross-surface spec: colour, type, spacing, motion, component contracts, navigation rules, and the checklist a screen must pass. |
| [`docs/INTEGRATIONS_AND_CREDENTIALS.md`](docs/INTEGRATIONS_AND_CREDENTIALS.md) | Every external account and credential: signup URLs, documents demanded, lead times, costs, env vars, how to test each. |
| [`docs/OPEN_ITEMS.md`](docs/OPEN_ITEMS.md) | What is still open: decisions needed, launch blockers, endpoints the clients are built against. |
| [`DEPLOYMENT.md`](DEPLOYMENT.md) | Production deployment. |
| [`SYSTEM_DOCUMENTATION.md`](SYSTEM_DOCUMENTATION.md) | Architecture. Its §18 tech-debt table is stale — see `docs/OPEN_ITEMS.md`. |
