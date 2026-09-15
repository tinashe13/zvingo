"use client";

import * as React from "react";
import {
  Bike,
  CheckCircle2,
  ChefHat,
  Clock3,
  Inbox,
  PackageCheck,
  RefreshCw,
  Search,
  StickyNote,
  Timer,
  TriangleAlert,
  Utensils,
  type LucideIcon,
} from "lucide-react";
import { PageContainer } from "@/components/AppShell";
import {
  Badge,
  Button,
  ConfirmDialog,
  EmptyState,
  ErrorState,
  Input,
  OrderCardSkeleton,
  OrderStatusPill,
  Sheet,
  SkeletonRegion,
  cn,
  orderStatePresentation,
  useToast,
} from "@/components/ui";
import {
  api,
  endpoints,
  errorMessage,
  normaliseOrderState,
  type Order,
  type OrderState,
} from "@/lib/api";
import { useApi, useMerchantSession } from "@/lib/useApi";
import {
  formatDateTime,
  formatDuration,
  formatMoney,
  formatOrderRef,
  formatRelativeTime,
  humaniseState,
  minutesSince,
  pluralise,
} from "@/lib/format";
import { useNow } from "@/lib/hooks";

/* -------------------------------------------------------------------------- */
/* Live wiring (broadcast by app/dashboard/layout.tsx)                        */
/* -------------------------------------------------------------------------- */

const ORDERS_CHANGED_EVENT = "zvingo:orders-changed";
const LIVE_STATUS_EVENT = "zvingo:live-status";
const LIVE_STATUS_REQUEST_EVENT = "zvingo:live-status-request";

type LiveStatus = "live" | "connecting" | "offline";

/** Orders fetched per page. The API has no total count, so this drives "load more". */
const PAGE_SIZE = 60;

/**
 * The board polls on its own as well as listening to the stream. The stream
 * only fires on order creation, so every driver-side change (driver arrived,
 * order picked up) reaches this screen through the poll.
 */
const POLL_INTERVAL_MS = 15_000;

/** How long an accept / mark-ready can be taken back before it is sent. */
const UNDO_WINDOW_MS = 6_000;

/** Distinct drivers whose names are resolved per render pass. */
const DRIVER_LOOKUP_LIMIT = 8;

/* -------------------------------------------------------------------------- */
/* Lanes                                                                      */
/* -------------------------------------------------------------------------- */

type LaneId = "new" | "preparing" | "ready" | "out" | "done";
type AgeTone = "calm" | "warm" | "late";

interface LaneConfig {
  id: LaneId;
  title: string;
  /** One line a shift manager can act on. */
  hint: string;
  states: readonly OrderState[];
  Icon: LucideIcon;
  /** Minutes in this lane before the clock turns amber / red. 0 = no pressure. */
  warnAfter: number;
  lateAfter: number;
  /** Only today's orders belong in this lane. */
  todayOnly?: boolean;
}

const LANES: readonly LaneConfig[] = [
  {
    id: "new",
    title: "New",
    hint: "Accept or reject — the customer is waiting for an answer",
    states: ["CREATED", "OFFERED"],
    Icon: TriangleAlert,
    warnAfter: 3,
    lateAfter: 8,
  },
  {
    id: "preparing",
    title: "Preparing",
    hint: "In the kitchen. Mark ready when it is bagged",
    states: ["ACCEPTED", "ARRIVED_AT_MERCHANT"],
    Icon: ChefHat,
    warnAfter: 15,
    lateAfter: 25,
  },
  {
    id: "ready",
    title: "Ready for pickup",
    hint: "Bagged and waiting on the counter for the driver",
    states: ["READY_FOR_PICKUP"],
    Icon: PackageCheck,
    warnAfter: 8,
    lateAfter: 15,
  },
  {
    id: "out",
    title: "Picked up",
    hint: "On the way to the customer — nothing left for you to do",
    states: ["PICKED_UP", "ARRIVED_AT_CUSTOMER"],
    Icon: Bike,
    warnAfter: 0,
    lateAfter: 0,
  },
  {
    id: "done",
    title: "Done today",
    hint: "Delivered and cancelled orders from today",
    states: ["DELIVERED", "CANCELLED"],
    Icon: CheckCircle2,
    warnAfter: 0,
    lateAfter: 0,
    todayOnly: true,
  },
];

const LANE_BY_STATE = new Map<string, LaneConfig>(
  LANES.flatMap((lane) => lane.states.map((state) => [state as string, lane] as const)),
);

