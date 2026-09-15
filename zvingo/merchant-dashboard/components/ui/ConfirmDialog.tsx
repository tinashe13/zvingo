"use client";

import * as React from "react";
import { AlertTriangle, Info, TriangleAlert } from "lucide-react";
import { cn } from "@/lib/cn";
import { Button } from "./Button";
import { Modal } from "./Modal";

export interface ConfirmDialogProps {
  open: boolean;
  onCancel: () => void;
  onConfirm: () => void | Promise<unknown>;
  /** Ask the question, e.g. "Cancel order #A93F21?" */
  title: string;
  /**
   * Name the consequence in plain language (§5.4):
   * "The customer will be refunded $12.50 within 3 days and told you could not
   * prepare the order." Never "Are you sure?".
   */
  consequence: string;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: "destructive" | "warning" | "info";
  /** Extra content between the consequence and the actions (e.g. a reason select). */
  children?: React.ReactNode;
  /** Disable the confirm button, e.g. until a required reason is chosen. */
  confirmDisabled?: boolean;
}

const TONE: Record<
  NonNullable<ConfirmDialogProps["tone"]>,
  { Icon: typeof AlertTriangle; wrap: string; button: "destructive" | "primary" }
> = {
  destructive: { Icon: TriangleAlert, wrap: "bg-error-surface text-error", button: "destructive" },
  warning: { Icon: AlertTriangle, wrap: "bg-warning-surface text-warning", button: "primary" },
  info: { Icon: Info, wrap: "bg-info-surface text-info", button: "primary" },
};

/**
 * DESIGN_SYSTEM §5.4 — a destructive or irreversible action is confirmed in a
 * dialog that names the consequence. The dialog cannot be dismissed by scrim
 * or Escape while the action is running.
 */
export function ConfirmDialog({
  open,
  onCancel,
  onConfirm,
  title,
  consequence,
  confirmLabel = "Confirm",
  cancelLabel = "Keep it",
  tone = "destructive",
  children,
  confirmDisabled,
}: ConfirmDialogProps) {
  const [busy, setBusy] = React.useState(false);
  const { Icon, wrap, button } = TONE[tone];

  const handleConfirm = async () => {
    setBusy(true);
    try {
      await onConfirm();
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={busy ? () => undefined : onCancel}
      title={title}
      size="sm"
      hideCloseButton
      dismissible={!busy}
      footer={
        <>
          <Button variant="secondary" onClick={onCancel} disabled={busy}>
            {cancelLabel}
          </Button>
          <Button
            variant={button}
            onClick={handleConfirm}
            loading={busy}
            disabled={confirmDisabled}
            data-autofocus
          >
            {confirmLabel}
          </Button>
        </>
      }
    >
      <div className="flex gap-4">
        <span
          aria-hidden="true"
          className={cn("flex h-11 w-11 shrink-0 items-center justify-center rounded-md", wrap)}
        >
          <Icon className="h-5 w-5" />
        </span>
        <div className="min-w-0 flex-1">
          <p className="type-body text-neutral-800">{consequence}</p>
          {children && <div className="mt-4">{children}</div>}
        </div>
      </div>
    </Modal>
  );
}

export interface UseConfirmResult {
  /** Spread onto `<ConfirmDialog {...dialogProps} />`. */
  dialogProps: Pick<ConfirmDialogProps, "open" | "onCancel" | "onConfirm">;
  /** Open the dialog for a specific action. */
  request: (action: () => void | Promise<unknown>) => void;
  isOpen: boolean;
}

/** Small helper so a page can reuse one `ConfirmDialog` for many rows. */
export function useConfirm(): UseConfirmResult {
  const [pending, setPending] = React.useState<null | (() => void | Promise<unknown>)>(null);

  return {
    isOpen: pending !== null,
    request: (action) => setPending(() => action),
    dialogProps: {
      open: pending !== null,
      onCancel: () => setPending(null),
      onConfirm: async () => {
        const action = pending;
        setPending(null);
        if (action) await action();
      },
    },
  };
}
