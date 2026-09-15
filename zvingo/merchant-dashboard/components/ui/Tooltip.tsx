"use client";

import * as React from "react";
import { cn } from "@/lib/cn";

export type TooltipPlacement = "top" | "bottom" | "left" | "right";

export interface TooltipProps {
  /** The text shown in the bubble. Keep it to a short phrase. */
  content: React.ReactNode;
  children: React.ReactElement;
  placement?: TooltipPlacement;
  className?: string;
  /** Render the bubble even when the trigger is disabled (wraps in a span). */
  disabled?: boolean;
}

const PLACEMENT: Record<TooltipPlacement, string> = {
  top: "bottom-full left-1/2 -translate-x-1/2 mb-2",
  bottom: "top-full left-1/2 -translate-x-1/2 mt-2",
  left: "right-full top-1/2 -translate-y-1/2 mr-2",
  right: "left-full top-1/2 -translate-y-1/2 ml-2",
};

/**
 * Hover/focus tooltip. It supplements a visible label — it is never the only
 * way to learn what a control does (§5.4 bans unlabelled icon-only controls).
 */
export function Tooltip({ content, children, placement = "top", className, disabled }: TooltipProps) {
  const reactId = React.useId();
  const tooltipId = `tooltip-${reactId}`;

  const trigger = React.cloneElement(children, {
    "aria-describedby": tooltipId,
  } as React.HTMLAttributes<HTMLElement>);

  return (
    <span className={cn("group relative inline-flex", disabled && "cursor-not-allowed")}>
      {trigger}
      <span
        id={tooltipId}
        role="tooltip"
        className={cn(
          "pointer-events-none absolute z-50 w-max max-w-56 rounded-sm bg-neutral-900 px-2.5 py-1.5 text-caption font-medium text-neutral-0 shadow-md",
          "opacity-0 transition-opacity duration-(--motion-fast)",
          "group-hover:opacity-100 group-focus-within:opacity-100",
          PLACEMENT[placement],
          className,
        )}
      >
        {content}
      </span>
    </span>
  );
}
