"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import AppShell from "@/components/AppShell";
import { NewOrderAlert, useOrderAlertSound } from "@/components/ui";
import {
  docId,
  endpoints,
  eventStreamUrl,
  normaliseOrderState,
  type Order,
  type Restaurant,
} from "@/lib/api";
import { useApi, useMerchantSession } from "@/lib/useApi";
import { useNow } from "@/lib/hooks";

/* -------------------------------------------------------------------------- */
/* Live wiring                                                                */
/* -------------------------------------------------------------------------- */

/**
 * The dashboard chrome owns exactly one connection to the order event stream
 * and re-broadcasts what it hears on `window`, so the orders board (a separate
 * route module) stays live without opening a second stream per tab.
 *
 * These names are duplicated as literals in `app/dashboard/orders/page.tsx`.
 * They cannot live in a shared module: `layout.tsx` and `page.tsx` may only
 * export the fields Next.js recognises, and `lib/` is owned by another agent.
 */
const ORDERS_CHANGED_EVENT = "zvingo:orders-changed";
const LIVE_STATUS_EVENT = "zvingo:live-status";
const LIVE_STATUS_REQUEST_EVENT = "zvingo:live-status-request";

/** Orders the merchant has not responded to yet. */
const WAITING_STATES = new Set(["CREATED", "OFFERED"]);

/**
 * Polling is not a fallback of last resort here — it is the only way the
 * dashboard learns about driver-side progress, because the backend publishes a
 * merchant notification on order creation and on nothing else. The stream makes
 * new orders instant; this makes sure the board is never silently stale.
 */
const POLL_INTERVAL_MS = 20_000;

/** How many of the newest orders the alert watches. Waiting orders are newest. */
const ALERT_WINDOW = 40;

/** Reviewing silences an order; if it is still unanswered this long, re-alert. */
const ALERT_REARM_MS = 120_000;

/** The server pings every 15s. Three missed pings means the pipe is dead. */
const STREAM_SILENCE_MS = 45_000;

const RECONNECT_BASE_MS = 1_000;
const RECONNECT_MAX_MS = 30_000;

/** At most this many restaurant channels are watched from one tab. */
const MAX_CHANNELS = 4;

type LiveStatus = "live" | "connecting" | "offline";

/**
 * Subscribe to `GET /notification/events/{channel}` for every channel, with
 * exponential-backoff reconnection and a silence watchdog.
 *
 * `EventSource` reconnects on a dropped connection but gives up permanently on
 * an HTTP error, and it cannot notice a connection that is open but dead. Both
 * cases are handled here, because a board that has quietly stopped updating is
 * the worst failure this screen can have.
 */
function useOrderStream(channels: string[], onMessage: (payload: unknown) => void): LiveStatus {
  const [status, setStatus] = React.useState<LiveStatus>("connecting");
  const handlerRef = React.useRef(onMessage);

  React.useEffect(() => {
    handlerRef.current = onMessage;
  }, [onMessage]);

  // A primitive key keeps the effect from re-running on every render.
  const channelKey = channels.join("|");

  React.useEffect(() => {
    if (!channelKey) {
      setStatus("connecting");
      return;
    }
    if (typeof window === "undefined" || typeof window.EventSource === "undefined") {
      // No SSE support: the poll below is the only transport. Say so honestly.
      setStatus("offline");
      return;
    }

    const names = channelKey.split("|");
    const health = new Map<string, boolean>(names.map((name) => [name, false]));
    const cleanups: Array<() => void> = [];
    let cancelled = false;

    const publish = () => {
      if (cancelled) return;
      const values = Array.from(health.values());
      setStatus(values.some(Boolean) ? "live" : "connecting");
    };

    for (const channel of names) {
      let source: EventSource | null = null;
      let attempt = 0;
      let retryTimer = 0;
      let watchdog = 0;

      function beat() {
        if (cancelled) return;
        attempt = 0;
        health.set(channel, true);
        publish();
        window.clearTimeout(watchdog);
        watchdog = window.setTimeout(reconnect, STREAM_SILENCE_MS);
      }

      function reconnect() {
        if (cancelled) return;
        health.set(channel, false);
        publish();
        window.clearTimeout(watchdog);
        source?.close();
        source = null;
        const delay = Math.min(RECONNECT_MAX_MS, RECONNECT_BASE_MS * 2 ** attempt) + Math.random() * 400;
        attempt += 1;
        retryTimer = window.setTimeout(open, delay);
      }

      function open() {
        if (cancelled) return;
        let created: EventSource;
        try {
          created = new EventSource(eventStreamUrl(channel));
        } catch {
          reconnect();
          return;
        }
        source = created;

        created.addEventListener("open", beat);
        // sse_starlette names its handshake and keepalive frames, so neither
        // reaches `onmessage`; both still prove the connection is alive.
        created.addEventListener("connected", beat);
        created.addEventListener("ping", beat);

        created.onmessage = (event: MessageEvent<string>) => {
          beat();
          let payload: unknown = event.data;
          try {
            payload = JSON.parse(event.data);
          } catch {
            // The channel carries raw Redis strings; a non-JSON frame still
            // means something changed, so it is forwarded as-is.
          }
          handlerRef.current(payload);
        };

        created.onerror = () => {
          if (cancelled) return;
          if (created.readyState === EventSource.CLOSED) {
            reconnect();
          } else {
            health.set(channel, false);
            publish();
          }
        };
      }

      open();
      cleanups.push(() => {
        window.clearTimeout(retryTimer);
        window.clearTimeout(watchdog);
        source?.close();
      });
    }

    return () => {
      cancelled = true;
      cleanups.forEach((fn) => fn());
    };
  }, [channelKey]);

  return channelKey ? status : "connecting";
}

