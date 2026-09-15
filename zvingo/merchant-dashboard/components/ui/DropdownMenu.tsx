"use client";

import * as React from "react";
import { cn } from "@/lib/cn";
import { useEscapeKey, useOnClickOutside } from "@/lib/hooks";

export interface DropdownMenuItem {
  /** Stable id; also used as the React key. */
  id: string;
  label: React.ReactNode;
  icon?: React.ReactNode;
  onSelect?: () => void;
  /** Renders in the destructive tone and is announced as such. */
  destructive?: boolean;
  disabled?: boolean;
  /** Secondary line under the label. */
  description?: string;
  /** Draws a divider above this item. */
  separatorBefore?: boolean;
}

export interface DropdownMenuProps {
  /** The control that opens the menu. Gets the aria wiring automatically. */
  trigger: React.ReactElement;
  items: DropdownMenuItem[];
  /** Names the menu for screen readers, e.g. "Order actions". */
  label: string;
  align?: "start" | "end";
  /** Optional heading rendered at the top of the menu. */
  heading?: string;
  className?: string;
}

/**
 * Keyboard-complete menu: ArrowUp/Down move, Home/End jump, Enter/Space
 * select, Escape closes and returns focus to the trigger.
 */
export function DropdownMenu({
  trigger,
  items,
  label,
  align = "end",
  heading,
  className,
}: DropdownMenuProps) {
  const [open, setOpen] = React.useState(false);
  const [activeIndex, setActiveIndex] = React.useState(0);
  const rootRef = React.useRef<HTMLDivElement>(null);
  const itemRefs = React.useRef<Array<HTMLButtonElement | null>>([]);
  const reactId = React.useId();
  const menuId = `menu-${reactId}`;

  // The trigger is found through the wrapper rather than by cloning a ref onto
  // it, so any element (Button, a plain button, a link) can be a trigger.
  const focusTrigger = React.useCallback(() => {
    rootRef.current
      ?.querySelector<HTMLElement>(':scope > button, :scope > [role="button"], :scope > a')
      ?.focus();
  }, []);

  const enabledIndexes = React.useMemo(
    () => items.map((item, index) => (item.disabled ? -1 : index)).filter((i) => i >= 0),
    [items],
  );

  const close = React.useCallback(
    (returnFocus = true) => {
      setOpen(false);
      if (returnFocus) focusTrigger();
    },
    [focusTrigger],
  );

  useOnClickOutside([rootRef], () => setOpen(false), open);
  useEscapeKey(() => close(), open);

  React.useEffect(() => {
    if (!open) return;
    const first = enabledIndexes[0] ?? 0;
    setActiveIndex(first);
    requestAnimationFrame(() => itemRefs.current[first]?.focus());
  }, [open, enabledIndexes]);

  const moveActive = (direction: 1 | -1 | "first" | "last") => {
    if (!enabledIndexes.length) return;
    const position = enabledIndexes.indexOf(activeIndex);
    let nextPosition: number;
    if (direction === "first") nextPosition = 0;
    else if (direction === "last") nextPosition = enabledIndexes.length - 1;
    else nextPosition = (position + direction + enabledIndexes.length) % enabledIndexes.length;
    const nextIndex = enabledIndexes[nextPosition]!;
    setActiveIndex(nextIndex);
    itemRefs.current[nextIndex]?.focus();
  };

  const triggerElement = React.cloneElement(trigger, {
    "aria-haspopup": "menu",
    "aria-expanded": open,
    "aria-controls": open ? menuId : undefined,
    onClick: (event: React.MouseEvent) => {
      (trigger.props as { onClick?: (e: React.MouseEvent) => void }).onClick?.(event);
      setOpen((current) => !current);
    },
    onKeyDown: (event: React.KeyboardEvent) => {
      (trigger.props as { onKeyDown?: (e: React.KeyboardEvent) => void }).onKeyDown?.(event);
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        setOpen(true);
      }
    },
  } as React.HTMLAttributes<HTMLElement>);

  return (
    <div ref={rootRef} className="relative inline-flex">
      {triggerElement}

      {open && (
        <div
          id={menuId}
          role="menu"
          aria-label={label}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") {
              event.preventDefault();
              moveActive(1);
            } else if (event.key === "ArrowUp") {
              event.preventDefault();
              moveActive(-1);
            } else if (event.key === "Home") {
              event.preventDefault();
              moveActive("first");
            } else if (event.key === "End") {
              event.preventDefault();
              moveActive("last");
            } else if (event.key === "Tab") {
              setOpen(false);
            }
          }}
          className={cn(
            "zv-fade absolute top-full z-40 mt-2 min-w-56 overflow-hidden rounded-md border border-border bg-surface py-1 shadow-md",
            align === "end" ? "right-0" : "left-0",
            className,
          )}
        >
          {heading && (
            <p className="px-3 pb-1 pt-2 type-overline text-text-tertiary">{heading}</p>
          )}
          {items.map((item, index) => (
            <React.Fragment key={item.id}>
              {item.separatorBefore && <div className="my-1 h-px bg-divider" role="separator" />}
              <button
                ref={(node) => {
                  itemRefs.current[index] = node;
                }}
                type="button"
                role="menuitem"
                disabled={item.disabled}
                tabIndex={index === activeIndex ? 0 : -1}
                onClick={() => {
                  if (item.disabled) return;
                  close(false);
                  item.onSelect?.();
                }}
                className={cn(
                  "flex w-full min-h-11 items-center gap-3 px-3 py-2 text-left type-body transition-colors",
                  "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-action",
                  item.destructive
                    ? "text-error hover:bg-error-surface"
                    : "text-neutral-800 hover:bg-neutral-100",
                  item.disabled && "cursor-not-allowed text-action-disabled-fg hover:bg-transparent",
                )}
              >
                {item.icon && (
                  <span className="flex shrink-0 items-center [&_svg]:h-4 [&_svg]:w-4" aria-hidden="true">
                    {item.icon}
                  </span>
                )}
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-semibold">{item.label}</span>
                  {item.description && (
                    <span className="block truncate type-caption text-text-secondary">
                      {item.description}
                    </span>
                  )}
                </span>
              </button>
            </React.Fragment>
          ))}
        </div>
      )}
    </div>
  );
}
