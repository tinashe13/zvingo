/**
 * Zvingo merchant dashboard data layer.
 *
 * One fetch wrapper, one error type, one place that knows about auth. Pages
 * should never call `fetch` directly.
 *
 * Base URL resolution (first non-empty wins):
 *   1. NEXT_PUBLIC_API_BASE_URL  — explicit public gateway, e.g. https://host/api
 *   2. NEXT_PUBLIC_API_URL       — legacy name, kept for existing deployments
 *   3. '/api'                    — same-origin path rewritten by next.config.ts
 *                                  to the local Nginx gateway (dev default)
 *
 * The gateway strips the `/api` prefix, so paths here are backend-relative:
 * `/auth/me`, `/orders/merchant/{id}`, `/catalog/restaurants`, …
 */

const RAW_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL || process.env.NEXT_PUBLIC_API_URL || "";

/** Browser-facing base URL for API + SSE calls. */
export const API_BASE = (RAW_BASE || "/api").replace(/\/+$/, "");

/**
 * Base URL for direct multipart uploads, which bypass the same-origin `/api`
 * rewrite in dev. Shares the public base; falls back to the local backend.
 */
export const UPLOAD_API_URL = RAW_BASE || "http://localhost:8000";

export const TOKEN_STORAGE_KEY = "zvingo_token";
export const USER_STORAGE_KEY = "zvingo_user";
export const REFRESH_TOKEN_STORAGE_KEY = "zvingo_refresh_token";
export const TOKEN_EXPIRY_STORAGE_KEY = "zvingo_token_expires_at";

const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_RETRIES = 2;
const RETRY_BASE_DELAY_MS = 300;
const RETRYABLE_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504]);

/* -------------------------------------------------------------------------- */
/* Errors                                                                     */
/* -------------------------------------------------------------------------- */

export type ApiErrorKind =
  | "network"      // the request never reached the server
  | "timeout"      // the server did not answer in time
  | "auth"         // 401 — session expired
  | "forbidden"    // 403 — signed in, not allowed
  | "not_found"    // 404
  | "validation"   // 400 / 409 / 422 — the submitted data is wrong
  | "rate_limited" // 429
  | "server"       // 5xx
  | "unknown";

/**
 * Every failure out of this module is an `ApiError`. `message` is always safe
 * to render to a non-technical user (DESIGN_SYSTEM §5.5: never surface a raw
 * exception or HTTP status). `detail` keeps the raw payload for logging.
 */
export class ApiError extends Error {
  readonly name = "ApiError";
  readonly kind: ApiErrorKind;
  readonly status: number;
  readonly detail: unknown;
  readonly path: string;
  /** True when retrying the exact same request could plausibly succeed. */
  readonly retryable: boolean;

  constructor(init: {
    kind: ApiErrorKind;
    status: number;
    message: string;
    detail?: unknown;
    path?: string;
    retryable?: boolean;
  }) {
    super(init.message);
    this.kind = init.kind;
    this.status = init.status;
    this.detail = init.detail;
    this.path = init.path ?? "";
    this.retryable =
      init.retryable ?? (init.kind === "network" || init.kind === "timeout" || init.kind === "server");
  }
}

export function isApiError(error: unknown): error is ApiError {
  return error instanceof ApiError;
}

/** Plain-language message for anything that can be thrown, including non-Errors. */
export function errorMessage(error: unknown, fallback = "Something went wrong. Please try again."): string {
  if (isApiError(error)) return error.message;
  if (error instanceof Error && error.message) return error.message;
  return fallback;
}

const FRIENDLY_BY_STATUS: Record<number, string> = {
  400: "Some of the details are not valid. Check the form and try again.",
  401: "Your session has expired. Please sign in again.",
  403: "You do not have permission to do that.",
  404: "We could not find what you were looking for.",
  409: "That change conflicts with something that already exists.",
  413: "That file is too large. Try one under 5 MB.",
  422: "Some of the details are not valid. Check the form and try again.",
  429: "Too many requests. Wait a moment and try again.",
  500: "Zvingo had a problem on our side. Please try again.",
  502: "We could not reach Zvingo just now. Please try again.",
  503: "Zvingo is temporarily unavailable. Please try again in a moment.",
  504: "Zvingo took too long to respond. Please try again.",
};

