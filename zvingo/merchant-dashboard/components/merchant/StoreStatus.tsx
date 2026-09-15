"use client";

import * as React from "react";
import { CalendarClock, Clock, Loader2, PauseCircle, PlayCircle, Store } from "lucide-react";
import { cn } from "@/lib/cn";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { DropdownMenu } from "@/components/ui/DropdownMenu";
import { useOptionalToast } from "@/components/ui/Toast";
import { api } from "@/lib/api";
import { useApi, useMerchantSession } from "@/lib/useApi";

/* -------------------------------------------------------------------------- */
/* The store-availability contract (backend/app/catalog/router.py + hours.py)  */
/* -------------------------------------------------------------------------- */

/** One open window on one weekday, in the restaurant's own wall-clock time. */
export interface HoursInterval {
  /** `"HH:MM"`. */
  open: string;
  /** `"HH:MM"`; a value <= `open` means the window runs past midnight. */
  close: string;
}

/** One weekday. An empty `intervals` array means closed all day. */
export interface DayHours {
  /** 0 = Monday … 6 = Sunday. */
  day: number;
  intervals: HoursInterval[];
}

/** Computed "can this store take an order right now", and why. */
export interface Availability {
  is_open: boolean;
  status: "open" | "closed" | "closed_by_merchant" | "paused" | "unlisted" | string;
  /** Short sentence written by the backend, safe to show as-is. */
  reason: string;
  timezone: string;
  /** The restaurant's current wall-clock time, `"HH:MM"`. */
  local_time: string;
  /** ISO-8601 *local* datetime of the next opening, or null. */
  opens_at: string | null;
  /** ISO-8601 *local* datetime the current window ends, or null. */
  closes_at: string | null;
  accepts_scheduled: boolean;
}

/** `GET /catalog/restaurants/{id}/status`. */
export interface RestaurantStatus {
  restaurant_id: string;
  /** Platform listing switch — distinct from "closed right now". */
  is_active: boolean;
  /** Tri-state: `true` forces open, `false` forces closed, `null` follows `hours`. */
  is_open_override: boolean | null;
  pause_until: string | null;
  timezone: string;
  hours: DayHours[];
  /** Human-readable summary the backend derives from `hours`. */
  operating_hours: string | null;
  accepts_scheduled_orders: boolean;
  availability: Availability;
}

/** `PATCH /catalog/restaurants/{id}/status`. Only the keys you send are applied. */
export interface StoreStatusPatch {
  is_open_override?: boolean | null;
  /** Snooze for N minutes from now (1…1440). Mutually exclusive with `pause_until`. */
  pause_minutes?: number;
  pause_until?: string | null;
  /** Cancel an active pause immediately. */
  resume?: boolean;
  hours?: DayHours[];
  timezone?: string;
  accepts_scheduled_orders?: boolean;
  is_active?: boolean;
}

export const DAY_LABELS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
export const DAY_SHORT = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** Shared cache key so the header pill and the settings page stay in step. */
export function storeStatusKey(restaurantId: string): string {
  return `catalog:store-status:${restaurantId}`;
}

export function fetchStoreStatus(restaurantId: string): Promise<RestaurantStatus> {
  return api.get<RestaurantStatus>(`/catalog/restaurants/${restaurantId}/status`);
}

export function patchStoreStatus(
  restaurantId: string,
  body: StoreStatusPatch,
): Promise<RestaurantStatus> {
  return api.patch<RestaurantStatus>(`/catalog/restaurants/${restaurantId}/status`, body);
}

/**
 * `opens_at` / `closes_at` are already expressed in the restaurant's timezone,
 * so read the clock straight off the string rather than re-interpreting it in
 * the browser's zone (a manager on a laptop set to UTC must still see 08:00).
 */
export function localClock(iso: string | null | undefined): string {
  if (!iso) return "";
  const match = /T(\d{2}:\d{2})/.exec(iso);
  return match?.[1] ?? "";
}

export function localDayLabel(iso: string | null | undefined): string {
  if (!iso) return "";
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!match) return "";
  const [, y, m, d] = match;
  const date = new Date(Number(y), Number(m) - 1, Number(d));
  return DAY_SHORT[(date.getDay() + 6) % 7] ?? "";
}

