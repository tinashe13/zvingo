"use client";

import * as React from "react";
import { cn } from "@/lib/cn";

export interface TabItem<T extends string = string> {
  value: T;
  label: string;
  /** Small lucide icon before the label. */
  icon?: React.ReactNode;
  /** Count shown as a pill after the label, e.g. open orders in that lane. */
  count?: number;
  /** Draws attention without colour alone — pairs with the count. */
  urgent?: boolean;
  disabled?: boolean;
}

export interface TabsProps<T extends string = string> {
  items: Array<TabItem<T>>;
  value: T;
  onValueChange: (value: T) => void;
  /** Names the tab list for screen readers. */
  label: string;
  /** `line` for page sections, `segmented` for a compact filter control. */
  variant?: "line" | "segmented";
  /** Stretch the tabs to fill the row. */
  fill?: boolean;
  className?: string;
  /** id prefix used to link tabs to their panels. */
  idPrefix?: string;
}

/**
 * Keyboard-complete tabs (arrow keys, Home/End) with roving tabindex. Pair
 * each tab with a `<TabPanel>` so the relationship is announced.
 */
export function Tabs<T extends string = string>({
  items,
  value,
  onValueChange,
  label,
  variant = "line",
  fill,
  className,
  idPrefix,
}: TabsProps<T>) {
  const reactId = React.useId();
  const prefix = idPrefix ?? `tabs-${reactId}`;
  const listRef = React.useRef<HTMLDivElement>(null);

  const move = (direction: 1 | -1 | "first" | "last") => {
    const enabled = items.filter((item) => !item.disabled);
    if (!enabled.length) return;
    const currentIndex = enabled.findIndex((item) => item.value === value);
    let nextIndex: number;
    if (direction === "first") nextIndex = 0;
    else if (direction === "last") nextIndex = enabled.length - 1;
    else nextIndex = (currentIndex + direction + enabled.length) % enabled.length;
    const next = enabled[nextIndex];
    if (!next) return;
    onValueChange(next.value);
    requestAnimationFrame(() => {
      listRef.current
        ?.querySelector<HTMLButtonElement>(`#${CSS.escape(`${prefix}-tab-${next.value}`)}`)
        ?.focus();
    });
  };

  return (
    <div
      ref={listRef}
      role="tablist"
      aria-label={label}
      onKeyDown={(event) => {
        if (event.key === "ArrowRight") {
          event.preventDefault();
          move(1);
        } else if (event.key === "ArrowLeft") {
          event.preventDefault();
          move(-1);
        } else if (event.key === "Home") {
          event.preventDefault();
          move("first");
        } else if (event.key === "End") {
          event.preventDefault();
          move("last");
        }
      }}
      className={cn(
        "zv-no-scrollbar flex items-center gap-1 overflow-x-auto",
        variant === "line" && "border-b border-divider",
        variant === "segmented" && "rounded-md bg-neutral-100 p-1",
        fill && "w-full [&>button]:flex-1",
        className,
      )}
    >
      {items.map((item) => {
        const selected = item.value === value;
        return (
          <button
            key={item.value}
            id={`${prefix}-tab-${item.value}`}
            type="button"
            role="tab"
            aria-selected={selected}
            aria-controls={`${prefix}-panel-${item.value}`}
            tabIndex={selected ? 0 : -1}
            disabled={item.disabled}
            onClick={() => onValueChange(item.value)}
            className={cn(
              "relative inline-flex min-h-11 shrink-0 items-center justify-center gap-2 whitespace-nowrap px-4 type-button transition-colors",
              "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-action",
              "disabled:cursor-not-allowed disabled:text-action-disabled-fg",
              variant === "line" &&
                cn(
                  "-mb-px border-b-2",
                  selected
                    ? "border-action text-neutral-900"
                    : "border-transparent text-text-secondary hover:text-neutral-900",
                ),
              variant === "segmented" &&
                cn(
                  "rounded-sm",
                  selected
                    ? "bg-surface text-neutral-900 shadow-sm"
                    : "text-text-secondary hover:text-neutral-900",
                ),
            )}
          >
            {item.icon && (
              <span className="flex shrink-0 items-center [&_svg]:h-4 [&_svg]:w-4" aria-hidden="true">
                {item.icon}
              </span>
            )}
            {item.label}
            {item.count !== undefined && (
              <span
                className={cn(
                  "inline-flex min-w-5 items-center justify-center rounded-full px-1.5 py-0.5 text-overline tabular-figures",
                  item.urgent && item.count > 0
                    ? "bg-error text-neutral-0"
                    : selected
                      ? "bg-neutral-900 text-neutral-0"
                      : "bg-neutral-200 text-neutral-700",
                )}
              >
                {item.count}
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}

export interface TabPanelProps extends React.HTMLAttributes<HTMLDivElement> {
  value: string;
  activeValue: string;
  idPrefix: string;
}

/** The content region for one tab. Renders nothing when its tab is not active. */
export function TabPanel({ value, activeValue, idPrefix, className, ...props }: TabPanelProps) {
  if (value !== activeValue) return null;
  return (
    <div
      role="tabpanel"
      id={`${idPrefix}-panel-${value}`}
      aria-labelledby={`${idPrefix}-tab-${value}`}
      tabIndex={0}
      className={cn("zv-fade focus-visible:outline-none", className)}
      {...props}
    />
  );
}