function kindForStatus(status: number): ApiErrorKind {
  if (status === 401) return "auth";
  if (status === 403) return "forbidden";
  if (status === 404) return "not_found";
  if (status === 429) return "rate_limited";
  if (status === 400 || status === 409 || status === 422) return "validation";
  if (status >= 500) return "server";
  return "unknown";
}

/**
 * FastAPI returns `{detail: "..."}` or `{detail: [{loc, msg, type}, ...]}`.
 * Turn either into one readable sentence; fall back to a status-based message.
 */
function messageFromPayload(status: number, payload: unknown): string {
  const fallback = FRIENDLY_BY_STATUS[status] ?? "Something went wrong. Please try again.";
  if (!payload || typeof payload !== "object") return fallback;

  const detail = (payload as { detail?: unknown }).detail;
  if (typeof detail === "string" && detail.trim()) {
    // Server-authored copy is already user-facing for this API.
    return detail.trim().replace(/^\w/, (c) => c.toUpperCase());
  }
  if (Array.isArray(detail)) {
    const parts = detail
      .map((entry) => {
        if (!entry || typeof entry !== "object") return null;
        const e = entry as { loc?: unknown[]; msg?: string };
        const field = Array.isArray(e.loc) ? String(e.loc[e.loc.length - 1] ?? "") : "";
        const msg = e.msg ?? "";
        if (!msg) return null;
        const label = field ? field.replace(/_/g, " ") : "";
        return label ? `${label}: ${msg}` : msg;
      })
      .filter(Boolean) as string[];
    if (parts.length) return parts.slice(0, 3).join("; ");
  }
  const message = (payload as { message?: unknown }).message;
  if (typeof message === "string" && message.trim()) return message.trim();
  return fallback;
}

/* -------------------------------------------------------------------------- */
/* Auth storage                                                               */
/* -------------------------------------------------------------------------- */

const isBrowser = () => typeof window !== "undefined";

function safeStorage(): Storage | null {
  if (!isBrowser()) return null;
  try {
    return window.localStorage;
  } catch {
    // Private mode / blocked site data.
    return null;
  }
}

export function getToken(): string | null {
  return safeStorage()?.getItem(TOKEN_STORAGE_KEY) ?? null;
}

export function setToken(token: string) {
  safeStorage()?.setItem(TOKEN_STORAGE_KEY, token);
}

export function clearAuth() {
  const store = safeStorage();
  store?.removeItem(TOKEN_STORAGE_KEY);
  store?.removeItem(USER_STORAGE_KEY);
  // A refresh token outlives the access token by a long way. Leaving it behind
  // means "sign out" on a shared counter tablet leaves a live credential that
  // can mint new access tokens for weeks.
  store?.removeItem(REFRESH_TOKEN_STORAGE_KEY);
  store?.removeItem(TOKEN_EXPIRY_STORAGE_KEY);
}

export function isAuthenticated(): boolean {
  return Boolean(getToken());
}

/** Cache the signed-in profile so the shell can render a name without a round-trip. */
export function setCachedUser(user: unknown) {
  try {
    safeStorage()?.setItem(USER_STORAGE_KEY, JSON.stringify(user));
  } catch {
    /* storage unavailable or quota exceeded — the shell refetches instead */
  }
}

