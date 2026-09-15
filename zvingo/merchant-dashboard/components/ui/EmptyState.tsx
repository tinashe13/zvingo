import * as React from "react";
import { Inbox, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/cn";

export interface EmptyStateProps {
  /** Lucide icon component (not an element) — rendered inside a tinted tile. */
  icon?: LucideIcon;
  title: string;
  /** One sentence explaining why this is empty and what happens next. */
  description: string;
  /** The single action that moves the user forward. Never leave a dead end. */
  action?: React.ReactNode;
  /** An optional lower-emphasis escape hatch, e.g. "Learn how pricing works". */
  secondaryAction?: React.ReactNode;
  size?: "sm" | "md";
  className?: string;
}

/**
 * DESIGN_SYSTEM §5.5 — an empty list always shows an icon, a one-line title,
 * a one-line explanation and a button that moves the user forward.
 */
export function EmptyState({
  icon: Icon = Inbox,
  title,
  description,
  action,
  secondaryAction,
  size = "md",
  className,
}: EmptyStateProps) {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center px-6 text-center",
        size === "md" ? "py-16" : "py-10",
        className,
      )}
    >
      <span
        aria-hidden="true"
        className={cn(
          "flex items-center justify-center rounded-lg bg-neutral-100 text-text-secondary",
          size === "md" ? "h-14 w-14" : "h-11 w-11",
        )}
      >
        <Icon className={size === "md" ? "h-7 w-7" : "h-5 w-5"} />
      </span>
      <h3 className={cn("mt-4 text-neutral-900", size === "md" ? "type-h3" : "type-body-strong")}>
        {title}
      </h3>
      <p className="type-caption mt-1.5 max-w-sm text-text-secondary">{description}</p>
      {(action || secondaryAction) && (
        <div className="mt-5 flex flex-col items-center gap-3 sm:flex-row">
          {action}
          {secondaryAction}
        </div>
      )}
    </div>
  );
}
