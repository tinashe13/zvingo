"use client";

import * as React from "react";
import { createPortal } from "react-dom";
import { AlertTriangle, CheckCircle2, Info, Undo2, X, XCircle } from "lucide-react";
import { cn } from "@/lib/cn";
import { useIsMounted, usePrefersReducedMotion } from "@/lib/hooks";

export type ToastTone = "success" | "error" | "info" | "warning";

export interface ToastAction {
  label: string;
  onClick: () => void | Promise<unknown>;
}

export interface ToastOptions {
  /** One short sentence. This is the part people actually read. */
  title: string;
  /** Optional second line with the detail. */
  description?: string;
  tone?: ToastTone;
  /** ms before auto-dismiss. 0 keeps it until dismissed. Errors default to 8s. */
  duration?: number;
  /** Trailing action, e.g. "View order". */
  action?: ToastAction;
  /**
   * Shorthand for a reversible mutation (§5.5). Renders an "Undo" button and
   * gives the toast a longer life so there is time to hit it.
   */
  onUndo?: () => void | Promise<unknown>;
  /** Replaces an existing toast with the same id instead of stacking. */
  id?: string;
}

interface ToastRecord extends ToastOptions {
  id: string;
  tone: ToastTone;
  duration: number;
  createdAt: number;
}

export interface ToastApi {
  toast: (options: ToastOptions) => string;
  success: (title: string, options?: Omit<ToastOptions, "title" | "tone">) => string;
  error: (title: string, options?: Omit<ToastOptions, "title" | "tone">) => string;
  info: (title: string, options?: Omit<ToastOptions, "title" | "tone">) => string;
  warning: (title: string, options?: Omit<ToastOptions, "title" | "tone">) => string;
  dismiss: (id: string) => void;
  dismissAll: () => void;
}

const ToastContext = React.createContext<ToastApi | null>(null);

/** Access the toast queue. Must be used inside `<ToastProvider>`. */
export function useToast(): ToastApi {
  const context = React.useContext(ToastContext);
  if (!context) {
    throw new Error("useToast must be used inside <ToastProvider>. Add it to the app shell.");
  }
  return context;
}

/**
 * Toast api when one is available, `null` otherwise. For shared components
 * that may render outside `<ToastProvider>` (e.g. inside a legacy layout).
 */
export function useOptionalToast(): ToastApi | null {
  return React.useContext(ToastContext);
}

const DEFAULT_DURATION: Record<ToastTone, number> = {
  success: 4_000,
  info: 5_000,
  warning: 6_000,
  error: 8_000,
};

const TONE_STYLES: Record<ToastTone, { Icon: typeof CheckCircle2; icon: string; bar: string }> = {
  success: { Icon: CheckCircle2, icon: "text-success", bar: "bg-success" },
  error: { Icon: XCircle, icon: "text-error", bar: "bg-error" },
  warning: { Icon: AlertTriangle, icon: "text-warning", bar: "bg-warning" },
  info: { Icon: Info, icon: "text-info", bar: "bg-info" },
};

export interface ToastProviderProps {
  children: React.ReactNode;
  /** Maximum toasts on screen. Older ones drop off the top. Default 4. */
  max?: number;
}

/**
 * Toast queue with `aria-live` announcements, stacking, an Undo slot and a
 * progress bar that pauses while the pointer or keyboard focus is on the toast.
 */
export function ToastProvider({ children, max = 4 }: ToastProviderProps) {
  const [toasts, setToasts] = React.useState<ToastRecord[]>([]);
  const mounted = useIsMounted();
  const counter = React.useRef(0);

  const dismiss = React.useCallback((id: string) => {
    setToasts((current) => current.filter((item) => item.id !== id));
  }, []);

  const dismissAll = React.useCallback(() => setToasts([]), []);

  const toast = React.useCallback(
    (options: ToastOptions) => {
      counter.current += 1;
      const tone = options.tone ?? "info";
      const id = options.id ?? `toast-${counter.current}`;
      const record: ToastRecord = {
        ...options,
        id,
        tone,
        duration: options.duration ?? (options.onUndo ? 8_000 : DEFAULT_DURATION[tone]),
        createdAt: Date.now(),
      };
      setToasts((current) => {
        const withoutDuplicate = current.filter((item) => item.id !== id);
        return [...withoutDuplicate, record].slice(-max);
      });
      return id;
    },
    [max],
  );

  const api = React.useMemo<ToastApi>(
    () => ({
      toast,
      success: (title, options) => toast({ ...options, title, tone: "success" }),
      error: (title, options) => toast({ ...options, title, tone: "error" }),
      info: (title, options) => toast({ ...options, title, tone: "info" }),
      warning: (title, options) => toast({ ...options, title, tone: "warning" }),
      dismiss,
      dismissAll,
    }),
    [toast, dismiss, dismissAll],
  );

  return (
    <ToastContext.Provider value={api}>
      {children}
      {mounted &&
        createPortal(
          <div
            className="pointer-events-none fixed inset-x-0 bottom-0 z-[60] flex flex-col items-center gap-2 p-4 sm:inset-x-auto sm:right-0 sm:items-end"
            aria-label="Notifications"
          >
            {/* Polite channel: success / info / warning. */}
            <div aria-live="polite" aria-atomic="false" className="contents">
              {toasts
                .filter((item) => item.tone !== "error")
                .map((item) => (
                  <ToastCard key={item.id} toast={item} onDismiss={dismiss} />
                ))}
            </div>
            {/* Assertive channel: failures interrupt, because they cost money. */}
            <div aria-live="assertive" aria-atomic="false" className="contents">
              {toasts
                .filter((item) => item.tone === "error")
                .map((item) => (
                  <ToastCard key={item.id} toast={item} onDismiss={dismiss} />
                ))}
            </div>
          </div>,
          document.body,
        )}
    </ToastContext.Provider>
  );
}

