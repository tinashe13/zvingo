"use client";

import * as React from "react";
import { Minus, TrendingDown, TrendingUp, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/cn";
import { useCountUp } from "@/lib/hooks";
import { formatDuration, formatMoney, formatNumber } from "@/lib/format";
import { StatCardSkeleton } from "./Skeleton";

export type StatFormat = "number" | "money" | "duration" | "percent" | "raw";

export interface Sparkline {
  /** Oldest → newest. 2+ points required. */
  points: number[];
  /** Accessible summary, e.g. "Orders per day over the last 7 days". */
  label: string;
}

export interface StatCardProps {
  /** Short, literal label, e.g. "Orders today". */
  label: string;
  /** The number itself. Strings bypass the count-up animation. */
  value: number | string;
  format?: StatFormat;
  /** Currency code for `format="money"`. Defaults to USD. */
  currency?: string;
  /** Percentage change vs the comparison period. Negative renders as a fall. */
  delta?: number | null;
  /** Names the comparison, e.g. "vs yesterday". */
  deltaLabel?: string;
  /** Set when a fall is good (e.g. average prep time). Default false. */
  lowerIsBetter?: boolean;
  /** Leading icon in a tinted tile. */
  icon?: LucideIcon;
  /** One line of context under the value. */
  hint?: string;
  sparkline?: Sparkline;
  loading?: boolean;
  /** Makes the whole tile a link/button target. */
  onClick?: () => void;
  className?: string;
}

function SparklinePath({ points, label }: Sparkline) {
  const width = 96;
  const height = 28;
  if (points.length < 2) return null;

  const min = Math.min(...points);
  const max = Math.max(...points);
  const span = max - min || 1;
  const step = width / (points.length - 1);

  const coords = points.map((point, index) => {
    const x = index * step;
    const y = height - ((point - min) / span) * (height - 4) - 2;
    return `${x.toFixed(2)},${y.toFixed(2)}`;
  });

  const rising = points[points.length - 1]! >= points[0]!;

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      width={width}
      height={height}
      role="img"
      aria-label={label}
      className="shrink-0 overflow-visible"
      preserveAspectRatio="none"
    >
      <polyline
        points={coords.join(" ")}
        fill="none"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        className={rising ? "stroke-success" : "stroke-neutral-400"}
      />
    </svg>
  );
}

/**
 * A KPI tile: label, a big tabular-figure value that counts up when it
 * changes (§4.3), a direction-marked delta and an optional sparkline.
 */
export function StatCard({
  label,
  value,
  format = "number",
  currency,
  delta,
  deltaLabel,
  lowerIsBetter = false,
  icon: Icon,
  hint,
  sparkline,
  loading,
  onClick,
  className,
}: StatCardProps) {
  const numericValue = typeof value === "number" ? value : 0;
  const animated = useCountUp(numericValue, 260);

  if (loading) return <StatCardSkeleton className={className} />;

  const display =
    typeof value === "string"
      ? value
      : format === "money"
        ? formatMoney(animated, { currency })
        : format === "duration"
          ? formatDuration(animated)
          : format === "percent"
            ? `${formatNumber(animated, 1)}%`
            : formatNumber(Math.round(animated));

  const hasDelta = delta !== null && delta !== undefined && Number.isFinite(delta);
  const flat = hasDelta && Math.abs(delta) < 0.05;
  const rising = hasDelta && delta > 0;
  const good = flat ? null : lowerIsBetter ? !rising : rising;
  const DeltaIcon = flat ? Minus : rising ? TrendingUp : TrendingDown;

  const Tag = onClick ? "button" : "div";

  return (
    <Tag
      {...(onClick ? { type: "button" as const, onClick } : {})}
      className={cn(
        "flex w-full flex-col gap-3 rounded-lg border border-border bg-surface p-4 text-left shadow-sm",
        onClick &&
          "cursor-pointer transition-shadow hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action",
        className,
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <p className="type-overline text-text-secondary">{label}</p>
        {Icon && (
          <span
            aria-hidden="true"
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-sm bg-neutral-100 text-neutral-700"
          >
            <Icon className="h-4 w-4" />
          </span>
        )}
      </div>

      <div className="flex items-end justify-between gap-3">
        <p className="type-display tabular-figures text-neutral-900">{display}</p>
        {sparkline && sparkline.points.length > 1 && <SparklinePath {...sparkline} />}
      </div>

      {(hasDelta || hint) && (
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
          {hasDelta && (
            <span
              className={cn(
                "inline-flex items-center gap-1 type-caption font-bold tabular-figures",
                good === null ? "text-text-secondary" : good ? "text-success" : "text-error",
              )}
            >
              <DeltaIcon className="h-3.5 w-3.5" aria-hidden="true" />
              {delta > 0 ? "+" : ""}
              {Math.abs(delta) >= 10 ? Math.round(delta) : Math.round(delta * 10) / 10}%
              <span className="zv-sr-only">
                {flat ? "no change" : rising ? "increase" : "decrease"}
              </span>
            </span>
          )}
          {(deltaLabel || hint) && (
            <span className="type-caption text-text-tertiary">{deltaLabel ?? hint}</span>
          )}
        </div>
      )}
    </Tag>
  );
}