const AGE_TONE_CLASSES: Record<AgeTone, string> = {
  calm: "bg-neutral-100 text-neutral-700",
  warm: "bg-warning-surface text-warning",
  late: "bg-error-surface text-error",
};

function ageTone(minutes: number, lane: LaneConfig): AgeTone {
  if (!lane.lateAfter) return "calm";
  if (minutes >= lane.lateAfter) return "late";
  if (minutes >= lane.warnAfter) return "warm";
  return "calm";
}

/** Parse an API timestamp. Naive ISO strings from the backend are UTC. */
function parseTimestamp(value: string | null | undefined): Date | null {
  if (!value) return null;
  const raw = /^\d{4}-\d{2}-\d{2}T[\d:.]+$/.test(value) ? `${value}Z` : value;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? null : date;
}

function isToday(value: string | null | undefined, now: number): boolean {
  const date = parseTimestamp(value);
  if (!date) return false;
  const today = new Date(now);
  return (
    date.getFullYear() === today.getFullYear() &&
    date.getMonth() === today.getMonth() &&
    date.getDate() === today.getDate()
  );
}

interface BoardRow {
  order: Order;
  /** The state the board is showing, which may be an un-sent optimistic change. */
  state: OrderState;
  lane: LaneConfig;
  ageMinutes: number;
}

/* -------------------------------------------------------------------------- */
/* Page                                                                       */
/* -------------------------------------------------------------------------- */

