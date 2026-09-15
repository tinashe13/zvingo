"use client";

import * as React from "react";
import { useIsomorphicLayoutEffect } from "./hooks";
import {
  ApiError,
  api,
  docId,
  endpoints,
  isApiError,
  type Restaurant,
  type UserProfile,
  getCachedUser,
  setCachedUser,
} from "./api";

/* -------------------------------------------------------------------------- */
/* Tiny SWR-style cache                                                       */
/* -------------------------------------------------------------------------- */

type CacheEntry = { data: unknown; at: number };
const cache = new Map<string, CacheEntry>();
const subscribers = new Map<string, Set<() => void>>();

function notify(key: string) {
  subscribers.get(key)?.forEach((fn) => fn());
}

/** Write a value into the shared cache and wake every hook watching that key. */
export function mutateCache<T>(key: string, data: T) {
  cache.set(key, { data, at: Date.now() });
  notify(key);
}

/** Drop a cached key (or everything) — call after sign-out. */
export function clearApiCache(key?: string) {
  if (key) cache.delete(key);
  else cache.clear();
  if (key) notify(key);
  else subscribers.forEach((set) => set.forEach((fn) => fn()));
}

export interface UseApiOptions {
  /** Skip the request entirely (e.g. while an id is still unknown). */
  enabled?: boolean;
  /** Poll every N ms. Orders boards use 15–30s; analytics 60s. */
  refreshInterval?: number;
  /** Re-fetch when the tab regains focus. Default true. */
  revalidateOnFocus?: boolean;
  /** Serve cached data younger than this without a network call. Default 0. */
  dedupeMs?: number;
  onSuccess?: (data: unknown) => void;
  onError?: (error: ApiError) => void;
}

export interface UseApiResult<T> {
  data: T | undefined;
  error: ApiError | null;
  /** First load with nothing to show yet — render a skeleton. */
  isLoading: boolean;
  /** A background refresh is in flight — keep showing data, dim if you like. */
  isValidating: boolean;
  /** Re-run the request. Safe to pass straight to an ErrorState `onRetry`. */
  refresh: () => Promise<T | undefined>;
  /** Optimistically replace the cached value. */
  mutate: (next: T | ((prev: T | undefined) => T)) => void;
}

/**
 * Fetch-with-cache hook. `key` is both the cache key and the dependency: pass
 * `null` to suspend the request until its inputs are ready.
 *
 *   const { data, isLoading, error, refresh } =
 *     useApi(merchantId && `orders:${merchantId}`, () => endpoints.orders.forMerchant(merchantId));
 */
export function useApi<T>(
  key: string | null | false | undefined,
  fetcher: (signal: AbortSignal) => Promise<T>,
  options: UseApiOptions = {},
): UseApiResult<T> {
  const {
    enabled = true,
    refreshInterval = 0,
    revalidateOnFocus = true,
    dedupeMs = 0,
  } = options;

  const cacheKey = typeof key === "string" && key.length > 0 ? key : null;
  const active = Boolean(cacheKey) && enabled;

  const fetcherRef = React.useRef(fetcher);
  const callbacksRef = React.useRef(options);
  useIsomorphicLayoutEffect(() => {
    fetcherRef.current = fetcher;
    callbacksRef.current = options;
  });

  const [, forceRender] = React.useReducer((n: number) => n + 1, 0);
  const [error, setError] = React.useState<ApiError | null>(null);
  const [isValidating, setIsValidating] = React.useState(false);
  const abortRef = React.useRef<AbortController | null>(null);
  const mountedRef = React.useRef(true);

  React.useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      abortRef.current?.abort();
    };
  }, []);

  // Re-render whenever another hook mutates the same cache key.
  React.useEffect(() => {
    if (!cacheKey) return;
    let set = subscribers.get(cacheKey);
    if (!set) {
      set = new Set();
      subscribers.set(cacheKey, set);
    }
    set.add(forceRender);
    return () => {
      set?.delete(forceRender);
      if (set && set.size === 0) subscribers.delete(cacheKey);
    };
  }, [cacheKey]);

  const run = React.useCallback(async (): Promise<T | undefined> => {
    if (!cacheKey) return undefined;
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    setIsValidating(true);
    try {
      const data = await fetcherRef.current(controller.signal);
      if (!mountedRef.current || controller.signal.aborted) return undefined;
      cache.set(cacheKey, { data, at: Date.now() });
      setError(null);
      notify(cacheKey);
      callbacksRef.current.onSuccess?.(data);
      return data;
    } catch (err) {
      if (controller.signal.aborted || !mountedRef.current) return undefined;
      const apiError = isApiError(err)
        ? err
        : new ApiError({
            kind: "unknown",
            status: 0,
            message: err instanceof Error ? err.message : "Something went wrong. Please try again.",
            detail: err,
          });
      setError(apiError);
      callbacksRef.current.onError?.(apiError);
      return undefined;
    } finally {
      if (mountedRef.current) setIsValidating(false);
    }
  }, [cacheKey]);

  // Initial + key-change fetch.
  React.useEffect(() => {
    if (!active || !cacheKey) return;
    const entry = cache.get(cacheKey);
    if (entry && dedupeMs > 0 && Date.now() - entry.at < dedupeMs) return;
    void run();
  }, [active, cacheKey, dedupeMs, run]);

  // Polling.
  React.useEffect(() => {
    if (!active || refreshInterval <= 0) return;
    const id = window.setInterval(() => {
      if (document.visibilityState === "visible") void run();
    }, refreshInterval);
    return () => window.clearInterval(id);
  }, [active, refreshInterval, run]);

  // Revalidate on focus.
  React.useEffect(() => {
    if (!active || !revalidateOnFocus) return;
    const onFocus = () => {
      if (document.visibilityState === "visible") void run();
    };
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onFocus);
    return () => {
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onFocus);
    };
  }, [active, revalidateOnFocus, run]);

  const data = cacheKey ? (cache.get(cacheKey)?.data as T | undefined) : undefined;

  const mutate = React.useCallback(
    (next: T | ((prev: T | undefined) => T)) => {
      if (!cacheKey) return;
      const prev = cache.get(cacheKey)?.data as T | undefined;
      const resolved = typeof next === "function" ? (next as (p: T | undefined) => T)(prev) : next;
      cache.set(cacheKey, { data: resolved, at: Date.now() });
      notify(cacheKey);
    },
    [cacheKey],
  );

  return {
    data,
    error,
    isLoading: active && data === undefined && error === null,
    isValidating,
    refresh: run,
    mutate,
  };
}

