import * as React from "react";
import { cn } from "@/lib/cn";

export interface SkeletonProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Shape preset. `text` gets a line height, `circle` is fully round. */
  shape?: "block" | "text" | "circle";
}

/**
 * DESIGN_SYSTEM §4.3 — any load expected over 300ms shows a shimmer skeleton
 * that matches the real content's layout. A bare full-screen spinner is a bug.
 */
export function Skeleton({ className, shape = "block", style, ...props }: SkeletonProps) {
  return (
    <div
      aria-hidden="true"
      style={style}
      className={cn(
        "zv-shimmer",
        shape === "circle" ? "rounded-full" : "rounded-sm",
        shape === "text" && "h-3.5 w-full",
        shape === "block" && "h-4 w-full",
        className,
      )}
      {...props}
    />
  );
}

/** A paragraph-shaped placeholder. The last line is deliberately short. */
export function SkeletonText({ lines = 3, className }: { lines?: number; className?: string }) {
  return (
    <div className={cn("flex flex-col gap-2", className)} aria-hidden="true">
      {Array.from({ length: lines }).map((_, index) => (
        <Skeleton key={index} shape="text" className={index === lines - 1 ? "w-2/3" : undefined} />
      ))}
    </div>
  );
}

/**
 * Wrap a loading region so assistive tech announces the wait without reading
 * the placeholder boxes.
 */
export function SkeletonRegion({
  label = "Loading",
  className,
  children,
}: {
  label?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div role="status" aria-live="polite" aria-busy="true" className={className}>
      <span className="zv-sr-only">{label}</span>
      {children}
    </div>
  );
}

/** Matches `StatCard`: eyebrow, big value, delta row. */
export function StatCardSkeleton({ className }: { className?: string }) {
  return (
    <div className={cn("rounded-lg border border-border bg-surface p-4 shadow-sm", className)}>
      <Skeleton className="h-3 w-24" />
      <Skeleton className="mt-3 h-8 w-32" />
      <Skeleton className="mt-3 h-3 w-20" />
    </div>
  );
}

/** Matches an order card: reference + status, two item lines, footer actions. */
export function OrderCardSkeleton({ className }: { className?: string }) {
  return (
    <div className={cn("rounded-lg border border-border bg-surface p-4 shadow-sm", className)}>
      <div className="flex items-center justify-between gap-3">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-6 w-20 rounded-full" />
      </div>
      <div className="mt-4 flex flex-col gap-2">
        <Skeleton shape="text" className="w-3/4" />
        <Skeleton shape="text" className="w-1/2" />
      </div>
      <div className="mt-4 flex items-center justify-between gap-3 border-t border-divider pt-3">
        <Skeleton className="h-4 w-16" />
        <div className="flex gap-2">
          <Skeleton className="h-10 w-24 rounded-md" />
          <Skeleton className="h-10 w-24 rounded-md" />
        </div>
      </div>
    </div>
  );
}

/** Matches a menu list row: thumbnail, name + description, price, switch. */
export function MenuRowSkeleton({ className }: { className?: string }) {
  return (
    <div className={cn("flex items-center gap-4 border-b border-divider px-4 py-3", className)}>
      <Skeleton className="h-14 w-14 shrink-0 rounded-md" />
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <Skeleton shape="text" className="w-40" />
        <Skeleton shape="text" className="w-64 max-w-full" />
      </div>
      <Skeleton className="h-4 w-14 shrink-0" />
      <Skeleton className="h-7 w-12 shrink-0 rounded-full" />
    </div>
  );
}

/** Rows shaped like the real table body — pass the same column count. */
export function TableRowsSkeleton({
  rows = 5,
  columns = 4,
  className,
}: {
  rows?: number;
  columns?: number;
  className?: string;
}) {
  return (
    <>
      {Array.from({ length: rows }).map((_, rowIndex) => (
        <tr key={rowIndex} className={cn("border-b border-divider", className)}>
          {Array.from({ length: columns }).map((__, columnIndex) => (
            <td key={columnIndex} className="px-4 py-3.5">
              <Skeleton
                shape="text"
                className={columnIndex === 0 ? "w-32" : columnIndex === columns - 1 ? "w-16" : "w-24"}
              />
            </td>
          ))}
        </tr>
      ))}
    </>
  );
}
