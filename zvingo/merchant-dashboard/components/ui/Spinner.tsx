import * as React from "react";
import { cn } from "@/lib/cn";

export interface SpinnerProps extends React.SVGAttributes<SVGSVGElement> {
  /** Diameter in px. Defaults to 16 (inline, inside a button). */
  size?: number;
  /** Accessible label. Pass `null` when a visible label already describes it. */
  label?: string | null;
}

/**
 * Inline activity indicator. DESIGN_SYSTEM §4.3: spinners are legal ONLY
 * inside a button during submit — everywhere else use a `Skeleton`.
 */
export function Spinner({ size = 16, label = "Loading", className, ...props }: SpinnerProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      role={label ? "status" : undefined}
      aria-label={label ?? undefined}
      aria-hidden={label ? undefined : true}
      className={cn("zv-spin shrink-0", className)}
      {...props}
    >
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.25" strokeWidth="3" />
      <path
        d="M21 12a9 9 0 0 0-9-9"
        stroke="currentColor"
        strokeWidth="3"
        strokeLinecap="round"
      />
    </svg>
  );
}
