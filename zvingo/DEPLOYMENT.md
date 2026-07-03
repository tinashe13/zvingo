# Zvingo — Production Deployment Guide

Deploys the FastAPI backend, merchant dashboard, MongoDB, Redis, and an
nginx TLS-terminating reverse proxy via `docker-compose.prod.yml`.

Keep using `docker-compose.yml` (no `-f` flag) for local development — it is
unchanged and still mounts source with `--reload`.

## 1. Provision a server

- Any Linux host (Ubuntu 22.04+ recommended) with Docker Engine + the
  Docker Compose plugin installed.
- Open inbound ports in your firewall/security group:
  - `80` (HTTP → HTTPS redirect + Let's Encrypt renewals)
  - `443` (HTTPS)
  - `9090/udp` and `9091/tcp` (BinProto telemetry — the driver app connects
    to these directly; they bypass nginx by design)
- Do **not** open 27017 (Mongo) or 6379 (Redis) — the prod compose file does
  not publish them to the host at all.

```bash
git clone <your-repo-url>
cd Doordash/zvingo
```

## 2. DNS

Point an A record (and AAAA if you have IPv6) for your domain, e.g.
`zvingo.example.com`, at the server's public IP. Wait for it to resolve
before requesting certificates.

Then replace both `server_name zvingo.example.com;` lines in
`nginx/nginx.prod.conf` with your domain.

## 3. Configure environment

```bash
cp .env.production.example .env
```

Fill in every value. Generate secrets:

```bash
openssl rand -hex 32   # SECRET_KEY
openssl rand -hex 24   # MONGO_INITDB_ROOT_PASSWORD
openssl rand -hex 24   # REDIS_PASSWORD
```

The compose file uses `${VAR:?}` for all secrets, so startup fails
immediately with a clear message if anything required is missing.
Never commit the filled-in `.env`.

Also place your Firebase service-account JSON at
`backend/firebase-credentials.json` (it is baked into the backend image).

## 4. Obtain TLS certificates

nginx expects `fullchain.pem` and `privkey.pem` in `nginx/certs/`.

Initial issuance (before the stack is running, port 80 must be free):

```bash
sudo certbot certonly --standalone -d zvingo.example.com
mkdir -p nginx/certs
sudo cp /etc/letsencrypt/live/zvingo.example.com/fullchain.pem nginx/certs/
sudo cp /etc/letsencrypt/live/zvingo.example.com/privkey.pem  nginx/certs/
```

Renewals while the stack is running: nginx serves
`/.well-known/acme-challenge/` from the shared `certbot_webroot` volume, so
you can renew with the webroot plugin, e.g. via cron:

```bash
docker run --rm \
  -v zvingo_certbot_webroot:/var/www/certbot \
  -v /etc/letsencrypt:/etc/letsencrypt \
  certbot/certbot renew --webroot -w /var/www/certbot
# then copy the renewed certs into nginx/certs/ and reload:
docker compose -f docker-compose.prod.yml exec nginx nginx -s reload
```

(Self-signed for a staging box: `openssl req -x509 -nodes -days 365
-newkey rsa:2048 -keyout nginx/certs/privkey.pem -out nginx/certs/fullchain.pem`.)

## 5. Build and start

```bash
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps        # all services healthy?
curl -s https://zvingo.example.com/api/health        # backend health via nginx
```

## 6. Database migrations

There are **no migrations to run**: the backend uses MongoDB (schemaless) and
initializes its own collections/state at startup (`app/db/session.py:init_db`,
called from the FastAPI lifespan). The `backend/alembic/` directory exists but
contains no configured environment or migration scripts. If Alembic migrations
are added later, run them with:

```bash
docker compose -f docker-compose.prod.yml exec backend alembic upgrade head
```

## 7. Backups (Mongo volume)

Data lives in the named volumes `mongo_data` (database), `redis_data`, and
`backend_uploads` (uploaded images). Dump Mongo with authentication:

```bash
docker compose -f docker-compose.prod.yml exec mongo sh -c \
  'mongodump -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
   --authenticationDatabase admin --archive' > backup-$(date +%F).archive
```

Restore:

```bash
docker compose -f docker-compose.prod.yml exec -T mongo sh -c \
  'mongorestore -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
   --authenticationDatabase admin --archive' < backup-2026-07-02.archive
```

Schedule the dump via cron and copy archives off the server. Back up the
`backend_uploads` volume too (`docker run --rm -v zvingo_backend_uploads:/data
-v $(pwd):/backup alpine tar czf /backup/uploads.tgz /data`).

## 8. Logs and operations

```bash
docker compose -f docker-compose.prod.yml logs -f            # everything
docker compose -f docker-compose.prod.yml logs -f backend    # one service
docker compose -f docker-compose.prod.yml logs --tail=200 nginx
docker compose -f docker-compose.prod.yml restart backend    # restart a service
docker compose -f docker-compose.prod.yml up -d --build backend  # deploy new code
docker compose -f docker-compose.prod.yml down               # stop (volumes kept)
```

## Routing reference

| Public path            | Destination                       | Notes                          |
|------------------------|-----------------------------------|--------------------------------|
| `/api/*`               | backend:8000 (prefix stripped)    | REST API                       |
| `/api/notification/*`  | backend:8000 (prefix stripped)    | SSE — proxy buffering off      |
| `/api/location/driver/*` | backend:8000 (prefix stripped)  | SSE — proxy buffering off      |
| `/ws/*`                | backend:8000                      | WebSocket (driver dispatch)    |
| `/static/*`            | backend:8000                      | Uploaded images                |
| `/*` (everything else) | merchant-dashboard:3000           | Dashboard UI                   |
| `:9090/udp`, `:9091`   | backend directly (host-published) | BinProto telemetry, no nginx   |
