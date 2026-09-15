"use client";

import * as React from "react";
import { AlertCircle } from "lucide-react";
import { cn } from "@/lib/cn";

export type FieldSize = "sm" | "md";

export interface FieldShellProps {
  /** Label text. Always sits above the control — never a disappearing placeholder (§5.3). */
  label?: React.ReactNode;
  /** Helper copy under the control. Hidden while an error is showing. */
  help?: React.ReactNode;
  /** Error copy. Rendered with an icon so state is never colour alone (§1.5). */
  error?: React.ReactNode;
  required?: boolean;
  /** Shown next to the label, e.g. a character counter or "Optional". */
  hint?: React.ReactNode;
  className?: string;
  /** id of the control, used for `htmlFor` and aria wiring. */
  htmlFor?: string;
  describedById?: string;
  errorId?: string;
  children: React.ReactNode;
}

/** Label-above / help-below / error-below shell shared by every form control. */
export function FieldShell({
  label,
  help,
  error,
  required,
  hint,
  className,
  htmlFor,
  describedById,
  errorId,
  children,
}: FieldShellProps) {
  return (
    <div className={cn("flex w-full flex-col gap-2", className)}>
      {(label || hint) && (
        <div className="flex items-baseline justify-between gap-3">
          {label && (
            <label htmlFor={htmlFor} className="type-caption font-semibold text-neutral-800">
              {label}
              {required && (
                <span className="ml-1 text-error" aria-hidden="true">
                  *
                </span>
              )}
              {required && <span className="zv-sr-only"> (required)</span>}
            </label>
          )}
          {hint && <span className="type-caption text-text-tertiary">{hint}</span>}
        </div>
      )}

      {children}

      {error ? (
        <p id={errorId} className="type-caption flex items-start gap-1.5 text-error">
          <AlertCircle className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden="true" />
          <span>{error}</span>
        </p>
      ) : help ? (
        <p id={describedById} className="type-caption text-text-secondary">
          {help}
        </p>
      ) : null}
    </div>
  );
}

/**
 * DESIGN_SYSTEM §5.3 — height 52 (44 when dense), fill `neutral/100`, no
 * border at rest, `radius/md`, 16px horizontal padding. Focus swaps the fill
 * to white and draws a 1.5px `action` border; error draws a 1.5px `error` one.
 */
export function controlClasses({
  size = "md",
  invalid,
  className,
  withLeftIcon,
  withRightIcon,
}: {
  size?: FieldSize;
  invalid?: boolean;
  className?: string;
  withLeftIcon?: boolean;
  withRightIcon?: boolean;
} = {}) {
  return cn(
    "w-full rounded-md border-[1.5px] border-transparent bg-neutral-100 text-neutral-900",
    "type-body placeholder:text-text-tertiary",
    "transition-[background-color,border-color,box-shadow]",
    "focus:bg-surface focus:border-action focus:outline-none",
    "disabled:cursor-not-allowed disabled:bg-neutral-100 disabled:text-action-disabled-fg",
    size === "md" ? "h-13 px-4" : "h-11 px-3",
    withLeftIcon && (size === "md" ? "pl-11" : "pl-10"),
    withRightIcon && (size === "md" ? "pr-11" : "pr-10"),
    invalid && "border-error bg-error-surface/40 focus:border-error",
    className,
  );
}