export function getCachedUser<T = UserProfile>(): T | null {
  try {
    const raw = safeStorage()?.getItem(USER_STORAGE_KEY);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

let redirectingToLogin = false;

/** Clear the session and send the user to /login once, preserving where they were. */
function handleUnauthorized() {
  clearAuth();
  if (!isBrowser() || redirectingToLogin) return;
  const path = window.location.pathname + window.location.search;
  if (window.location.pathname.startsWith("/login")) return;
  redirectingToLogin = true;
  const next = path && path !== "/" ? `?next=${encodeURIComponent(path)}` : "";
  window.location.href = `/login${next}`;
}

/* -------------------------------------------------------------------------- */
/* Core fetch                                                                 */
/* -------------------------------------------------------------------------- */

export interface ApiRequestOptions extends Omit<RequestInit, "body"> {
  /** JSON-serialisable body. Mutually exclusive with `rawBody`. */
  json?: unknown;
  /** FormData / string / Blob body, passed through untouched. */
  rawBody?: BodyInit | null;
  /** Abort after this many ms. Default 15000. Pass 0 to disable (SSE, uploads). */
  timeoutMs?: number;
  /** Retries for idempotent requests. Defaults to 2 for GET/HEAD, 0 otherwise. */
  retries?: number;
  /** Skip the automatic 401 → /login redirect (used by the login screen itself). */
  skipAuthRedirect?: boolean;
  /** Send without the Authorization header. */
  anonymous?: boolean;
}

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

function buildHeaders(options: ApiRequestOptions, hasJsonBody: boolean): Headers {
  const headers = new Headers(options.headers as HeadersInit | undefined);
  if (hasJsonBody && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  if (!headers.has("Accept")) headers.set("Accept", "application/json");
  if (!options.anonymous) {
    const token = getToken();
    if (token) headers.set("Authorization", `Bearer ${token}`);
  }
  return headers;
}

/**
 * Low-level request. Returns the raw `Response` for callers that need headers
 * or a non-JSON body; throws `ApiError` on transport failures and on 401.
 * Non-2xx responses are returned as-is (mirrors the historic `apiFetch`).
 */
export async function apiFetch(path: string, options: ApiRequestOptions | RequestInit = {}): Promise<Response> {
  const opts = options as ApiRequestOptions;
  const method = (opts.method ?? "GET").toUpperCase();
  const idempotent = method === "GET" || method === "HEAD";

  const legacyBody = (options as RequestInit).body;
  const hasJson = opts.json !== undefined || typeof legacyBody === "string";
  const body: BodyInit | null | undefined =
    opts.json !== undefined ? JSON.stringify(opts.json) : (opts.rawBody ?? legacyBody);

  const headers = buildHeaders(opts, hasJson);
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const maxAttempts = 1 + (opts.retries ?? (idempotent ? DEFAULT_RETRIES : 0));
  const url = `${API_BASE}${path.startsWith("/") ? path : `/${path}`}`;

  let lastError: ApiError | null = null;

  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const controller = new AbortController();
    const externalSignal = opts.signal;
    const onExternalAbort = () => controller.abort();
    externalSignal?.addEventListener("abort", onExternalAbort);
    let timedOut = false;
    const timer =
      timeoutMs > 0
        ? setTimeout(() => {
            timedOut = true;
            controller.abort();
          }, timeoutMs)
        : null;

    try {
      const response = await fetch(url, {
        ...opts,
        method,
        headers,
        body: body ?? undefined,
        signal: controller.signal,
      });

      if (response.status === 401) {
        if (!opts.skipAuthRedirect) handleUnauthorized();
        throw new ApiError({
          kind: "auth",
          status: 401,
          message: FRIENDLY_BY_STATUS[401]!,
          path,
          retryable: false,
        });
      }

      // Retry transient server/network-ish statuses on idempotent requests only.
      if (idempotent && RETRYABLE_STATUSES.has(response.status) && attempt < maxAttempts - 1) {
        lastError = new ApiError({
          kind: kindForStatus(response.status),
          status: response.status,
          message: FRIENDLY_BY_STATUS[response.status] ?? "Zvingo is having trouble. Please try again.",
          path,
        });
        await sleep(RETRY_BASE_DELAY_MS * 2 ** attempt + Math.random() * 120);
        continue;
      }

      return response;
    } catch (error) {
      if (error instanceof ApiError) throw error;

      const aborted =
        (error instanceof DOMException && error.name === "AbortError") ||
        (error instanceof Error && error.name === "AbortError");
      if (aborted && !timedOut) {
        // The caller cancelled (unmount, new search keystroke). Not an error.
        throw new ApiError({
          kind: "network",
          status: 0,
          message: "Request cancelled.",
          path,
          retryable: false,
          detail: error,
        });
      }

      lastError = timedOut
        ? new ApiError({
            kind: "timeout",
            status: 0,
            message: "Zvingo took too long to respond. Check your connection and try again.",
            path,
            detail: error,
          })
        : new ApiError({
            kind: "network",
            status: 0,
            message: "We could not reach Zvingo. Check your connection and try again.",
            path,
            detail: error,
          });

      if (!idempotent || attempt === maxAttempts - 1) throw lastError;
      await sleep(RETRY_BASE_DELAY_MS * 2 ** attempt + Math.random() * 120);
    } finally {
      if (timer) clearTimeout(timer);
      externalSignal?.removeEventListener("abort", onExternalAbort);
    }
  }

  throw lastError ?? new ApiError({ kind: "unknown", status: 0, message: "Something went wrong. Please try again.", path });
}

async function parseBody(response: Response): Promise<unknown> {
  if (response.status === 204 || response.headers.get("Content-Length") === "0") return null;
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

/**
 * Historic call sites use `apiJson(path)` with no type argument and then index
 * into the result. Defaulting to `any` keeps them compiling; new code should
 * pass an explicit type (or use `api.get<T>` / `endpoints.*`).
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type JsonResponse = any;

/** Request and decode JSON. Throws `ApiError` with a user-safe message on failure. */
export async function apiJson<T = JsonResponse>(
  path: string,
  options: ApiRequestOptions | RequestInit = {},
): Promise<T> {
  const response = await apiFetch(path, options);
  const payload = await parseBody(response);

  if (!response.ok) {
    throw new ApiError({
      kind: kindForStatus(response.status),
      status: response.status,
      message: messageFromPayload(response.status, payload),
      detail: payload,
      path,
    });
  }

  return payload as T;
}

/* -------------------------------------------------------------------------- */
/* Verb helpers                                                               */
/* -------------------------------------------------------------------------- */

type BodylessOptions = Omit<ApiRequestOptions, "json" | "rawBody" | "method">;
type BodyOptions = Omit<ApiRequestOptions, "method">;

export const api = {
  get: <T>(path: string, options: BodylessOptions = {}) => apiJson<T>(path, { ...options, method: "GET" }),
  post: <T>(path: string, json?: unknown, options: BodyOptions = {}) =>
    apiJson<T>(path, { ...options, method: "POST", json }),
  put: <T>(path: string, json?: unknown, options: BodyOptions = {}) =>
    apiJson<T>(path, { ...options, method: "PUT", json }),
  patch: <T>(path: string, json?: unknown, options: BodyOptions = {}) =>
    apiJson<T>(path, { ...options, method: "PATCH", json }),
  delete: <T = null>(path: string, options: BodylessOptions = {}) =>
    apiJson<T>(path, { ...options, method: "DELETE" }),
  /** Multipart upload straight to the backend (skips the `/api` rewrite). */
  upload: async <T>(path: string, form: FormData, options: BodylessOptions = {}): Promise<T> => {
    const headers = new Headers(options.headers as HeadersInit | undefined);
    const token = getToken();
    if (token) headers.set("Authorization", `Bearer ${token}`);
    const response = await fetch(`${UPLOAD_API_URL}${path.startsWith("/") ? path : `/${path}`}`, {
      method: "POST",
      body: form,
      headers,
    });
    const payload = await parseBody(response);
    if (response.status === 401) {
      handleUnauthorized();
      throw new ApiError({ kind: "auth", status: 401, message: FRIENDLY_BY_STATUS[401]!, path });
    }
    if (!response.ok) {
      throw new ApiError({
        kind: kindForStatus(response.status),
        status: response.status,
        message: messageFromPayload(response.status, payload),
        detail: payload,
        path,
      });
    }
    return payload as T;
  },
};

/* -------------------------------------------------------------------------- */
/* Backend contracts (mirrors the FastAPI routers under backend/app)          */
/* -------------------------------------------------------------------------- */

export type OrderState =
  | "CREATED"
  | "OFFERED"
  | "ACCEPTED"
  | "ARRIVED_AT_MERCHANT"
  | "READY_FOR_PICKUP"
  | "PICKED_UP"
  | "ARRIVED_AT_CUSTOMER"
  | "DELIVERED"
  | "CANCELLED";

/** Beanie serialises enums as `OrderState.ACCEPTED` in some responses. */
export function normaliseOrderState(state: string | null | undefined): OrderState {
  return (state ?? "CREATED").replace(/^OrderState\./, "") as OrderState;
}

export interface UserProfile {
  id: string;
  email?: string | null;
  phone: string;
  full_name: string;
  role: "merchant" | "driver" | "consumer" | "admin" | string;
  is_active: boolean;
  driver_rating?: number | null;
  driver_review_count?: number | null;
}

export interface GeoLocation {
  type?: "Point";
  coordinates: [number, number]; // [lng, lat]
}

export interface MenuItem {
  id: string;
  name: string;
  description?: string | null;
  price_usd: number;
  category: string;
  is_available: boolean;
  image_url?: string | null;
  images?: string[];
  approval_percent?: number | null;
  approval_count?: number | null;
  is_great_price?: boolean;
}

export interface Restaurant {
  _id?: string;
  id?: string;
  merchant_id?: string | null;
  name: string;
  description?: string | null;
  location?: GeoLocation;
  rating: number;
  delivery_time_min: number;
  delivery_time_max: number;
  delivery_fee_usd: number;
  is_active: boolean;
  categories: string[];
  dietary_tags?: string[];
  operating_hours?: string | null;
  image_url?: string | null;
  banner_url?: string | null;
  address: string;
  menu: MenuItem[];
  review_count?: number | null;
  free_delivery_threshold?: number | null;
  is_zvingo_plus?: boolean;
}

export interface OrderItem {
  name: string;
  quantity: number;
  price: number;
  special_instructions?: string | null;
}

export interface Order {
  id: string;
  state: OrderState | string;
  total_amount: number;
  created_at: string;
  driver_id?: string | null;
  driver_name?: string | null;
  merchant_id?: string | null;
  consumer_id?: string | null;
  items: OrderItem[];
  pickup_lat?: number | null;
  pickup_lng?: number | null;
  delivery_lat?: number | null;
  delivery_lng?: number | null;
  delivery_instructions?: string | null;
  group_id?: string | null;
}

export interface Promotion {
  _id?: string;
  id?: string;
  promo_id: string;
  merchant_id: string;
  restaurant_id?: string | null;
  title: string;
  subtitle: string;
  description?: string | null;
  icon: string;
  promo_type: "percentage" | "flat" | "free_delivery" | "free_item" | string;
  discount_value: number;
  min_order_usd: number;
  max_discount_usd?: number | null;
  free_item_id?: string | null;
  free_item_name?: string | null;
  starts_at: string;
  ends_at?: string | null;
  is_active: boolean;
  max_uses?: number | null;
  max_uses_per_user: number;
  current_uses: number;
  code?: string | null;
  created_at: string;
  updated_at: string;
}

export interface MerchantAnalytics {
  today_orders: number;
  today_gmv: number;
  total_orders: number;
  total_gmv: number;
  active_items: number;
  avg_prep_time: number;
}

export interface ExchangeRates {
  base: string;
  rates: Record<string, number>;
}

/** Normalise the `_id` / `id` split that Beanie documents expose. */
export function docId(doc: { id?: string; _id?: string } | null | undefined): string {
  return doc?.id || doc?._id || "";
}

/* -------------------------------------------------------------------------- */
/* Typed endpoint map — the one obvious way to call the backend               */
/* -------------------------------------------------------------------------- */

export const endpoints = {
  auth: {
    me: () => api.get<UserProfile>("/auth/me"),
    updateMe: (body: { full_name?: string; email?: string }) =>
      api.patch<UserProfile>("/auth/me", body),
    login: (phoneOrEmail: string, password: string) =>
      apiJson<{ access_token: string; token_type: string }>("/auth/token", {
        method: "POST",
        rawBody: new URLSearchParams({ username: phoneOrEmail, password }).toString(),
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        anonymous: true,
        skipAuthRedirect: true,
      }),
    register: (body: {
      phone: string;
      password: string;
      full_name: string;
      email?: string;
      role?: string;
    }) =>
      apiJson<{ access_token: string; token_type: string }>("/auth/register", {
        method: "POST",
        json: { role: "merchant", ...body },
        anonymous: true,
        skipAuthRedirect: true,
      }),
    requestPasswordReset: (phone: string) =>
      apiJson<{ status: string }>("/auth/reset-password/request", {
        method: "POST",
        json: { phone },
        anonymous: true,
        skipAuthRedirect: true,
      }),
    confirmPasswordReset: (token: string, newPassword: string) =>
      apiJson<{ status: string }>("/auth/reset-password/confirm", {
        method: "POST",
        json: { token, new_password: newPassword },
        anonymous: true,
        skipAuthRedirect: true,
      }),
  },

  catalog: {
    restaurantsForMerchant: (merchantId: string) =>
      api.get<Restaurant[]>(`/catalog/restaurants?merchant_id=${encodeURIComponent(merchantId)}`),
    restaurant: (restaurantId: string) => api.get<Restaurant>(`/catalog/restaurants/${restaurantId}`),
    createRestaurant: (body: Partial<Restaurant>) => api.post<Restaurant>("/catalog/restaurants", body),
    updateRestaurant: (restaurantId: string, body: Partial<Restaurant>) =>
      api.put<Restaurant>(`/catalog/restaurants/${restaurantId}`, body),
    addMenuItem: (restaurantId: string, body: Omit<MenuItem, "id">) =>
      api.post<Restaurant>(`/catalog/restaurants/${restaurantId}/menu`, body),
    updateMenuItem: (restaurantId: string, itemId: string, body: Partial<MenuItem>) =>
      api.put<Restaurant>(`/catalog/restaurants/${restaurantId}/menu/${itemId}`, body),
    deleteMenuItem: (restaurantId: string, itemId: string) =>
      api.delete<Restaurant>(`/catalog/restaurants/${restaurantId}/menu/${itemId}`),
  },

  promotions: {
    listMine: () => api.get<Promotion[]>("/catalog/promotions/merchant"),
    create: (body: Partial<Promotion>) => api.post<Promotion>("/catalog/promotions", body),
    update: (promoId: string, body: Partial<Promotion>) =>
      api.put<Promotion>(`/catalog/promotions/${promoId}`, body),
    toggle: (promoId: string) => api.patch<Promotion>(`/catalog/promotions/${promoId}/toggle`),
    remove: (promoId: string) => api.delete(`/catalog/promotions/${promoId}`),
  },

  orders: {
    /**
     * Orders across every restaurant this merchant owns, newest first.
     * `limit` / `offset` are optional — the backend clamps them server-side.
     */
    forMerchant: (merchantId: string, page?: { limit?: number; offset?: number }) => {
      const query = new URLSearchParams();
      if (page?.limit !== undefined) query.set("limit", String(page.limit));
      if (page?.offset !== undefined) query.set("offset", String(page.offset));
      const suffix = query.size ? `?${query.toString()}` : "";
      return api.get<Order[]>(`/orders/merchant/${merchantId}${suffix}`);
    },
    detail: (orderId: string) => api.get<Order>(`/orders/${orderId}`),
    setState: (orderId: string, state: OrderState) =>
      api.put<Order>(`/orders/${orderId}/state`, { state }),
    cancel: (orderId: string, reason?: string) =>
      api.post<{ status: string }>(`/orders/${orderId}/cancel`, reason ? { reason } : undefined),
  },

  finance: {
    merchantAnalytics: (merchantId: string) =>
      api.get<MerchantAnalytics>(`/finance/analytics/merchant/${merchantId}`),
    rates: () => api.get<ExchangeRates>("/finance/rates"),
  },

  ratings: {
    forRestaurant: (restaurantId: string) =>
      api.get<Array<{ id: string; rating: number; comment?: string | null; created_at: string }>>(
        `/rating/restaurants/${restaurantId}/reviews`,
      ),
  },

  uploads: {
    file: (form: FormData) => api.upload<{ url: string; filename?: string }>("/upload/", form),
  },
} as const;

/** SSE stream URL for a merchant channel (`GET /notification/events/{channel}`). */
export function eventStreamUrl(channelId: string): string {
  return `${API_BASE}/notification/events/${encodeURIComponent(channelId)}`;
}

/**
 * Open an authenticated SSE connection to one channel.
 *
 * The stream used to be reachable with only a channel name, which made it a
 * public feed of every restaurant's live orders — restaurant ids come from the
 * public catalog listing. It now needs a ticket minted from the caller's JWT.
 *
 * EventSource cannot send an Authorization header, so the ticket rides in the
 * query string. That is safe here in a way a JWT would not be: it is valid for
 * one subscription to one channel for about a minute, and is consumed the
 * moment the stream opens.
 *
 * Tickets are single-use, so every reconnect must call this again rather than
 * reusing a URL.
 */
export async function openEventStream(channelId: string): Promise<EventSource> {
  const { ticket } = await apiJson<{ ticket: string }>(
    "/notification/stream-ticket",
    { method: "POST", json: { channel: channelId } },
  );
  const url = `${eventStreamUrl(channelId)}?ticket=${encodeURIComponent(ticket)}`;
  return new EventSource(url);
}
