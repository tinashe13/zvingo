"use client";

import * as React from "react";
import { Loader2, Store } from "lucide-react";
import { cn } from "@/lib/cn";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { useOptionalToast } from "@/components/ui/Toast";
import { endpoints } from "@/lib/api";
import { useMerchantSession } from "@/lib/useApi";

export interface StoreStatusProps {
  className?: string;
  /** Hide the written state and show only the dot (never used in the header). */
  compact?: boolean;
}

/**
 * The store's accepting/paused state, visible at all times in the app bar.
 *
 * Pausing is a revenue-affecting action, so it is confirmed with the
 * consequence spelled out (§5.4). Re-opening is immediate.
 */
export default function StoreStatus({ className, compact }: StoreStatusProps) {
  const { restaurant, restaurantId, isLoading, patchRestaurant } = useMerchantSession();
  const toast = useOptionalToast();
  const [updating, setUpdating] = React.useState(false);
  const [confirmPause, setConfirmPause] = React.useState(false);

  const isOpen = Boolean(restaurant?.is_active);

  const apply = React.useCallback(
    async (next: boolean) => {
      if (!restaurantId || updating) return;
      setUpdating(true);
      patchRestaurant({ is_active: next });
      try {
        await endpoints.catalog.updateRestaurant(restaurantId, { is_active: next });
        toast?.success(next ? "Your store is accepting orders" : "New orders are paused", {
          description: next
            ? "Customers can order from you again."
            : "Customers will not see your store until you re-open.",
        });
      } catch (error) {
        patchRestaurant({ is_active: !next });
        toast?.error("That change did not save", {
          description: error instanceof Error ? error.message : undefined,
        });
      } finally {
        setUpdating(false);
      }
    },
    [restaurantId, updating, patchRestaurant, toast],
  );

  if (isLoading) {
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

  return (
    <>
      <button
        type="button"
        role="switch"
        aria-checked={isOpen}
        aria-label={isOpen ? "Pause new orders" : "Start accepting orders"}
        disabled={updating}
        onClick={() => (isOpen ? setConfirmPause(true) : void apply(true))}
        className={cn(
          "zv-touch flex h-11 items-center gap-2 rounded-full px-4 type-caption font-bold transition-colors",
          "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action",
          "disabled:cursor-wait disabled:opacity-70",
          isOpen
            ? "bg-brand-green-surface text-brand-green-dark hover:bg-brand-green-surface/70"
            : "bg-warning-surface text-warning hover:bg-warning-surface/70",
          className,
        )}
      >
        <span
          aria-hidden="true"
          className={cn(
            "h-2 w-2 shrink-0 rounded-full",
            isOpen ? "bg-brand-green shadow-[0_0_0_4px_rgba(10,143,91,0.15)]" : "bg-warning",
          )}
        />
        {!compact && (
          <span>{updating ? "Saving…" : isOpen ? "Accepting orders" : "Orders paused"}</span>
        )}
      </button>

      <ConfirmDialog
        open={confirmPause}
        tone="warning"
        title="Pause new orders?"
        consequence="Your store will disappear from the Zvingo app until you turn it back on. Orders already in progress are not affected."
        confirmLabel="Pause orders"
        cancelLabel="Keep accepting"
        onCancel={() => setConfirmPause(false)}
        onConfirm={async () => {
          setConfirmPause(false);
          await apply(false);
        }}
      />
    </>
  );
}
