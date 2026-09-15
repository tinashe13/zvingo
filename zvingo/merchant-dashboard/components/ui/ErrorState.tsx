"use client";

import * as React from "react";
import { CloudOff, RefreshCw, ShieldAlert, TriangleAlert, WifiOff } from "lucide-react";
import { cn } from "@/lib/cn";
import { Button } from "./Button";
import { isApiError } from "@/lib/api";

export interface ErrorStateProps {
  /** Anything thrown by the data layer. `ApiError` messages are already safe. */
  error?: unknown;
  /** Overrides the derived title. */
  title?: string;
  /** Overrides the derived explanation. */
  description?: string;
  /** Retry handler. Omit only when retrying genuinely cannot help. */
  onRetry?: () => void | Promise<unknown>;
  retryLabel?: string;
  /** Extra escape hatch, e.g. a "Go to orders" link. */
  action?: React.ReactNode;
  size?: "sm" | "md";
  className?: string;
}

function presentation(error: unknown) {
  if (isApiError(error)) {
    switch (error.kind) {
      case "network":
        return { Icon: WifiOff, title: "You appear to be offline" };
      case "timeout":
        return { Icon: CloudOff, title: "Zvingo did not respond in time" };
      case "forbidden":
        return { Icon: ShieldAlert, title: "You do not have access to this" };
      case "not_found":
        return { Icon: TriangleAlert, title: "We could not find that" };
      case "server":
        return { Icon: CloudOff, title: "Zvingo had a problem" };
      default:
        return { Icon: TriangleAlert, title: "That did not work" };
    }
  }
  return { Icon: TriangleAlert, title: "That did not work" };
}

/**
 * DESIGN_SYSTEM §5.5 — say what happened in plain language and offer Retry.
 * A raw exception or HTTP status is never shown to a merchant.
 */
export function ErrorState({
  error,
  title,
  description,
  onRetry,
  retryLabel = "Try again",
  action,
  size = "md",
  className,
}: ErrorStateProps) {
  const { Icon, title: derivedTitle } = presentation(error);
  const [retrying, setRetrying] = React.useState(false);

  const message =
    description ??
    (isApiError(error)
      ? error.message
      : error instanceof Error && error.message
        ? error.message
        : "Something went wrong on our side. Your data is safe — please try again.");

  const handleRetry = async () => {
    if (!onRetry) return;
    setRetrying(true);
    try {
      await onRetry();
    } finally {
      setRetrying(false);
    }
  };

  return (
    <div
      role="alert"
      className={cn(
        "flex flex-col items-center justify-center px-6 text-center",
        size === "md" ? "py-16" : "py-10",
        className,
      )}
    >
      <span
        aria-hidden="true"
        className={cn(
          "flex items-center justify-center rounded-lg bg-error-surface text-error",
          size === "md" ? "h-14 w-14" : "h-11 w-11",
        )}
      >
        <Icon className={size === "md" ? "h-7 w-7" : "h-5 w-5"} />
      </span>
      <h3 className={cn("mt-4 text-neutral-900", size === "md" ? "type-h3" : "type-body-strong")}>
        {title ?? derivedTitle}
      </h3>
      <p className="type-caption mt-1.5 max-w-sm text-text-secondary">{message}</p>
      {(onRetry || action) && (
        <div className="mt-5 flex flex-col items-center gap-3 sm:flex-row">
          {onRetry && (
            <Button
              variant="primary"
              loading={retrying}
              onClick={handleRetry}
              leftIcon={<RefreshCw className="h-4 w-4" />}
            >
              {retryLabel}
            </Button>
          )}
          {action}
        </div>
      )}
    </div>
  );
}

/**
 * Inline variant for a failure inside a form or a card that already has a
 * heading — keeps the page layout instead of taking over the region.
 */
export function InlineError({
  error,
  onRetry,
  className,
}: {
  error?: unknown;
  onRetry?: () => void;
  className?: string;
}) {
  const message = isApiError(error)
    ? error.message
    : error instanceof Error && error.message
      ? error.message
      : "Something went wrong. Please try again.";

  return (
    <div
      role="alert"
      className={cn(
        "flex items-start gap-3 rounded-md border border-error/25 bg-error-surface px-4 py-3",
        className,
      )}
    >
      <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0 text-error" aria-hidden="true" />
      <p className="type-caption flex-1 text-neutral-800">{message}</p>
      {onRetry && (
        <Button variant="tertiary" size="sm" onClick={onRetry} className="-my-1 shrink-0">
          Retry
        </Button>
      )}
    </div>
  );
}