/* -------------------------------------------------------------------------- */
/* Presentation                                                               */
/* -------------------------------------------------------------------------- */

type Tone = "open" | "paused" | "closed" | "unlisted";

const TONE_CLASS: Record<Tone, string> = {
  open: "bg-brand-green-surface text-brand-green-dark hover:bg-brand-green-surface/70",
  paused: "bg-warning-surface text-warning hover:bg-warning-surface/70",
  closed: "bg-neutral-100 text-neutral-700 hover:bg-neutral-200",
  unlisted: "bg-error-surface text-error hover:bg-error-surface/70",
};

const DOT_CLASS: Record<Tone, string> = {
  open: "bg-brand-green shadow-[0_0_0_4px_rgba(10,143,91,0.15)]",
  paused: "bg-warning",
  closed: "bg-neutral-400",
  unlisted: "bg-error",
};

export function statusTone(status: string): Tone {
  if (status === "open") return "open";
  if (status === "paused" || status === "closed_by_merchant") return "paused";
  if (status === "unlisted") return "unlisted";
  return "closed";
}

/** Short label for the header pill — colour is never the only signal. */
export function statusLabel(availability: Availability | undefined): string {
  if (!availability) return "Checking store";
  switch (availability.status) {
    case "open":
      return "Accepting orders";
    case "paused":
      return "Paused";
    case "closed_by_merchant":
      return "Closed by you";
    case "unlisted":
      return "Not listed";
    default:
      return "Closed";
  }
}

export interface StoreStatusProps {
  className?: string;
  /** Hide the written state and show only the dot (never used in the header). */
  compact?: boolean;
}

/**
 * The store's live open/closed state, visible at all times in the app bar.
 *
 * It reads the *computed* availability from the backend, which folds together
 * the weekly schedule, a temporary pause and the manual override in Africa/Harare
 * time — so this pill tells the truth even when nobody has touched it today.
 * Closing is revenue-affecting, so it is confirmed with the consequence spelled
 * out (§5.4). Re-opening is immediate.
 */