/* -------------------------------------------------------------------------- */
/* Mutations                                                                  */
/* -------------------------------------------------------------------------- */

export interface UseMutationResult<TArgs extends unknown[], TResult> {
  run: (...args: TArgs) => Promise<TResult | undefined>;
  isPending: boolean;
  error: ApiError | null;
  reset: () => void;
}

/**
 * Wrap a write call with pending/error state. `run` resolves to `undefined`
 * when the call failed, so callers can branch without a try/catch.
 */
export function useMutation<TArgs extends unknown[], TResult>(
  mutator: (...args: TArgs) => Promise<TResult>,
  options: {
    onSuccess?: (result: TResult, ...args: TArgs) => void;
    onError?: (error: ApiError, ...args: TArgs) => void;
  } = {},
): UseMutationResult<TArgs, TResult> {
  const [isPending, setIsPending] = React.useState(false);
  const [error, setError] = React.useState<ApiError | null>(null);
  const mutatorRef = React.useRef(mutator);
  const optionsRef = React.useRef(options);
  useIsomorphicLayoutEffect(() => {
    mutatorRef.current = mutator;
    optionsRef.current = options;
  });
  const mountedRef = React.useRef(true);

  React.useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const run = React.useCallback(async (...args: TArgs) => {
    setIsPending(true);
    setError(null);
    try {
      const result = await mutatorRef.current(...args);
      optionsRef.current.onSuccess?.(result, ...args);
      return result;
    } catch (err) {
      const apiError = isApiError(err)
        ? err
        : new ApiError({
            kind: "unknown",
            status: 0,
            message: err instanceof Error ? err.message : "Something went wrong. Please try again.",
            detail: err,
          });
      if (mountedRef.current) setError(apiError);
      optionsRef.current.onError?.(apiError, ...args);
      return undefined;
    } finally {
      if (mountedRef.current) setIsPending(false);
    }
  }, []);

  const reset = React.useCallback(() => setError(null), []);

  return { run, isPending, error, reset };
}

/* -------------------------------------------------------------------------- */
/* Merchant session — every dashboard page needs these two ids                */
/* -------------------------------------------------------------------------- */

export interface MerchantSession {
  user: UserProfile | undefined;
  merchantId: string;
  restaurant: Restaurant | undefined;
  restaurantId: string;
  isLoading: boolean;
  error: ApiError | null;
  refresh: () => Promise<void>;
  /** Optimistically patch the cached restaurant (e.g. open/closed toggle). */
  patchRestaurant: (patch: Partial<Restaurant>) => void;
}

/**
 * The signed-in merchant and their restaurant, cached across pages. Use this
 * instead of re-deriving `merchantId` from `/auth/me` on every screen.
 */
export function useMerchantSession(): MerchantSession {
  const profile = useApi<UserProfile>("session:me", () => endpoints.auth.me(), {
    dedupeMs: 60_000,
    revalidateOnFocus: false,
  });

  const cachedUser = React.useMemo(() => getCachedUser<UserProfile>(), []);
  const user = profile.data ?? cachedUser ?? undefined;
  const merchantId = user?.id ?? "";

  React.useEffect(() => {
    if (profile.data) setCachedUser(profile.data);
  }, [profile.data]);

  const restaurants = useApi<Restaurant[]>(
    merchantId ? `session:restaurants:${merchantId}` : null,
    () => endpoints.catalog.restaurantsForMerchant(merchantId),
    { dedupeMs: 30_000, revalidateOnFocus: false },
  );

  const restaurant = restaurants.data?.[0];

  // Depend on the stable callbacks, not the result objects, so consumers can
  // safely put `refresh` / `patchRestaurant` in their own dependency arrays.
  const refreshProfile = profile.refresh;
  const refreshRestaurants = restaurants.refresh;
  const mutateRestaurants = restaurants.mutate;

  const refresh = React.useCallback(async () => {
    await refreshProfile();
    await refreshRestaurants();
  }, [refreshProfile, refreshRestaurants]);

  const patchRestaurant = React.useCallback(
    (patch: Partial<Restaurant>) => {
      mutateRestaurants((prev) =>
        prev?.length ? [{ ...prev[0]!, ...patch }, ...prev.slice(1)] : (prev ?? []),
      );
    },
    [mutateRestaurants],
  );

  return {
    user,
    merchantId,
    restaurant,
    restaurantId: docId(restaurant),
    isLoading: profile.isLoading || (Boolean(merchantId) && restaurants.isLoading),
    error: profile.error ?? restaurants.error,
    refresh,
    patchRestaurant,
  };
}

/** Live exchange rates (`GET /finance/rates`), refreshed hourly. */
export function useExchangeRates() {
  return useApi("finance:rates", () => endpoints.finance.rates(), {
    dedupeMs: 60 * 60_000,
    revalidateOnFocus: false,
  });
}

export { api, endpoints };
