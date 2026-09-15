"use client";

import * as React from "react";
import Link from "next/link";
import {
  ArrowRight,
  BellRing,
  ChefHat,
  Clock3,
  DollarSign,
  Inbox,
  ShoppingBag,
  Timer,
  UtensilsCrossed,
} from "lucide-react";
import { PageContainer, PageSection } from "@/components/AppShell";
import {
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  OrderStatusPill,
  SkeletonRegion,
  StatCard,
  StatCardSkeleton,
  buttonClasses,
  cn,
} from "@/components/ui";
import { api, endpoints, normaliseOrderState, type Order } from "@/lib/api";
import { useApi, useMerchantSession } from "@/lib/useApi";
import {
  formatDuration,
  formatMoney,
  formatOrderRef,
  formatRelativeTime,
  minutesSince,
  pluralise,
} from "@/lib/format";
import { useNow } from "@/lib/hooks";

/** Newest orders pulled for the overview. The API caps a page at 200. */
const OVERVIEW_LIMIT = 200;
const REFRESH_INTERVAL_MS = 30_000;

/** How many finished orders are sampled to measure the real prep time. */
const PREP_SAMPLE_SIZE = 12;

/** Rows in the live feed. */
const FEED_SIZE = 8;

const WAITING_STATES = new Set(["CREATED", "OFFERED"]);
const KITCHEN_STATES = new Set(["ACCEPTED", "ARRIVED_AT_MERCHANT"]);
const TERMINAL_STATES = new Set(["DELIVERED", "CANCELLED"]);

