# syntax=docker/dockerfile:1
# Production image for the Zvingo merchant dashboard (Next.js standalone output).

# ---- Stage 1: install dependencies ----
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---- Stage 2: build ----
FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build-time configuration (see .env.example):
# - NEXT_PUBLIC_* vars are inlined into the client bundle at build time.
# - API_PROXY_URL is baked into the '/api/*' rewrite (next.config.ts).
ARG NEXT_PUBLIC_API_URL
ARG API_PROXY_URL
ARG NEXT_PUBLIC_DEFAULT_RESTAURANT_LAT
ARG NEXT_PUBLIC_DEFAULT_RESTAURANT_LNG
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL \
    API_PROXY_URL=$API_PROXY_URL \
    NEXT_PUBLIC_DEFAULT_RESTAURANT_LAT=$NEXT_PUBLIC_DEFAULT_RESTAURANT_LAT \
    NEXT_PUBLIC_DEFAULT_RESTAURANT_LNG=$NEXT_PUBLIC_DEFAULT_RESTAURANT_LNG \
    NEXT_TELEMETRY_DISABLED=1

# Cap the V8 heap for `next build`. Left uncapped, Node sizes its heap from
# total host RAM and a small droplet gets OOM-killed mid-build (the build
# dies with "signal: killed" rather than a JS error). Capping makes Node
# collect garbage instead. Raise it on a bigger box for a faster build.
ARG NODE_BUILD_MEMORY_MB=1536
ENV NODE_OPTIONS=--max-old-space-size=$NODE_BUILD_MEMORY_MB

RUN npm run build

# ---- Stage 3: production runner ----
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# Next.js standalone output: minimal server + traced node_modules
COPY --from=builder --chown=node:node /app/.next/standalone ./
COPY --from=builder --chown=node:node /app/.next/static ./.next/static
COPY --from=builder --chown=node:node /app/public ./public

# Run as the non-root 'node' user provided by the base image
USER node

EXPOSE 3000

CMD ["node", "server.js"]