export default function OrdersBoardPage() {
  const { merchantId, isLoading: sessionLoading, error: sessionError, refresh: refreshSession } =
    useMerchantSession();
  const toast = useToast();
  const now = useNow(10_000);

  const [limit, setLimit] = React.useState(PAGE_SIZE);
  const [query, setQuery] = React.useState("");
  const [detailId, setDetailId] = React.useState<string | null>(null);
  const [rejecting, setRejecting] = React.useState<Order | null>(null);
  const [liveStatus, setLiveStatus] = React.useState<LiveStatus>("connecting");
  const [lastUpdated, setLastUpdated] = React.useState<number | null>(null);

  const ordersQuery = useApi<Order[]>(
    merchantId ? `orders:board:${merchantId}:${limit}` : null,
    () => endpoints.orders.forMerchant(merchantId, { limit }),
    {
      refreshInterval: POLL_INTERVAL_MS,
      dedupeMs: 3_000,
      onSuccess: () => setLastUpdated(Date.now()),
    },
  );

  const orders = ordersQuery.data;
  const refreshOrders = ordersQuery.refresh;
  const mutateOrders = ordersQuery.mutate;

  /* ---- Live updates broadcast by the dashboard shell ---------------------- */

  React.useEffect(() => {
    const onChanged = () => void refreshOrders();
    const onStatus = (event: Event) => {
      const detail = (event as CustomEvent<LiveStatus>).detail;
      if (detail === "live" || detail === "connecting" || detail === "offline") {
        setLiveStatus(detail);
      }
    };
    window.addEventListener(ORDERS_CHANGED_EVENT, onChanged);
    window.addEventListener(LIVE_STATUS_EVENT, onStatus);
    // Ask the shell where the stream stands; it may have settled before this
    // route mounted, in which case no status event is coming on its own.
    window.dispatchEvent(new Event(LIVE_STATUS_REQUEST_EVENT));
    return () => {
      window.removeEventListener(ORDERS_CHANGED_EVENT, onChanged);
      window.removeEventListener(LIVE_STATUS_EVENT, onStatus);
    };
  }, [refreshOrders]);

  /* ---- Optimistic state with a real undo window --------------------------- */

  // The backend state machine has no backwards transitions: once an order is
  // ACCEPTED it can never return to CREATED. So "undo" cannot be a compensating
  // request — instead the change is shown at once and held for UNDO_WINDOW_MS
  // before it is sent. Undo inside that window means nothing was ever sent.
  const [overrides, setOverrides] = React.useState<Record<string, OrderState>>({});
  const pendingRef = React.useRef(new Map<string, { target: OrderState; timer: number }>());
  const [pendingIds, setPendingIds] = React.useState<string[]>([]);

  const clearOverride = React.useCallback((orderId: string) => {
    setOverrides((prev) => {
      if (!(orderId in prev)) return prev;
      const next = { ...prev };
      delete next[orderId];
      return next;
    });
  }, []);

  // Drop an optimistic state as soon as the server reports the same thing.
  React.useEffect(() => {
    if (!orders) return;
    setOverrides((prev) => {
      let changed = false;
      const next = { ...prev };
      for (const order of orders) {
        if (next[order.id] && normaliseOrderState(order.state) === next[order.id]) {
          delete next[order.id];
          changed = true;
        }
      }
      return changed ? next : prev;
    });
  }, [orders]);

  const applyRef = React.useRef<(orderId: string, target: OrderState) => Promise<void>>(
    async () => undefined,
  );

  const applyState = React.useCallback(
    async (orderId: string, target: OrderState) => {
      try {
        const updated = await endpoints.orders.setState(orderId, target);
        mutateOrders((prev) =>
          (prev ?? []).map((order) => (order.id === orderId ? { ...order, ...updated } : order)),
        );
      } catch (error) {
        clearOverride(orderId);
        toast.error("That change did not save", {
          description: errorMessage(error),
          action: { label: "Try again", onClick: () => void applyRef.current(orderId, target) },
        });
        void refreshOrders();
      }
    },
    [mutateOrders, clearOverride, toast, refreshOrders],
  );

  React.useEffect(() => {
    applyRef.current = applyState;
  }, [applyState]);

  /** Send a held change now (timer fired, page hidden, or the board unmounted). */
  const flush = React.useCallback((orderId: string) => {
    const pending = pendingRef.current.get(orderId);
    if (!pending) return;
    window.clearTimeout(pending.timer);
    pendingRef.current.delete(orderId);
    setPendingIds((ids) => ids.filter((id) => id !== orderId));
    void applyRef.current(orderId, pending.target);
  }, []);

  const undo = React.useCallback(
    (orderId: string) => {
      const pending = pendingRef.current.get(orderId);
      if (!pending) return;
      window.clearTimeout(pending.timer);
      pendingRef.current.delete(orderId);
      setPendingIds((ids) => ids.filter((id) => id !== orderId));
      clearOverride(orderId);
      toast.info("Change undone", {
        description: "Nothing was sent to the customer.",
        duration: 3_000,
      });
    },
    [clearOverride, toast],
  );

  // A held change must never be lost because the tablet was locked or the
  // merchant navigated away — send it instead of dropping it.
  React.useEffect(() => {
    const flushAll = () => Array.from(pendingRef.current.keys()).forEach(flush);
    window.addEventListener("pagehide", flushAll);
    return () => {
      window.removeEventListener("pagehide", flushAll);
      flushAll();
    };
  }, [flush]);

  const schedule = React.useCallback(
    (order: Order, target: OrderState, title: string, description: string) => {
      const existing = pendingRef.current.get(order.id);
      if (existing) window.clearTimeout(existing.timer);

      setOverrides((prev) => ({ ...prev, [order.id]: target }));
      const timer = window.setTimeout(() => flush(order.id), UNDO_WINDOW_MS);
      pendingRef.current.set(order.id, { target, timer });
      setPendingIds((ids) => (ids.includes(order.id) ? ids : [...ids, order.id]));

      toast.toast({
        id: `order-${order.id}`,
        tone: "success",
        title,
        description,
        onUndo: () => undo(order.id),
      });
    },
    [flush, toast, undo],
  );

  const acceptOrder = React.useCallback(
    (order: Order) =>
      schedule(
        order,
        "ACCEPTED",
        `${formatOrderRef(order.id)} accepted`,
        "The customer is told you are preparing it. Undo within a few seconds.",
      ),
    [schedule],
  );

  const markReady = React.useCallback(
    (order: Order) =>
      schedule(
        order,
        "READY_FOR_PICKUP",
        `${formatOrderRef(order.id)} is ready`,
        "The driver is told the food is on the counter.",
      ),
    [schedule],
  );

  const confirmReject = React.useCallback(async () => {
    const order = rejecting;
    if (!order) return;
    setRejecting(null);
    setOverrides((prev) => ({ ...prev, [order.id]: "CANCELLED" }));
    await applyRef.current(order.id, "CANCELLED");
    toast.warning(`${formatOrderRef(order.id)} rejected`, {
      description: "The order is cancelled and the customer has been refunded.",
    });
  }, [rejecting, toast]);

  /* ---- Driver names ------------------------------------------------------- */

  // `GET /orders/merchant/{id}` returns `driver_id` but never `driver_name`,
  // while `GET /orders/{id}` does. Resolve each distinct driver once and cache
  // it, rather than fetching a detail for every card.
  const driverNames = React.useRef(new Map<string, string>());
  const [, bumpDrivers] = React.useReducer((n: number) => n + 1, 0);
  const ordersRef = React.useRef<Order[] | undefined>(undefined);
  ordersRef.current = orders;

  const driverKey = React.useMemo(
    () =>
      Array.from(new Set((orders ?? []).map((order) => order.driver_id).filter(Boolean) as string[]))
        .sort()
        .join(","),
    [orders],
  );

  React.useEffect(() => {
    const ids = driverKey ? driverKey.split(",") : [];
    const unknown = ids.filter((id) => !driverNames.current.has(id)).slice(0, DRIVER_LOOKUP_LIMIT);
    if (!unknown.length) return;
    let cancelled = false;

    void (async () => {
      for (const driverId of unknown) {
        // Mark before awaiting so a re-render cannot queue the same lookup twice.
        driverNames.current.set(driverId, "");
        const carrying = ordersRef.current?.find((order) => order.driver_id === driverId);
        if (!carrying) continue;
        try {
          const detail = await endpoints.orders.detail(carrying.id);
          if (detail?.driver_name) driverNames.current.set(driverId, detail.driver_name);
        } catch {
          // Leave it blank: the card falls back to the driver reference.
        }
      }
      if (!cancelled) bumpDrivers();
    })();

    return () => {
      cancelled = true;
    };
  }, [driverKey]);

  /* ---- Board rows --------------------------------------------------------- */

  const rows = React.useMemo<BoardRow[]>(() => {
    const term = query.trim().toLowerCase();
    return (orders ?? [])
      .map((order) => {
        const state = overrides[order.id] ?? normaliseOrderState(order.state);
        const lane = LANE_BY_STATE.get(state);
        if (!lane) return null;
        if (lane.todayOnly && !isToday(order.created_at, now)) return null;
        return { order, state, lane, ageMinutes: minutesSince(order.created_at, now) };
      })
      .filter((row): row is BoardRow => row !== null)
      .filter((row) => {
        if (!term) return true;
        const haystack = [
          formatOrderRef(row.order.id),
          row.order.id,
          ...row.order.items.map((item) => item.name),
        ]
          .join(" ")
          .toLowerCase();
        return haystack.includes(term);
      });
  }, [orders, overrides, query, now]);

  const lanes = React.useMemo(
    () =>
      LANES.map((lane) => {
        const laneRows = rows
          .filter((row) => row.lane.id === lane.id)
          .sort((a, b) => b.ageMinutes - a.ageMinutes);
        return { lane, rows: laneRows, oldest: laneRows[0]?.ageMinutes ?? 0 };
      }),
    [rows],
  );

  const pageCount = orders?.length ?? 0;
  const hasMore = pageCount >= limit;
  const activeCount = rows.filter((row) => row.lane.id !== "done").length;

  /* ---- Render ------------------------------------------------------------- */

  if (sessionError && !merchantId) {
    return (
      <PageContainer>
        <ErrorState
          error={sessionError}
          title="We could not load your restaurant"
          onRetry={refreshSession}
        />
      </PageContainer>
    );
  }

  const loading = ordersQuery.isLoading || (sessionLoading && !orders);

  return (
    <PageContainer>
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="type-body text-text-secondary">
            {loading
              ? "Loading today’s orders…"
              : activeCount === 0
                ? "No orders in the kitchen right now."
                : `${pluralise(activeCount, "order")} in progress.`}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <LiveIndicator status={liveStatus} lastUpdated={lastUpdated} now={now} />
          <div className="w-56 max-sm:w-full">
            <Input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              inputSize="sm"
              leftIcon={<Search className="h-4 w-4" />}
              placeholder="Find an order or item"
              aria-label="Search orders by reference or item"
            />
          </div>
          <Button
            variant="secondary"
            size="sm"
            leftIcon={<RefreshCw className={cn("h-4 w-4", ordersQuery.isValidating && "zv-spin")} />}
            onClick={() => void refreshOrders()}
            disabled={ordersQuery.isValidating}
          >
            Refresh
          </Button>
        </div>
      </div>

      {ordersQuery.error && !orders ? (
        <ErrorState
          error={ordersQuery.error}
          title="We could not load your orders"
          onRetry={refreshOrders}
        />
      ) : loading ? (
        <SkeletonRegion label="Loading orders">
          <div className="zv-scroll-x flex gap-4 overflow-x-auto pb-2 max-md:flex-col max-md:overflow-x-visible">
            {LANES.slice(0, 4).map((lane) => (
              <div key={lane.id} className="w-[320px] shrink-0 max-md:w-full">
                <div className="mb-3 h-6 w-32 rounded-sm bg-neutral-200" />
                <div className="flex flex-col gap-3">
                  <OrderCardSkeleton />
                  <OrderCardSkeleton />
                </div>
              </div>
            ))}
          </div>
        </SkeletonRegion>
      ) : rows.length === 0 ? (
        <EmptyState
          icon={query ? Search : Inbox}
          title={query ? "Nothing matches that search" : "No orders yet"}
          description={
            query
              ? "Try the order reference (for example A93F21) or an item name."
              : "New orders appear here the moment a customer places one, with a sound and an alert you cannot miss."
          }
          action={
            query ? (
              <Button variant="secondary" onClick={() => setQuery("")}>
                Clear search
              </Button>
            ) : (
              <Button variant="secondary" onClick={() => void refreshOrders()}>
                Check again
              </Button>
            )
          }
        />
      ) : (
        <div
          className="zv-scroll-x flex items-start gap-4 overflow-x-auto pb-3 max-md:flex-col max-md:overflow-x-visible"
          role="list"
          aria-label="Orders by stage"
        >
          {lanes.map(({ lane, rows: laneRows, oldest }) => (
            <LaneColumn
              key={lane.id}
              lane={lane}
              rows={laneRows}
              oldest={oldest}
              pendingIds={pendingIds}
              driverNames={driverNames.current}
              onAccept={acceptOrder}
              onMarkReady={markReady}
              onReject={setRejecting}
              onUndo={undo}
              onOpenDetail={setDetailId}
            />
          ))}
        </div>
      )}

      {!loading && orders && orders.length > 0 && (
        <div className="mt-6 flex flex-col items-center gap-2">
          <p className="type-caption text-text-tertiary" aria-live="polite">
            Showing the {pluralise(pageCount, "most recent order")}.
          </p>
          {hasMore ? (
            <Button
              variant="secondary"
              onClick={() => setLimit((value) => value + PAGE_SIZE)}
              loading={ordersQuery.isValidating}
            >
              Load {PAGE_SIZE} older orders
            </Button>
          ) : (
            <p className="type-caption text-text-tertiary">That is every order on record.</p>
          )}
        </div>
      )}

      <ConfirmDialog
        open={rejecting !== null}
        onCancel={() => setRejecting(null)}
        onConfirm={confirmReject}
        tone="destructive"
        title={rejecting ? `Reject order ${formatOrderRef(rejecting.id)}?` : "Reject this order?"}
        consequence={
          rejecting
            ? `The order is cancelled and the customer is refunded ${formatMoney(
                rejecting.total_amount,
              )}. They are told the restaurant could not prepare it. This cannot be undone — Zvingo cannot send them your reason yet, so call them if they need to know why.`
            : ""
        }
        confirmLabel="Reject order"
        cancelLabel="Keep the order"
      />

      <OrderDetailSheet
        orderId={detailId}
        onClose={() => setDetailId(null)}
        driverNames={driverNames.current}
      />
    </PageContainer>
  );
}

