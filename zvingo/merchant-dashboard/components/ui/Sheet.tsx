"use client";

import * as React from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { cn } from "@/lib/cn";
import { IconButton } from "./Button";
import { useEscapeKey, useFocusTrap, useIsMounted, useLockBodyScroll } from "@/lib/hooks";

export type SheetSide = "right" | "left";

export interface SheetProps {
  open: boolean;
  onClose: () => void;
  /** Names the panel for screen readers. Required. */
  title: string;
  description?: React.ReactNode;
  children?: React.ReactNode;
  /** Sticky action row pinned to the bottom of the panel. */
  footer?: React.ReactNode;
  side?: SheetSide;
  /** Panel width at ≥768px. Below that the sheet is full-width. */
  width?: "sm" | "md" | "lg";
  className?: string;
  /** Extra controls next to the close button, e.g. a "Print" icon button. */
  headerActions?: React.ReactNode;
}

const WIDTH: Record<NonNullable<SheetProps["width"]>, string> = {
  sm: "md:max-w-md",
  md: "md:max-w-xl",
  lg: "md:max-w-2xl",
};

/**
 * Side panel for a detail view. Keeps the list behind it on screen so a shift
 * manager never loses their place — the dashboard equivalent of a bottom sheet.
 */
export function Sheet({
  open,
  onClose,
  title,
  description,
  children,
  footer,
  side = "right",
  width = "md",
  className,
  headerActions,
}: SheetProps) {
  const mounted = useIsMounted();
  const panelRef = React.useRef<HTMLDivElement>(null);
  const reactId = React.useId();
  const titleId = `sheet-title-${reactId}`;
  const descriptionId = `sheet-description-${reactId}`;

  useLockBodyScroll(open);
  useFocusTrap(panelRef, open);
  useEscapeKey(onClose, open);

  if (!mounted || !open) return null;

  return createPortal(
    <div className="fixed inset-0 z-50" role="presentation">
      <div
        className="zv-fade absolute inset-0 bg-neutral-900/45"
        onClick={onClose}
        aria-hidden="true"
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={description ? descriptionId : undefined}
        className={cn(
          "absolute inset-y-0 flex w-full flex-col bg-surface shadow-lg",
          WIDTH[width],
          side === "right" ? "right-0 zv-sheet-right" : "left-0 zv-sheet-left",
          className,
        )}
      >
        <div className="flex items-start justify-between gap-3 border-b border-divider px-5 py-4">
          <div className="min-w-0">
            <h2 id={titleId} className="type-h2 truncate text-neutral-900">
              {title}
            </h2>
            {description && (
              <p id={descriptionId} className="type-caption mt-1 text-text-secondary">
                {description}
              </p>
            )}
          </div>
          <div className="flex shrink-0 items-center gap-2">
            {headerActions}
            <IconButton label="Close panel" icon={<X className="h-4 w-4" />} onClick={onClose} />
          </div>
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-5">{children}</div>

        {footer && (
          <div className="flex flex-wrap items-center justify-end gap-3 border-t border-divider px-5 py-4 shadow-dock">
            {footer}
          </div>
        )}
      </div>
    </div>,
    document.body,
  );
}

export { Sheet as Drawer };