interface OrderEventRow {
  state: string;
  timestamp?: string | null;
  actor_id?: string | null;
  reason?: string | null;
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

export default function DashboardOverviewPage() {
  const {
    merchantId,
    restaurant,
    isLoading: sessionLoading,
    error: sessionError,
    refresh: refreshSession,
  } = useMerchantSession();
  const now = useNow(30_000);

  const ordersQuery = useApi<Order[]>(
    merchantId ? `orders:overview:${merchantId}` : null,
    () => endpoints.orders.forMerchant(merchantId, { limit: OVERVIEW_LIMIT }),
    { refreshInterval: REFRESH_INTERVAL_MS, dedupeMs: 5_000 },
  );

  const orders = ordersQuery.data;

  const today = React.useMemo(() => {
    const list = (orders ?? []).filter((order) => isToday(order.created_at, now));
    const delivered = list.filter((order) => normaliseOrderState(order.state) === "DELIVERED");
    const waiting = list.filter((order) => WAITING_STATES.has(normaliseOrderState(order.state)));
    const inKitchen = list.filter((order) => KITCHEN_STATES.has(normaliseOrderState(order.state)));
    const openValue = list
      .filter((order) => !TERMINAL_STATES.has(normaliseOrderState(order.state)))
      .reduce((sum, order) => sum + (order.total_amount || 0), 0);

    return {
      all: list,
      delivered,
      waiting,
      inKitchen,
      revenue: delivered.reduce((sum, order) => sum + (order.total_amount || 0), 0),
      openValue,
      oldestWait: waiting.reduce(
        (oldest, order) => Math.max(oldest, minutesSince(order.created_at, now)),
        0,
      ),
    };
  }, [orders, now]);

  /* ---- Average prep time, measured from the real audit trail --------------- */

  // `GET /finance/analytics/merchant/{id}` cannot supply this: it matches
  // `Order.merchant_id` (a restaurant id) against the merchant *user* id, so it
  // returns zeros and a hard-coded 18-minute fallback. Rather than print a
  // fabricated number, prep time is computed from the order event trail.
  const prepIds = React.useMemo(
    () =>
      today.delivered
        .slice(0, PREP_SAMPLE_SIZE)
        .map((order) => order.id)
        .sort(),
    [today.delivered],
  );

  const prepQuery = useApi<{ minutes: number; sample: number }>(
    prepIds.length ? `prep:${merchantId}:${prepIds.join(",")}` : null,
    async () => {
      const results = await Promise.allSettled(
        prepIds.map((id) => api.get<OrderEventRow[]>(`/orders/${id}/events`)),
      );
      const durations: number[] = [];
      for (const result of results) {
        if (result.status !== "fulfilled") continue;
        let acceptedAt: number | null = null;
        let pickedUpAt: number | null = null;
        for (const event of result.value) {
          const at = parseTimestamp(event.timestamp);
          if (!at) continue;
          const state = (event.state ?? "").replace(/^OrderState\./, "");
          if (state === "ACCEPTED") acceptedAt = at.getTime();
          else if (state === "PICKED_UP" && pickedUpAt === null) pickedUpAt = at.getTime();
        }
        if (acceptedAt !== null && pickedUpAt !== null && pickedUpAt > acceptedAt) {
          durations.push((pickedUpAt - acceptedAt) / 60_000);
        }
      }
      return durations.length
        ? { minutes: durations.reduce((a, b) => a + b, 0) / durations.length, sample: durations.length }
        : { minutes: 0, sample: 0 };
    },
    { dedupeMs: 5 * 60_000, revalidateOnFocus: false },
  );

  const prepSample = prepQuery.data?.sample ?? 0;

  /* ---- Menu availability, straight from the restaurant record ------------- */

  const availableItems = restaurant?.menu?.filter((item) => item.is_available).length ?? 0;
  const totalItems = restaurant?.menu?.length ?? 0;

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
  const feed = (orders ?? []).slice(0, FEED_SIZE);

  return (
    <PageContainer>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <p className="type-body min-w-0 text-text-secondary">
          {restaurant?.name ? `${restaurant.name} · today so far` : "Today so far"}
        </p>
        <Link href="/dashboard/orders" className={buttonClasses({ variant: "primary", size: "md" })}>
          Open live orders
          <ArrowRight className="h-4 w-4" aria-hidden="true" />
        </Link>
      </div>

      {ordersQuery.error && !orders ? (
        <ErrorState
          error={ordersQuery.error}
          title="We could not load today’s figures"
          onRetry={ordersQuery.refresh}
        />
      ) : (
        <>
          <PageSection
            title="Today"
            description="Everything below is measured from your own orders since midnight."
          >
            {loading ? (
              <SkeletonRegion label="Loading today’s figures">
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
                  <StatCardSkeleton />
                  <StatCardSkeleton />
                  <StatCardSkeleton />
                  <StatCardSkeleton />
                </div>
              </SkeletonRegion>
            ) : (
              <div className="zv-stagger grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
                <StatCard
                  label="Orders today"
                  value={today.all.length}
                  icon={ShoppingBag}
                  hint={`${today.delivered.length} delivered so far`}
                />
                <StatCard
                  label="Revenue today"
                  value={today.revenue}
                  format="money"
                  icon={DollarSign}
                  hint={
                    today.openValue > 0
                      ? `${formatMoney(today.openValue)} still in progress`
                      : "From delivered orders"
                  }
                />
                <StatCard
                  label="Waiting to accept"
                  value={today.waiting.length}
                  icon={BellRing}
                  hint={
                    today.waiting.length
                      ? `Oldest has waited ${formatDuration(today.oldestWait)}`
                      : "Nothing needs you right now"
                  }
                />
                <StatCard
                  label="Average prep time"
                  value={prepSample ? (prepQuery.data?.minutes ?? 0) : "—"}
                  format="duration"
                  icon={Timer}
                  lowerIsBetter
                  loading={prepIds.length > 0 && prepQuery.isLoading}
                  hint={
                    prepSample
                      ? `Accept to pickup, across ${pluralise(prepSample, "order")} finished today`
                      : "Measured once an order is picked up today"
                  }
                />
              </div>
            )}
          </PageSection>

          {today.waiting.length > 0 && (
            <PageSection
              title="Needs you now"
              description="These customers are waiting for you to accept or reject."
              actions={
                <Link
                  href="/dashboard/orders"
                  className={buttonClasses({ variant: "secondary", size: "sm" })}
                >
                  Go to the board
                </Link>
              }
            >
              <ul className="zv-stagger flex flex-col gap-3">
                {today.waiting.slice(0, 3).map((order) => {
                  const waited = minutesSince(order.created_at, now);
                  return (
                    <li key={order.id}>
                      <Card className="flex flex-wrap items-center justify-between gap-3">
                        <div className="min-w-0">
                          <p className="type-h3 tabular-figures text-neutral-900">
                            {formatOrderRef(order.id)}
                          </p>
                          <p className="type-caption text-text-secondary">
                            {pluralise(
                              order.items.reduce((sum, item) => sum + (item.quantity || 0), 0),
                              "item",
                            )}{" "}
                            · {formatMoney(order.total_amount)}
                          </p>
                        </div>
                        <span
                          className={cn(
                            "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 type-caption font-bold tabular-figures",
                            waited >= 8
                              ? "bg-error-surface text-error"
                              : waited >= 3
                                ? "bg-warning-surface text-warning"
                                : "bg-neutral-100 text-neutral-700",
                          )}
                        >
                          <Clock3 className="h-3.5 w-3.5" aria-hidden="true" />
                          Waiting {formatDuration(waited)}
                        </span>
                      </Card>
                    </li>
                  );
                })}
              </ul>
            </PageSection>
          )}

          <PageSection
            title="Live feed"
            description={`Updates on their own every ${Math.round(REFRESH_INTERVAL_MS / 1000)} seconds.`}
            actions={
              <Button
                variant="tertiary"
                size="sm"
                onClick={() => void ordersQuery.refresh()}
                disabled={ordersQuery.isValidating}
              >
                Refresh
              </Button>
            }
          >
            {loading ? (
              <SkeletonRegion label="Loading recent orders">
                <div className="flex flex-col gap-3">
                  <StatCardSkeleton />
                  <StatCardSkeleton />
                </div>
              </SkeletonRegion>
            ) : feed.length === 0 ? (
              <EmptyState
                icon={Inbox}
                title="No orders yet"
                description="When a customer orders, it lands here and on the live board with a sound you cannot miss."
                action={
                  <Link
                    href="/dashboard/menu"
                    className={buttonClasses({ variant: "secondary", size: "md" })}
                  >
                    Check your menu
                  </Link>
                }
              />
            ) : (
              <Card flush>
                <ul className="zv-stagger divide-y divide-divider">
                  {feed.map((order) => (
                    <li
                      key={order.id}
                      className="flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3"
                    >
                      <span className="type-body-strong w-24 shrink-0 tabular-figures text-neutral-900">
                        {formatOrderRef(order.id)}
                      </span>
                      <OrderStatusPill state={normaliseOrderState(order.state)} size="sm" />
                      <span className="type-caption min-w-0 flex-1 truncate text-text-secondary">
                        {order.items
                          .slice(0, 3)
                          .map((item) => `${item.quantity}× ${item.name}`)
                          .join(", ")}
                      </span>
                      <span className="type-caption shrink-0 tabular-figures text-text-tertiary">
                        {formatRelativeTime(order.created_at, now)}
                      </span>
                      <span className="type-body-strong shrink-0 tabular-figures text-neutral-900">
                        {formatMoney(order.total_amount)}
                      </span>
                    </li>
                  ))}
                </ul>
              </Card>
            )}
          </PageSection>

          <PageSection
            title="Your menu"
            description="What customers can order from you right now."
            actions={
              <Link
                href="/dashboard/menu"
                className={buttonClasses({ variant: "secondary", size: "sm" })}
              >
                Manage menu
              </Link>
            }
          >
            <Card className="flex flex-wrap items-center justify-between gap-4">
              <div className="flex items-center gap-3">
                <span
                  aria-hidden="true"
                  className="flex h-11 w-11 shrink-0 items-center justify-center rounded-md bg-neutral-100 text-neutral-700"
                >
                  <UtensilsCrossed className="h-5 w-5" />
                </span>
                <div>
                  <p className="type-h3 tabular-figures text-neutral-900">
                    {sessionLoading && !restaurant
                      ? "—"
                      : `${availableItems} of ${totalItems} available`}
                  </p>
                  <p className="type-caption text-text-secondary">
                    {totalItems === 0
                      ? "Add your first dish so customers can order."
                      : availableItems === totalItems
                        ? "Everything on your menu is switched on."
                        : `${totalItems - availableItems} hidden from customers.`}
                  </p>
                </div>
              </div>
              <Badge tone={today.inKitchen.length ? "warning" : "neutral"} icon={<ChefHat />}>
                {pluralise(today.inKitchen.length, "order")} in the kitchen
              </Badge>
            </Card>
          </PageSection>
        </>
      )}
    </PageContainer>
  );
}