/* -------------------------------------------------------------------------- */
/* Live indicator                                                             */
/* -------------------------------------------------------------------------- */

function LiveIndicator({
  status,
  lastUpdated,
  now,
}: {
  status: LiveStatus;
  lastUpdated: number | null;
  now: number;
}) {
  const label =
    status === "live" ? "Live" : status === "connecting" ? "Reconnecting" : "Auto-refresh";
  const tone = status === "live" ? "success" : status === "connecting" ? "warning" : "neutral";
  const explanation =
    status === "live"
      ? "New orders arrive instantly."
      : status === "connecting"
        ? `Instant alerts are reconnecting. The board still refreshes every ${Math.round(
            POLL_INTERVAL_MS / 1000,
          )} seconds.`
        : `The board refreshes every ${Math.round(POLL_INTERVAL_MS / 1000)} seconds.`;

  return (
    <span className="flex items-center gap-2" title={explanation}>
      <Badge tone={tone} dot size="sm">
        {label}
      </Badge>
      <span className="type-caption tabular-figures text-text-tertiary max-sm:hidden">
        {lastUpdated ? `Updated ${formatRelativeTime(lastUpdated, now).toLowerCase()}` : "Waiting…"}
      </span>
      <span className="zv-sr-only">{explanation}</span>
    </span>
  );
}

