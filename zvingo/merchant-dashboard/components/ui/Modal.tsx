"use client";

import * as React from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { cn } from "@/lib/cn";
import { IconButton } from "./Button";
import { useEscapeKey, useFocusTrap, useIsMounted, useLockBodyScroll } from "@/lib/hooks";

export type ModalSize = "sm" | "md" | "lg" | "xl";

const SIZE_CLASSES: Record<ModalSize, string> = {
  sm: "max-w-md",
  md: "max-w-xl",
  lg: "max-w-3xl",
  xl: "max-w-5xl",
};

export interface ModalProps {
  open: boolean;
  /** Called on Escape, scrim click and the close button. */
  onClose: () => void;
  /** Names the dialog for screen readers. Required. */
  title: string;
  description?: React.ReactNode;
  children?: React.ReactNode;
  /** Sticky action row. Put the single primary action last. */
  footer?: React.ReactNode;
  size?: ModalSize;
  /** Hide the × button when the dialog must be resolved by its actions. */
  hideCloseButton?: boolean;
  /**
   * Block Escape and scrim dismissal. Use only for a destructive confirm or an
   * in-flight save — never to trap a user.
   */
  dismissible?: boolean;
  className?: string;
}

/**
 * Accessible dialog: focus is trapped while open, Escape and a scrim click
 * close it, and focus returns to whatever opened it (WCAG 2.4.3).
 */
export function Modal({
  open,
  onClose,
  title,
  description,
  children,
  footer,
  size = "md",
  hideCloseButton,
  dismissible = true,
  className,
}: ModalProps) {
  const mounted = useIsMounted();
  const panelRef = React.useRef<HTMLDivElement>(null);
  const reactId = React.useId();
  const titleId = `modal-title-${reactId}`;
  const descriptionId = `modal-description-${reactId}`;

  useLockBodyScroll(open);
  useFocusTrap(panelRef, open);
  useEscapeKey(() => dismissible && onClose(), open);

  if (!mounted || !open) return null;

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-4"
      role="presentation"
    >
      <div
        className="zv-fade absolute inset-0 bg-neutral-900/55 backdrop-blur-[2px]"
        onClick={() => dismissible && onClose()}
        aria-hidden="true"
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={description ? descriptionId : undefined}
        className={cn(
          "zv-modal-in relative flex max-h-[92vh] w-full flex-col overflow-hidden bg-surface shadow-lg",
          "rounded-t-xl sm:rounded-xl",
          SIZE_CLASSES[size],
          className,
        )}
      >
        <div className="flex items-start justify-between gap-4 border-b border-divider px-5 py-4">
          <div className="min-w-0">
            <h2 id={titleId} className="type-h2 text-neutral-900">
              {title}
            </h2>
            {description && (
              <p id={descriptionId} className="type-caption mt-1 text-text-secondary">
                {description}
              </p>
            )}
          </div>
          {!hideCloseButton && (
            <IconButton
              label="Close"
              icon={<X className="h-4 w-4" />}
              onClick={onClose}
              className="-mr-1 shrink-0"
            />
          )}
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-5">{children}</div>

        {footer && (
          <div className="flex flex-wrap items-center justify-end gap-3 border-t border-divider bg-surface px-5 py-4">
            {footer}
          </div>
        )}
      </div>
    </div>,
    document.body,
  );
}

export { Modal as Dialog };