export default function StoreStatus({ className, compact }: StoreStatusProps) {
  const { restaurantId, isLoading: sessionLoading } = useMerchantSession();
  const toast = useOptionalToast();
  const [updating, setUpdating] = React.useState(false);
  const [confirmClose, setConfirmClose] = React.useState(false);

  const status = useApi<RestaurantStatus>(
    restaurantId ? storeStatusKey(restaurantId) : null,
    () => fetchStoreStatus(restaurantId),
    // The schedule rolls over on its own, so re-check every minute.
    { refreshInterval: 60_000, dedupeMs: 15_000 },
  );

  const availability = status.data?.availability;
  const tone = statusTone(availability?.status ?? "closed");

  const apply = React.useCallback(
    async (patch: StoreStatusPatch, success: { title: string; description?: string }) => {
      if (!restaurantId || updating) return;
      setUpdating(true);
      try {
        const next = await patchStoreStatus(restaurantId, patch);
        status.mutate(next);
        toast?.success(success.title, { description: success.description });
      } catch (error) {
        toast?.error("That change did not save", {
          description: error instanceof Error ? error.message : undefined,
          action: { label: "Try again", onClick: () => void apply(patch, success) },
        });
      } finally {
        setUpdating(false);
      }
    },
    // `status.mutate` is stable for a given key.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [restaurantId, updating, toast, status.mutate],
  );

  if (sessionLoading || (restaurantId && status.isLoading)) {
    return (
      <div
        className={cn(
          "flex h-11 items-center gap-2 rounded-full bg-neutral-100 px-4 type-caption font-bold text-text-secondary",
          className,
        )}
      >
        <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
        Checking store
      </div>
    );
  }

  if (!restaurantId) {
    return (
      <div
        className={cn(
          "flex h-11 items-center gap-2 rounded-full bg-neutral-100 px-4 type-caption font-bold text-neutral-700",
          className,
        )}
      >
        <Store className="h-4 w-4" aria-hidden="true" />
        Store not set up yet
      </div>
    );
  }

  if (status.error || !status.data) {
    return (
      <button
        type="button"
        onClick={() => void status.refresh()}
        className={cn(
          "zv-touch flex h-11 items-center gap-2 rounded-full bg-neutral-100 px-4 type-caption font-bold text-neutral-700 hover:bg-neutral-200",
          className,
        )}
      >
        <Store className="h-4 w-4" aria-hidden="true" />
        Store status unavailable — retry
      </button>
    );
  }

  const isOpen = Boolean(availability?.is_open);
  const detail = availability?.reason ?? "";
  const closesAt = localClock(availability?.closes_at);
  const opensAt = localClock(availability?.opens_at);

  const items = [
    {
      id: "follow-hours",
      label: "Follow my opening hours",
      description: status.data.operating_hours || "No weekly hours set yet",
      icon: <CalendarClock className="h-4 w-4" aria-hidden="true" />,
      disabled: status.data.is_open_override === null && !status.data.pause_until,
      onSelect: () =>
        void apply(
          { is_open_override: null, resume: true },
          {
            title: "Following your opening hours",
            description: status.data?.operating_hours
              ? `Zvingo will open and close you automatically: ${status.data.operating_hours}.`
              : "Set your weekly hours in Settings so this works automatically.",
          },
        ),
    },
    {
      id: "open-now",
      label: "Open now, whatever the schedule says",
      icon: <PlayCircle className="h-4 w-4" aria-hidden="true" />,
      disabled: status.data.is_open_override === true,
      onSelect: () =>
        void apply(
          { is_open_override: true, resume: true },
          { title: "Your store is accepting orders", description: "It stays open until you change this." },
        ),
    },
    {
      id: "pause-30",
      label: "Pause for 30 minutes",
      description: "Catch up on the queue, then re-open automatically",
      icon: <PauseCircle className="h-4 w-4" aria-hidden="true" />,
      separatorBefore: true,
      onSelect: () =>
        void apply(
          { pause_minutes: 30 },
          { title: "Paused for 30 minutes", description: "Zvingo will start taking orders again by itself." },
        ),
    },
    {
      id: "pause-60",
      label: "Pause for 1 hour",
      icon: <PauseCircle className="h-4 w-4" aria-hidden="true" />,
      onSelect: () =>
        void apply(
          { pause_minutes: 60 },
          { title: "Paused for 1 hour", description: "Zvingo will start taking orders again by itself." },
        ),
    },
    {
      id: "close",
      label: "Close until I re-open",
      icon: <Clock className="h-4 w-4" aria-hidden="true" />,
      destructive: true,
      disabled: status.data.is_open_override === false,
      onSelect: () => setConfirmClose(true),
    },
  ];

  const summary = compact
    ? undefined
    : updating
      ? "Saving…"
      : statusLabel(availability);

  return (
    <>
      <DropdownMenu
        label="Store availability"
        heading={`Local time ${availability?.local_time ?? "--:--"} · ${availability?.timezone ?? "Africa/Harare"}`}
        align="start"
        items={items}
        trigger={
          <button
            type="button"
            aria-label={`Store is ${statusLabel(availability).toLowerCase()}. ${detail}. Change availability`}
            disabled={updating}
            className={cn(
              "zv-touch flex h-11 items-center gap-2 rounded-full px-4 type-caption font-bold transition-colors",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action",
              "disabled:cursor-wait disabled:opacity-70",
              TONE_CLASS[tone],
              className,
            )}
          >
            <span aria-hidden="true" className={cn("h-2 w-2 shrink-0 rounded-full", DOT_CLASS[tone])} />
            {summary && <span>{summary}</span>}
            {!compact && (isOpen ? closesAt : opensAt) && (
              <span className="tabular-figures font-semibold opacity-75 max-sm:hidden">
                {isOpen ? `· until ${closesAt}` : `· opens ${opensAt}`}
              </span>
            )}
          </button>
        }
      />

      <ConfirmDialog
        open={confirmClose}
        tone="warning"
        title="Close your store until you re-open it?"
        consequence={
          "Customers will see you as closed and cannot place new orders, even during your opening hours. " +
          "Orders already in the kitchen are not affected. Nothing re-opens you automatically — you have to."
        }
        confirmLabel="Close the store"
        cancelLabel="Keep taking orders"
        onCancel={() => setConfirmClose(false)}
        onConfirm={async () => {
          setConfirmClose(false);
          await apply(
            { is_open_override: false },
            {
              title: "Your store is closed",
              description: "Re-open it from this menu when you are ready.",
            },
          );
        }}
      />
    </>
  );
}