/* -------------------------------------------------------------------------- */
/* Lane                                                                       */
/* -------------------------------------------------------------------------- */

interface LaneColumnProps {
  lane: LaneConfig;
  rows: BoardRow[];
  oldest: number;
  pendingIds: string[];
  driverNames: Map<string, string>;
  onAccept: (order: Order) => void;
  onMarkReady: (order: Order) => void;
  onReject: (order: Order) => void;
  onUndo: (orderId: string) => void;
  onOpenDetail: (orderId: string) => void;
}

function LaneColumn({
  lane,
  rows,
  oldest,
  pendingIds,
  driverNames,
  onAccept,
  onMarkReady,
  onReject,
  onUndo,
  onOpenDetail,
}: LaneColumnProps) {
  const headingId = `lane-${lane.id}`;
  const tone = ageTone(oldest, lane);

  return (
    <section
      role="listitem"
      aria-labelledby={headingId}
      className="w-[320px] shrink-0 rounded-lg border border-border bg-surface-muted/70 p-3 max-md:w-full"
    >
      <header className="mb-3 px-1">
        <div className="flex items-center gap-2">
          <lane.Icon className="h-4 w-4 shrink-0 text-text-secondary" aria-hidden="true" />
          <h2 id={headingId} className="type-h3 min-w-0 flex-1 truncate text-neutral-900">
            {lane.title}
          </h2>
          <Badge tone="neutral" size="sm" className="tabular-figures">
            {rows.length}
          </Badge>
        </div>
        <p className="type-caption mt-1 text-text-secondary">{lane.hint}</p>
        {rows.length > 0 && lane.lateAfter > 0 && (
          <p
            className={cn(
              "mt-2 inline-flex items-center gap-1.5 rounded-sm px-2 py-1 type-caption font-bold tabular-figures",
              AGE_TONE_CLASSES[tone],
            )}
          >
            <Timer className="h-3.5 w-3.5" aria-hidden="true" />
            Oldest waiting {formatDuration(oldest)}
          </p>
        )}
      </header>

      {rows.length === 0 ? (
        <p className="rounded-md border border-dashed border-border px-3 py-6 text-center type-caption text-text-tertiary">
          Nothing here right now
        </p>
      ) : (
        <ul className="zv-stagger flex flex-col gap-3">
          {rows.map((row) => (
            <li key={row.order.id}>
              <OrderCard
                row={row}
                pending={pendingIds.includes(row.order.id)}
                driverName={row.order.driver_id ? driverNames.get(row.order.driver_id) : undefined}
                onAccept={onAccept}
                onMarkReady={onMarkReady}
                onReject={onReject}
                onUndo={onUndo}
                onOpenDetail={onOpenDetail}
              />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/* -------------------------------------------------------------------------- */
/* Card                                                                       */
/* -------------------------------------------------------------------------- */

const MAX_ITEMS_ON_CARD = 4;

interface OrderCardProps {
  row: BoardRow;
  pending: boolean;
  driverName?: string;
  onAccept: (order: Order) => void;
  onMarkReady: (order: Order) => void;
  onReject: (order: Order) => void;
  onUndo: (orderId: string) => void;
  onOpenDetail: (orderId: string) => void;
}

function OrderCard({
  row,
  pending,
  driverName,
  onAccept,
  onMarkReady,
  onReject,
  onUndo,
  onOpenDetail,
}: OrderCardProps) {
  const { order, state, lane, ageMinutes } = row;
  const tone = ageTone(ageMinutes, lane);
  const presentation = orderStatePresentation(state);
  const visibleItems = order.items.slice(0, MAX_ITEMS_ON_CARD);
  const hiddenItems = order.items.length - visibleItems.length;
  const itemCount = order.items.reduce((sum, item) => sum + (item.quantity || 0), 0);

  return (
    <article
      className={cn(
        "rounded-lg border bg-surface p-4 shadow-sm transition-shadow",
        tone === "late" ? "border-error/40" : "border-border",
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <h3 className="type-h3 tabular-figures text-neutral-900">{formatOrderRef(order.id)}</h3>
          <p className="type-caption text-text-secondary">
            {pluralise(itemCount, "item")} · {formatMoney(order.total_amount)}
          </p>
        </div>
        <span
          className={cn(
            "inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 type-caption font-bold tabular-figures",
            AGE_TONE_CLASSES[tone],
          )}
        >
          <Clock3 className="h-3.5 w-3.5" aria-hidden="true" />
          {formatDuration(ageMinutes)}
          {tone === "late" && <span className="zv-sr-only">— running late</span>}
        </span>
      </div>

      {lane.states.length > 1 && (
        <div className="mt-2.5">
          <OrderStatusPill state={state} size="sm" />
        </div>
      )}

      <ul className="mt-3 flex flex-col gap-1.5 border-t border-divider pt-3">
        {visibleItems.map((item, index) => (
          <li key={`${item.name}-${index}`} className="flex gap-2">
            <span className="type-body-strong shrink-0 tabular-figures text-neutral-900">
              {item.quantity}×
            </span>
            <span className="min-w-0 flex-1">
              <span className="type-body block text-neutral-900">{item.name}</span>
              {item.special_instructions && (
                <span className="type-caption mt-0.5 flex items-start gap-1.5 text-warning">
                  <Utensils className="mt-0.5 h-3 w-3 shrink-0" aria-hidden="true" />
                  {item.special_instructions}
                </span>
              )}
            </span>
          </li>
        ))}
        {hiddenItems > 0 && (
          <li className="type-caption text-text-secondary">
            + {pluralise(hiddenItems, "more item")}
          </li>
        )}
      </ul>

      {order.delivery_instructions && (
        <p className="type-caption mt-3 flex items-start gap-1.5 rounded-md bg-neutral-50 px-2.5 py-2 text-text-secondary">
          <StickyNote className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden="true" />
          <span className="min-w-0">{order.delivery_instructions}</span>
        </p>
      )}

      <p className="type-caption mt-3 flex items-center gap-1.5 text-text-secondary">
        <Bike className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
        {order.driver_id ? (
          <span className="min-w-0 truncate">
            Driver {driverName || formatOrderRef(order.driver_id)}
            {state === "ARRIVED_AT_MERCHANT" && " is at your counter"}
          </span>
        ) : (
          <span>No driver assigned yet</span>
        )}
      </p>

      {pending ? (
        <div className="mt-4 flex items-center justify-between gap-2 border-t border-divider pt-3">
          <span className="type-caption flex items-center gap-1.5 text-text-secondary">
            <Clock3 className="h-3.5 w-3.5" aria-hidden="true" />
            Sending…
          </span>
          <Button variant="secondary" size="sm" onClick={() => onUndo(order.id)}>
            Undo
          </Button>
        </div>
      ) : (
        <div className="mt-4 flex flex-wrap items-center gap-2 border-t border-divider pt-3">
          {lane.id === "new" && (
            <>
              <Button variant="primary" size="md" onClick={() => onAccept(order)} className="flex-1">
                Accept
              </Button>
              <Button variant="tertiary" size="md" onClick={() => onReject(order)}>
                Reject
              </Button>
            </>
          )}

          {lane.id === "preparing" && (
            <>
              <Button
                variant="secondary"
                size="md"
                onClick={() => onMarkReady(order)}
                className="flex-1"
                leftIcon={<PackageCheck className="h-4 w-4" />}
              >
                Mark ready
              </Button>
              <Button variant="tertiary" size="md" onClick={() => onReject(order)}>
                Cancel
              </Button>
            </>
          )}

          {lane.id === "ready" && (
            <>
              <span className="type-caption flex-1 text-text-secondary">
                Waiting for the driver to collect
              </span>
              <Button variant="tertiary" size="sm" onClick={() => onReject(order)}>
                Cancel
              </Button>
            </>
          )}

          {(lane.id === "out" || lane.id === "done") && (
            <span className="type-caption flex-1 text-text-secondary">{presentation.hint}</span>
          )}

          <Button variant="tertiary" size="sm" onClick={() => onOpenDetail(order.id)}>
            Details
          </Button>
        </div>
      )}
    </article>
  );
}

/* -------------------------------------------------------------------------- */
/* Detail sheet                                                               */
/* -------------------------------------------------------------------------- */

interface OrderEventRow {
  state: string;
  timestamp?: string | null;
  actor_id?: string | null;
  reason?: string | null;
}

function OrderDetailSheet({
  orderId,
  onClose,
  driverNames,
}: {
  orderId: string | null;
  onClose: () => void;
  driverNames: Map<string, string>;
}) {
  const detail = useApi<Order>(
    orderId ? `order:${orderId}` : null,
    () => endpoints.orders.detail(orderId as string),
    { dedupeMs: 10_000, revalidateOnFocus: false },
  );

  const events = useApi<OrderEventRow[]>(
    orderId ? `order:${orderId}:events` : null,
    () => api.get<OrderEventRow[]>(`/orders/${orderId}/events`),
    { dedupeMs: 10_000, revalidateOnFocus: false },
  );

  const order = detail.data;
  const driverName = order?.driver_name || (order?.driver_id ? driverNames.get(order.driver_id) : "");

  return (
    <Sheet
      open={orderId !== null}
      onClose={onClose}
      title={orderId ? `Order ${formatOrderRef(orderId)}` : "Order"}
      description={order ? `Placed ${formatDateTime(order.created_at)}` : undefined}
      width="md"
      footer={
        <Button variant="secondary" onClick={onClose}>
          Close
        </Button>
      }
    >
      {detail.error && !order ? (
        <ErrorState error={detail.error} size="sm" onRetry={detail.refresh} />
      ) : !order ? (
        <SkeletonRegion label="Loading order">
          <OrderCardSkeleton />
        </SkeletonRegion>
      ) : (
        <div className="flex flex-col gap-6">
          <div className="flex flex-wrap items-center gap-3">
            <OrderStatusPill state={normaliseOrderState(order.state)} />
            <span className="type-body-strong tabular-figures text-neutral-900">
              {formatMoney(order.total_amount)}
            </span>
          </div>

          <section>
            <h3 className="type-overline mb-2 text-text-secondary">Items</h3>
            <ul className="flex flex-col gap-2 rounded-md border border-border p-3">
              {order.items.map((item, index) => (
                <li key={`${item.name}-${index}`} className="flex items-start justify-between gap-3">
                  <span className="min-w-0">
                    <span className="type-body text-neutral-900">
                      <span className="tabular-figures font-bold">{item.quantity}×</span> {item.name}
                    </span>
                    {item.special_instructions && (
                      <span className="type-caption mt-0.5 block text-warning">
                        {item.special_instructions}
                      </span>
                    )}
                  </span>
                  <span className="type-body shrink-0 tabular-figures text-neutral-900">
                    {formatMoney(item.price * item.quantity)}
                  </span>
                </li>
              ))}
            </ul>
          </section>

          <section>
            <h3 className="type-overline mb-2 text-text-secondary">Delivery</h3>
            <dl className="flex flex-col gap-2">
              <DetailRow label="Driver" value={driverName || (order.driver_id ? "Assigned" : "Not assigned yet")} />
              <DetailRow
                label="Customer note"
                value={order.delivery_instructions || "None"}
              />
              <DetailRow label="Order reference" value={formatOrderRef(order.id)} />
            </dl>
          </section>

          <section>
            <h3 className="type-overline mb-2 text-text-secondary">History</h3>
            {events.error ? (
              <ErrorState
                error={events.error}
                size="sm"
                title="History is unavailable"
                onRetry={events.refresh}
              />
            ) : !events.data ? (
              <SkeletonRegion label="Loading history">
                <OrderCardSkeleton />
              </SkeletonRegion>
            ) : events.data.length === 0 ? (
              <p className="type-caption text-text-secondary">No history recorded yet.</p>
            ) : (
              <ol className="flex flex-col gap-3 border-l border-divider pl-4">
                {events.data.map((event, index) => (
                  <li key={`${event.state}-${index}`} className="relative">
                    <span
                      aria-hidden="true"
                      className="absolute -left-[21px] top-1.5 h-2.5 w-2.5 rounded-full bg-neutral-300"
                    />
                    <p className="type-body-strong text-neutral-900">
                      {humaniseState(event.state)}
                    </p>
                    <p className="type-caption tabular-figures text-text-secondary">
                      {formatDateTime(event.timestamp)}
                      {event.reason ? ` · ${event.reason.replace(/_/g, " ")}` : ""}
                    </p>
                  </li>
                ))}
              </ol>
            )}
          </section>
        </div>
      )}
    </Sheet>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <dt className="type-caption shrink-0 text-text-secondary">{label}</dt>
      <dd className="type-body min-w-0 text-right text-neutral-900">{value}</dd>
    </div>
  );
}
