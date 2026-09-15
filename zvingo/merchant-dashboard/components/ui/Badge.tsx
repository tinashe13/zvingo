import * as React from "react";
import {
  AlertTriangle,
  Ban,
  Bike,
  CheckCircle2,
  ChefHat,
  Clock3,
  Info,
  PackageCheck,
  Store,
  XCircle,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/cn";

export type Tone =
  | "neutral"
  | "success"
  | "warning"
  | "error"
  | "info"
  | "brand"
  | "deal"
  | "accent";

const TONE_CLASSES: Record<Tone, string> = {
  neutral: "bg-neutral-100 text-neutral-700",
  success: "bg-success-surface text-brand-green-dark",
  warning: "bg-warning-surface text-warning",
  error: "bg-error-surface text-error",
  info: "bg-info-surface text-info",
  brand: "bg-brand-green-surface text-brand-green-dark",
  deal: "bg-deal-surface text-deal",
  accent: "bg-brand-lime-surface text-neutral-900",
};

const TONE_DOT: Record<Tone, string> = {
  neutral: "bg-neutral-400",
  success: "bg-success",
  warning: "bg-warning",
  error: "bg-error",
  info: "bg-info",
  brand: "bg-brand-green",
  deal: "bg-deal",
  accent: "bg-brand-lime",
};

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  tone?: Tone;
  /** Small lucide icon rendered before the label. */
  icon?: React.ReactNode;
  /** Show a filled dot instead of an icon. */
  dot?: boolean;
  size?: "sm" | "md";
}

/**
 * Compact label. DESIGN_SYSTEM §1.5 — state is never communicated by colour
 * alone, so a badge always carries text and (for status) an icon or dot.
 */
export const Badge = React.forwardRef<HTMLSpanElement, BadgeProps>(function Badge(
  { className, tone = "neutral", icon, dot, size = "md", children, ...props },
  ref,
) {
  return (
    <span
      ref={ref}
      className={cn(
        "inline-flex max-w-full items-center gap-1.5 rounded-full font-bold",
        size === "md" ? "px-2.5 py-1 text-caption" : "px-2 py-0.5 text-overline uppercase",
        TONE_CLASSES[tone],
        className,
      )}
      {...props}
    >
      {dot && !icon && (
        <span className={cn("h-1.5 w-1.5 shrink-0 rounded-full", TONE_DOT[tone])} aria-hidden="true" />
      )}
      {icon && (
        <span className="flex shrink-0 items-center [&_svg]:h-3.5 [&_svg]:w-3.5" aria-hidden="true">
          {icon}
        </span>
      )}
      <span className="truncate">{children}</span>
    </span>
  );
});

export interface StatusPillProps extends Omit<BadgeProps, "children" | "tone"> {
  tone: Tone;
  label: string;
  /** Defaults to a sensible icon for the tone. */
  icon?: React.ReactNode;
}

const DEFAULT_TONE_ICON: Record<Tone, LucideIcon> = {
  neutral: Clock3,
  success: CheckCircle2,
  warning: AlertTriangle,
  error: XCircle,
  info: Info,
  brand: Store,
  deal: Info,
  accent: Info,
};

/** A status badge that always pairs colour with an icon and a written label. */
export const StatusPill = React.forwardRef<HTMLSpanElement, StatusPillProps>(function StatusPill(
  { tone, label, icon, ...props },
  ref,
) {
  const Fallback = DEFAULT_TONE_ICON[tone];
  return (
    <Badge ref={ref} tone={tone} icon={icon ?? <Fallback />} {...props}>
      {label}
    </Badge>
  );
});

/* -------------------------------------------------------------------------- */
/* Order state presentation — one source of truth for the whole dashboard     */
/* -------------------------------------------------------------------------- */

export interface OrderStatePresentation {
  label: string;
  tone: Tone;
  Icon: LucideIcon;
  /** One line a shift manager can act on. */
  hint: string;
}

const ORDER_STATE_PRESENTATION: Record<string, OrderStatePresentation> = {
  CREATED: { label: "New", tone: "error", Icon: AlertTriangle, hint: "Waiting for you to accept" },
  OFFERED: { label: "Finding driver", tone: "info", Icon: Bike, hint: "Looking for a nearby driver" },
  ACCEPTED: { label: "Preparing", tone: "warning", Icon: ChefHat, hint: "In the kitchen" },
  ARRIVED_AT_MERCHANT: { label: "Driver here", tone: "info", Icon: Bike, hint: "Driver is waiting at your counter" },
  READY_FOR_PICKUP: { label: "Ready", tone: "brand", Icon: PackageCheck, hint: "Waiting for pickup" },
  PICKED_UP: { label: "On the way", tone: "info", Icon: Bike, hint: "Out for delivery" },
  ARRIVED_AT_CUSTOMER: { label: "At customer", tone: "info", Icon: Bike, hint: "Driver has arrived" },
  DELIVERED: { label: "Delivered", tone: "success", Icon: CheckCircle2, hint: "Completed" },
  CANCELLED: { label: "Cancelled", tone: "neutral", Icon: Ban, hint: "No longer active" },
};

export function orderStatePresentation(state: string | null | undefined): OrderStatePresentation {
  const key = (state ?? "").replace(/^OrderState\./, "").toUpperCase();
  return (
    ORDER_STATE_PRESENTATION[key] ?? {
      label: key ? key.replace(/_/g, " ").toLowerCase() : "Unknown",
      tone: "neutral",
      Icon: Clock3,
      hint: "",
    }
  );
}

export interface OrderStatusPillProps extends Omit<BadgeProps, "children" | "tone" | "icon"> {
  state: string | null | undefined;
}

/** Status pill for an order, driven by the shared state → presentation map. */
export const OrderStatusPill = React.forwardRef<HTMLSpanElement, OrderStatusPillProps>(
  function OrderStatusPill({ state, ...props }, ref) {
    const { label, tone, Icon } = orderStatePresentation(state);
    return (
      <Badge ref={ref} tone={tone} icon={<Icon />} {...props}>
        {label}
      </Badge>
    );
  },
);
