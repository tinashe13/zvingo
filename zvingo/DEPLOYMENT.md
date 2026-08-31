# Zvingo — Production Deployment Guide

Deploys the FastAPI backend, merchant dashboard, MongoDB, Redis, and an
nginx TLS-terminating reverse proxy via `docker-compose.prod.yml`.

Keep using `docker-compose.yml` (no `-f` flag) for local development — it is
unchanged and still mounts source with `--reload`.

## 1. Provision a server

Any Linux host (Ubuntu 24.04 LTS recommended) with Docker Engine and the
Docker Compose plugin.

**2 GB RAM minimum, 4 GB recommended.** A 512 MB droplet cannot build *or* run
this stack — MongoDB alone will not fit. See "Build runs out of memory" below
for the sizing table and what to do if you are already on a small box.

Open inbound ports in your firewall/security group:

  - `80` (HTTP → HTTPS redirect + Let's Encrypt renewals)
  - `443` (HTTPS)
  - `9090/udp` and `9091/tcp` (BinProto telemetry — the driver app connects
    to these directly; they bypass nginx by design)

Do **not** open 27017 (Mongo) or 6379 (Redis) — the prod compose file does not
publish them to the host at all.

### DigitalOcean droplet (SSH-key auth)

Create the droplet with **Ubuntu 24.04**, Basic / 2 vCPU / 2 GB, and choose
**SSH Key** for authentication. Generate one first if you need to:

```bash
ssh-keygen -t ed25519 -C "zvingo-deploy"   # then paste ~/.ssh/id_ed25519.pub into DO
ssh -i ~/.ssh/id_ed25519 root@<DROPLET_IP>
```

Create an unprivileged user and copy the key to it:

```bash
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy
```

Verify `ssh -i ~/.ssh/id_ed25519 deploy@<DROPLET_IP>` works **in a second
terminal** before disabling root/password login — a bad sshd config otherwise
locks you out:

```bash
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/'  /etc/ssh/sshd_config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Firewall, Docker, and the clone:

```bash
sudo ufw allow OpenSSH && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw allow 9090/udp && sudo ufw allow 9091/tcp
sudo ufw --force enable

curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker deploy && newgrp docker

git clone <your-repo-url> && cd zvingo/zvingo
```

> `ufw` does not filter Docker-published ports — Docker inserts its own
> iptables rules ahead of it. Add a DigitalOcean **Cloud Firewall** with the
> same five rules for protection that actually applies to the containers.

For a private repo use a read-only **deploy key** on the droplet rather than
forwarding your personal key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/gh_deploy -N ""
cat ~/.ssh/gh_deploy.pub   # GitHub → repo → Settings → Deploy keys
printf 'Host github.com
  IdentityFile ~/.ssh/gh_deploy
  IdentitiesOnly yes
' >> ~/.ssh/config
```

## 2. DNS

Point an A record (and AAAA if you have IPv6) for your domain, e.g.
`pindira.com`, at the server's public IP. Wait for it to resolve
before requesting certificates.

Then replace both `server_name pindira.com;` lines in
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
Never commit the filled-in `.env` (`chmod 600 .env`).

`NEXT_PUBLIC_API_URL` and `API_PROXY_URL` are **build-time** values: Next.js
inlines them into the client bundle and resolves the `/api/*` rewrite when the
image is built. Changing either needs
`docker compose -f docker-compose.prod.yml up -d --build merchant-dashboard`,
not just a restart.

Also place your Firebase service-account JSON at
`backend/firebase-credentials.json` (it is baked into the backend image).

## 4. Obtain TLS certificates

nginx expects `fullchain.pem` and `privkey.pem` in `nginx/certs/`.

Initial issuance (before the stack is running, port 80 must be free):

```bash
sudo certbot certonly --standalone -d pindira.com
mkdir -p nginx/certs
sudo cp /etc/letsencrypt/live/pindira.com/fullchain.pem nginx/certs/
sudo cp /etc/letsencrypt/live/pindira.com/privkey.pem  nginx/certs/
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
curl -s https://pindira.com/api/health        # backend health via nginx
```

## 6. Create the first admin

Nothing can mint an admin through the API — `/auth/register` will not grant the
role. Register normally in the app, then promote that account once:

```bash
docker compose -f docker-compose.prod.yml exec mongo mongosh   -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD"   --authenticationDatabase admin zvingo   --eval 'db.users.updateOne({phone:"+263..."},{$set:{role:"admin"}})'
```

Manage every later role change through `PATCH /api/admin/users/{id}`.

## 7. Database migrations

There are **no migrations to run**: the backend uses MongoDB (schemaless) and
initializes its own collections/state at startup (`app/db/session.py:init_db`,
called from the FastAPI lifespan). The `backend/alembic/` directory exists but
contains no configured environment or migration scripts. If Alembic migrations
are added later, run them with:

```bash
docker compose -f docker-compose.prod.yml exec backend alembic upgrade head
```

## 8. Backups (Mongo volume)

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

## 9. Logs and operations

```bash
docker compose -f docker-compose.prod.yml logs -f            # everything
docker compose -f docker-compose.prod.yml logs -f backend    # one service
docker compose -f docker-compose.prod.yml logs --tail=200 nginx
docker compose -f docker-compose.prod.yml restart backend    # restart a service
docker compose -f docker-compose.prod.yml up -d --build backend  # deploy new code
docker compose -f docker-compose.prod.yml down               # stop (volumes kept)
```

## Split deployment (backend and dashboard on separate hosts)

`docker-compose.prod.yml` runs everything on one host. To separate them, use
the two split files instead — each host builds only its own image, so the
backend host never builds Node at all.

| Host | Compose file | Runs | Domain |
|------|--------------|------|--------|
| A | `docker-compose.backend.yml` | backend, mongo, redis, nginx | `api.<domain>` |
| B | `docker-compose.dashboard.yml` | dashboard, nginx | `app.<domain>` |

**Host A — backend**

```bash
cp .env.backend.example .env && nano .env && chmod 600 .env
sed -i 's/api\.zvingo\.example\.com/api.your-domain.com/g' nginx/nginx.api.conf
sudo certbot certonly --standalone -d api.your-domain.com
mkdir -p nginx/certs && sudo cp /etc/letsencrypt/live/api.your-domain.com/{fullchain,privkey}.pem nginx/certs/
docker compose -f docker-compose.backend.yml up -d --build
```

**Host B — dashboard**

```bash
cp .env.dashboard.example .env && nano .env && chmod 600 .env
sed -i 's/app\.zvingo\.example\.com/app.your-domain.com/g' nginx/nginx.dashboard.conf
sudo certbot certonly --standalone -d app.your-domain.com
mkdir -p nginx/certs && sudo cp /etc/letsencrypt/live/app.your-domain.com/{fullchain,privkey}.pem nginx/certs/
docker compose -f docker-compose.dashboard.yml up -d --build
```

Four things differ from the single-host setup:

1. **CORS becomes load-bearing.** Combined, the dashboard and API share an
   origin and the browser never preflights. Split, they do not — set
   `CORS_ORIGINS=https://app.your-domain.com` on host A. The backend sends
   credentials, so `"*"` is not a legal value; it must be an explicit list.
2. **Uploads follow the API host.** `UPLOAD_BASE_URL` must be
   `https://api.your-domain.com`, which is the host actually serving
   `/static/uploads/`.
3. **The dashboard calls the API directly.** `nginx.dashboard.conf`
   deliberately does not proxy `/api`; the browser uses the
   `NEXT_PUBLIC_API_URL` baked into the bundle.
4. **BinProto stays on host A.** The driver app keeps using
   `api.your-domain.com:9090/udp` and `:9091` — those bypass nginx by design.

The `/api` prefix is kept on the API host even though it is a dedicated
subdomain, so existing mobile builds (which target `https://api.<domain>/api`)
need no change.

## Build runs out of memory

A build that dies with `failed to execute bake: signal: killed` was terminated
by the kernel's OOM reaper, not by a code error.

### Check the droplet size first

| Droplet | Verdict |
|---------|---------|
| 512 MB (`s-1vcpu-512mb`) | **Too small.** Will not build, and will not run. |
| 1 GB | Builds only with swap; MongoDB will thrash under load. |
| 2 GB | Minimum for the backend stack. |
| 4 GB | Comfortable, and builds the dashboard without swap. |

512 MB cannot run this stack even if you get the image built elsewhere.
MongoDB 7's WiredTiger cache alone has a 256 MB floor, and `mongod` plus
Redis, uvicorn, and nginx will not fit in what remains. Resize the droplet to
at least 2 GB (Power off → Resize → pick a plan; a resize that only changes
RAM/CPU keeps the disk and needs no rebuild).

### Then reduce peak memory

Swap is worth adding on any droplet under 4 GB, and is *required* below 2 GB:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

The backend Dockerfile pins `POETRY_INSTALLER_MAX_WORKERS=1`, which is the
main lever for `poetry install` — the default of `min(cpu + 4, 10)` unpacks
that many wheels concurrently, and `cryptography`, `grpcio`, and `protobuf`
are each large.

If the droplet is genuinely too small to build on, build the image somewhere
with more RAM and pull it instead of building on the server:

```bash
# on a build machine or in CI
docker build -t ghcr.io/<you>/zvingo-backend:latest ./backend
docker push ghcr.io/<you>/zvingo-backend:latest

# on the droplet — swap `build:` for `image:` in docker-compose.backend.yml
docker compose -f docker-compose.backend.yml pull && docker compose -f docker-compose.backend.yml up -d
```

That removes the build entirely, but not the runtime requirement above.

### Other levers

Any one of these also helps:

```bash
# 1. Add swap (do this regardless — it is the cheapest insurance)
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h

# 2. Build one service at a time instead of in parallel
docker compose -f docker-compose.prod.yml build backend
docker compose -f docker-compose.prod.yml build merchant-dashboard
docker compose -f docker-compose.prod.yml up -d

# 3. Lower the V8 heap cap for the dashboard build
NODE_BUILD_MEMORY_MB=1024 docker compose -f docker-compose.prod.yml build merchant-dashboard
```

Splitting the hosts (above) removes the Node build from the backend host
entirely, which is the single biggest saving if you are deploying both.

On a memory-constrained box you can also cap MongoDB's cache by adding
`command: mongod --wiredTigerCacheSizeGB 0.25` to the `mongo` service. Do not
carry that setting onto a larger host — it would throttle a database that has
room to cache more.

If a killed build left partial layers behind, `docker builder prune -f`
reclaims the space before you retry.

## Routing reference

| Public path                        | Destination                       | Notes                            |
|------------------------------------|-----------------------------------|----------------------------------|
| `/api/*`                           | backend:8000 (prefix stripped)    | REST API, including `/api/admin/*` |
| `/api/notification/*`              | backend:8000 (prefix stripped)    | SSE — proxy buffering off        |
| `/api/location/driver/*`           | backend:8000 (prefix stripped)    | SSE — proxy buffering off        |
| `/api/chat/orders/{id}/stream`     | backend:8000 (prefix stripped)    | SSE — proxy buffering off        |
| `/api/metrics`                     | **denied**                        | Prometheus; scrape internally    |
| `/ws/driver/{id}`                  | backend:8000                      | WebSocket — driver dispatch      |
| `/ws/orders/{id}/track`            | backend:8000                      | WebSocket — consumer tracking    |
| `/static/*`                        | backend:8000                      | Uploaded images                  |
| `/*` (everything else)             | merchant-dashboard:3000           | Dashboard UI                     |
| `:9090/udp`, `:9091`               | backend directly (host-published) | BinProto telemetry, no nginx     |

`/api/metrics` returns 403 from the public internet on purpose — it reports
order, payment, and dispatch volumes. Scrape it from inside the compose
network at `http://backend:8000/metrics`, and set `METRICS_TOKEN` in `.env` if
you want bearer auth on top.

### Why the backend runs a single uvicorn worker

The FastAPI lifespan binds the BinProto UDP/TCP listeners on fixed ports and
starts singleton background loops (dispatch retry, scheduled-order release,
alert monitor). A second worker cannot bind those ports and would run every
loop again, duplicating driver offers. Scale out with additional backend
containers behind nginx — never with `--workers`.