function ToastCard({
  toast,
  onDismiss,
}: {
  toast: ToastRecord;
  onDismiss: (id: string) => void;
}) {
  const { Icon, icon, bar } = TONE_STYLES[toast.tone];
  const reducedMotion = usePrefersReducedMotion();
  const [paused, setPaused] = React.useState(false);
  const [busy, setBusy] = React.useState(false);
  const remainingRef = React.useRef(toast.duration);
  const startedRef = React.useRef(Date.now());

  // Auto-dismiss that genuinely pauses — the timer is rebuilt from the
  // remaining time each time the pointer enters or leaves.
  React.useEffect(() => {
    if (toast.duration <= 0 || paused || busy) return;
    startedRef.current = Date.now();
    const id = window.setTimeout(() => onDismiss(toast.id), remainingRef.current);
    return () => {
      window.clearTimeout(id);
      remainingRef.current = Math.max(0, remainingRef.current - (Date.now() - startedRef.current));
    };
  }, [toast.duration, toast.id, paused, busy, onDismiss]);

  const runAction = async (handler: () => void | Promise<unknown>) => {
    setBusy(true);
    try {
      await handler();
      onDismiss(toast.id);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      role={toast.tone === "error" ? "alert" : "status"}
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      onFocusCapture={() => setPaused(true)}
      onBlurCapture={() => setPaused(false)}
      className={cn(
        "zv-toast-in pointer-events-auto relative w-full max-w-sm overflow-hidden rounded-md border border-border bg-surface shadow-md",
      )}
    >
      <div className="flex items-start gap-3 p-4">
        <Icon className={cn("mt-0.5 h-5 w-5 shrink-0", icon)} aria-hidden="true" />
        <div className="min-w-0 flex-1">
          <p className="type-body font-semibold text-neutral-900">{toast.title}</p>
          {toast.description && (
            <p className="type-caption mt-0.5 text-text-secondary">{toast.description}</p>
          )}
          {(toast.onUndo || toast.action) && (
            <div className="mt-2.5 flex flex-wrap items-center gap-2">
              {toast.onUndo && (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => runAction(toast.onUndo!)}
                  className="zv-touch inline-flex min-h-9 items-center gap-1.5 rounded-sm bg-neutral-100 px-3 type-caption font-bold text-neutral-900 transition-colors hover:bg-neutral-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action disabled:opacity-60"
                >
                  <Undo2 className="h-3.5 w-3.5" aria-hidden="true" />
                  Undo
                </button>
              )}
              {toast.action && (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => runAction(toast.action!.onClick)}
                  className="zv-touch inline-flex min-h-9 items-center rounded-sm px-2 type-caption font-bold text-neutral-900 underline decoration-neutral-300 underline-offset-4 transition-colors hover:decoration-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action disabled:opacity-60"
                >
                  {toast.action.label}
                </button>
              )}
            </div>
          )}
        </div>
        <button
          type="button"
          onClick={() => onDismiss(toast.id)}
          aria-label="Dismiss notification"
          className="zv-touch -mr-1 -mt-1 flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-text-tertiary transition-colors hover:bg-neutral-100 hover:text-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
        >
          <X className="h-4 w-4" aria-hidden="true" />
        </button>
      </div>

      {toast.duration > 0 && !reducedMotion && (
        <span
          aria-hidden="true"
          className={cn("zv-toast-progress absolute inset-x-0 bottom-0 h-0.5 origin-left", bar)}
          style={{
            animationDuration: `${toast.duration}ms`,
            animationPlayState: paused || busy ? "paused" : "running",
          }}
        />
      )}
    </div>
  );
}