/* -------------------------------------------------------------------------- */
/* Layout                                                                     */
/* -------------------------------------------------------------------------- */

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const { merchantId } = useMerchantSession();
  const sound = useOrderAlertSound();
  const now = useNow(15_000);

  // Same cache key as `useMerchantSession`, so this shares one request with it
  // while giving us every restaurant rather than just the first.
  const restaurants = useApi<Restaurant[]>(
    merchantId ? `session:restaurants:${merchantId}` : null,
    () => endpoints.catalog.restaurantsForMerchant(merchantId),
    { dedupeMs: 30_000, revalidateOnFocus: false },
  );

  /**
   * The backend publishes to `merchant_{Order.merchant_id}`, and
   * `Order.merchant_id` holds the **restaurant** id, not the merchant user id
   * (see `app/auth/authorization.py: owning_merchant_id`). Subscribing with the
   * user id would connect successfully and then never receive a single order.
   */
  const channels = React.useMemo(
    () =>
      (restaurants.data ?? [])
        .map((restaurant) => docId(restaurant))
        .filter(Boolean)
        .slice(0, MAX_CHANNELS)
        .map((id) => `merchant_${id}`),
    [restaurants.data],
  );

  const orders = useApi<Order[]>(
    merchantId ? `orders:live:${merchantId}` : null,
    () => endpoints.orders.forMerchant(merchantId, { limit: ALERT_WINDOW }),
    { refreshInterval: POLL_INTERVAL_MS, dedupeMs: 5_000 },
  );

  const refreshOrders = orders.refresh;

  const handleStreamMessage = React.useCallback(
    (payload: unknown) => {
      void refreshOrders();
      if (typeof window !== "undefined") {
        window.dispatchEvent(new CustomEvent(ORDERS_CHANGED_EVENT, { detail: payload }));
      }
    },
    [refreshOrders],
  );

  const status = useOrderStream(channels, handleStreamMessage);

  // Re-broadcast the transport state so the orders board can tell the merchant
  // whether it is live or leaning on the poll, and answer late subscribers.
  React.useEffect(() => {
    if (typeof window === "undefined") return;
    const broadcast = () =>
      window.dispatchEvent(new CustomEvent(LIVE_STATUS_EVENT, { detail: status }));
    broadcast();
    window.addEventListener(LIVE_STATUS_REQUEST_EVENT, broadcast);
    return () => window.removeEventListener(LIVE_STATUS_REQUEST_EVENT, broadcast);
  }, [status]);

  /* ---- New-order alert ---------------------------------------------------- */

  // Reviewing the queue silences the orders that were in it at that moment.
  // New arrivals raise the alert again, and an order that is still unanswered
  // after ALERT_REARM_MS raises it again too — the food is going cold.
  const [acknowledged, setAcknowledged] = React.useState<Record<string, number>>({});

  const waiting = React.useMemo(
    () => (orders.data ?? []).filter((order) => WAITING_STATES.has(normaliseOrderState(order.state))),
    [orders.data],
  );

  React.useEffect(() => {
    // Forget orders that are no longer waiting so the map cannot grow forever.
    const live = new Set(waiting.map((order) => order.id));
    setAcknowledged((prev) => {
      const stale = Object.keys(prev).filter((id) => !live.has(id));
      if (!stale.length) return prev;
      const next = { ...prev };
      stale.forEach((id) => delete next[id]);
      return next;
    });
  }, [waiting]);

  const unanswered = waiting.filter((order) => {
    const at = acknowledged[order.id];
    return at === undefined || now - at > ALERT_REARM_MS;
  });

  const oldestWaiting = unanswered.reduce<string | undefined>((oldest, order) => {
    if (!order.created_at) return oldest;
    return !oldest || order.created_at < oldest ? order.created_at : oldest;
  }, undefined);

  const handleReview = React.useCallback(() => {
    const at = Date.now();
    setAcknowledged((prev) => {
      const next = { ...prev };
      waiting.forEach((order) => {
        next[order.id] = at;
      });
      return next;
    });
    // The click is a real user gesture, which is what the browser needs before
    // it will let the chime play at all.
    sound.arm();
    router.push("/dashboard/orders");
  }, [waiting, sound, router]);

  return (
    <AppShell
      banner={
        <NewOrderAlert
          count={unanswered.length}
          oldestCreatedAt={oldestWaiting}
          onReview={handleReview}
          sound={sound}
          position="top"
        />
      }
    >
      {children}
    </AppShell>
  );
}
