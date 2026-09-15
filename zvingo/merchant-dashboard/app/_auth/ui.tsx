"use client";

import * as React from "react";
import { AlertCircle, CheckCircle2, Clock, Eye, EyeOff, Info } from "lucide-react";
import { Input, type InputProps } from "@/components/ui";
import { cn } from "@/lib/cn";
import { formatPhone, toE164 } from "@/lib/format";
import { assessPassword, formatCountdown, PASSWORD_MIN_LENGTH } from "./session";

/* -------------------------------------------------------------------------- */
/* Banners                                                                    */
/* -------------------------------------------------------------------------- */

export type BannerTone = "error" | "info" | "success" | "warning";

const BANNER_STYLE: Record<BannerTone, { wrapper: string; icon: typeof Info }> = {
  error: { wrapper: "border-error/30 bg-error-surface text-error", icon: AlertCircle },
  info: { wrapper: "border-info/25 bg-info-surface text-info", icon: Info },
  success: { wrapper: "border-success/25 bg-success-surface text-success", icon: CheckCircle2 },
  warning: { wrapper: "border-warning/25 bg-warning-surface text-warning", icon: Clock },
};

/**
 * Form-level message. Colour is always paired with an icon and words (§1.5),
 * and errors announce themselves assertively so a screen reader user is not
 * left wondering why nothing happened.
 */
export function FormBanner({
  tone,
  title,
  children,
  action,
}: {
  tone: BannerTone;
  title: string;
  children?: React.ReactNode;
  action?: React.ReactNode;
}) {
  const { wrapper, icon: Icon } = BANNER_STYLE[tone];
  return (
    <div
      role={tone === "error" ? "alert" : "status"}
      aria-live={tone === "error" ? "assertive" : "polite"}
      className={cn("zv-enter flex gap-3 rounded-md border p-4", wrapper)}
    >
      <Icon className="mt-0.5 h-[18px] w-[18px] shrink-0" aria-hidden="true" />
      <div className="min-w-0 flex-1">
        <p className="type-body-strong">{title}</p>
        {children && <div className="mt-1 type-caption font-normal text-text-secondary">{children}</div>}
        {action && <div className="mt-3">{action}</div>}
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Rate limiting                                                              */
/* -------------------------------------------------------------------------- */

/**
 * Ticking "try again in 1m 12s" for a 429. Returns 0 once the wait is over,
 * so a screen can re-enable its submit button without a reload.
 */
export function useRetryCountdown(startSeconds: number | null | undefined): number {
  const [remaining, setRemaining] = React.useState(() => Math.max(0, Math.ceil(startSeconds ?? 0)));

  React.useEffect(() => {
    setRemaining(Math.max(0, Math.ceil(startSeconds ?? 0)));
  }, [startSeconds]);

  React.useEffect(() => {
    if (remaining <= 0) return;
    const timer = window.setInterval(() => {
      setRemaining((value) => (value <= 1 ? 0 : value - 1));
    }, 1000);
    return () => window.clearInterval(timer);
  }, [remaining]);

  return remaining;
}

/** Non-alarming 429 notice: what happened, why, and exactly when to retry. */
export function RateLimitNotice({ seconds, what }: { seconds: number; what: string }) {
  return (
    <FormBanner tone="warning" title="Let’s slow down for a moment">
      Zvingo limits how often {what} can be attempted from one device, which is what keeps other people
      out of your account.{" "}
      {seconds > 0 ? (
        <>
          You can try again in{" "}
          <span className="tabular-figures font-semibold text-neutral-900">{formatCountdown(seconds)}</span>.
        </>
      ) : (
        <>You can try again now.</>
      )}
    </FormBanner>
  );
}

/* -------------------------------------------------------------------------- */
/* Password                                                                   */
/* -------------------------------------------------------------------------- */

export interface PasswordFieldProps extends Omit<InputProps, "type" | "rightSlot" | "id"> {
  id: string;
  /** Show the live rule + strength block under the field. */
  showRules?: boolean;
}

/**
 * Password input with a visible reveal toggle and, for new passwords, the
 * rules stated *before* submission rather than as a post-hoc rejection.
 */
export function PasswordField({
  id,
  showRules = false,
  value,
  error,
  label,
  ...props
}: PasswordFieldProps) {
  const [revealed, setRevealed] = React.useState(false);
  const text = typeof value === "string" ? value : "";
  const assessment = assessPassword(text);
  const rulesId = `${id}-rules`;
  const errorId = `${id}-error`;
  const describedBy = [showRules ? rulesId : null, error ? errorId : null].filter(Boolean).join(" ");

  return (
    <div className="flex flex-col gap-2">
      <Input
        {...props}
        id={id}
        label={label}
        error={error}
        value={value}
        type={revealed ? "text" : "password"}
        aria-describedby={describedBy || undefined}
        rightSlot={
          <button
            type="button"
            onClick={() => setRevealed((open) => !open)}
            aria-pressed={revealed}
            aria-controls={id}
            className="zv-touch flex h-9 w-9 items-center justify-center rounded-full text-text-secondary transition-colors hover:bg-neutral-200 hover:text-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
          >
            {revealed ? (
              <EyeOff className="h-[18px] w-[18px]" aria-hidden="true" />
            ) : (
              <Eye className="h-[18px] w-[18px]" aria-hidden="true" />
            )}
            <span className="zv-sr-only">{revealed ? "Hide password" : "Show password"}</span>
          </button>
        }
      />

      {showRules && (
        <div id={rulesId} className="rounded-md bg-neutral-50 p-3">
          <p className="flex items-center gap-2 type-caption text-text-secondary">
            {assessment.meetsMinimum ? (
              <CheckCircle2 className="h-4 w-4 shrink-0 text-success" aria-hidden="true" />
            ) : (
              <span
                aria-hidden="true"
                className="h-4 w-4 shrink-0 rounded-full border-[1.5px] border-neutral-300"
              />
            )}
            <span className={assessment.meetsMinimum ? "text-neutral-900" : undefined}>
              At least {PASSWORD_MIN_LENGTH} characters
              <span className="zv-sr-only">
                {assessment.meetsMinimum ? " — met" : " — not met yet"}
              </span>
            </span>
          </p>

          {text.length > 0 && (
            <div className="mt-3">
              <div className="flex items-center justify-between gap-3">
                <span className="type-caption text-text-secondary">Password strength</span>
                <span className="type-caption font-bold text-neutral-900">{assessment.strengthLabel}</span>
              </div>
              <div
                className="mt-1.5 flex gap-1"
                role="meter"
                aria-valuemin={0}
                aria-valuemax={3}
                aria-valuenow={assessment.strength}
                aria-valuetext={assessment.strengthLabel}
                aria-label="Password strength"
              >
                {[1, 2, 3].map((step) => (
                  <span
                    key={step}
                    className={cn(
                      "h-1.5 flex-1 rounded-full transition-colors",
                      assessment.strength >= step
                        ? assessment.strength === 3
                          ? "bg-success"
                          : assessment.strength === 2
                            ? "bg-brand-green/50"
                            : "bg-warning"
                        : "bg-neutral-200",
                    )}
                  />
                ))}
              </div>
              {assessment.tip && (
                <p className="mt-2 type-caption text-text-secondary">{assessment.tip}</p>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Phone                                                                      */
/* -------------------------------------------------------------------------- */

export interface PhoneFieldProps extends Omit<InputProps, "type" | "value" | "onChange"> {
  value: string;
  onValueChange: (value: string) => void;
}

/**
 * Zimbabwean mobile number. Accepts `077…`, `26377…` or `+26377…` and shows the
 * E.164 value that will actually be sent, so nobody is surprised at submit.
 */
export function PhoneField({ value, onValueChange, help, error, ...props }: PhoneFieldProps) {
  const normalised = toE164(value);
  const showPreview = Boolean(normalised) && value.replace(/\s/g, "") !== normalised;
  return (
    <Input
      {...props}
      type="tel"
      inputMode="tel"
      autoComplete="tel"
      placeholder="077 123 4567"
      value={value}
      error={error}
      onChange={(event) => onValueChange(event.target.value)}
      help={
        error
          ? undefined
          : showPreview
            ? `Saved as ${formatPhone(normalised)}`
            : (help ?? "Zimbabwean mobile number. 077…, 0712… or +263…")
      }
    />
  );
}

/* -------------------------------------------------------------------------- */
/* Progress + success                                                         */
/* -------------------------------------------------------------------------- */

/** "Step 2 of 3 · Your account" plus a segmented bar. */
export function StepProgress({
  step,
  total,
  label,
}: {
  step: number;
  total: number;
  label: string;
}) {
  return (
    <div className="mb-6">
      <div className="flex items-baseline justify-between gap-3">
        <p className="type-overline text-text-tertiary">
          Step {step} of {total}
        </p>
        <p className="type-caption font-bold text-neutral-900">{label}</p>
      </div>
      <div
        className="mt-2 flex gap-1.5"
        role="progressbar"
        aria-valuemin={1}
        aria-valuemax={total}
        aria-valuenow={step}
        aria-valuetext={`Step ${step} of ${total}: ${label}`}
      >
        {Array.from({ length: total }, (_, index) => (
          <span
            key={index}
            className={cn(
              "h-1.5 flex-1 rounded-full transition-colors",
              index < step ? "bg-action" : "bg-neutral-200",
            )}
          />
        ))}
      </div>
    </div>
  );
}

/**
 * §4.3 success moment — a check that draws in once with `ease/spring`.
 * Reduced motion turns the draw into a plain cross-fade via globals.css.
 */
export function SuccessMark({ className }: { className?: string }) {
  return (
    <span
      className={cn(
        "flex h-14 w-14 items-center justify-center rounded-full bg-success-surface text-success",
        className,
      )}
    >
      <svg viewBox="0 0 24 24" className="h-7 w-7" fill="none" aria-hidden="true">
        <path
          d="M4.5 12.5l4.5 4.5L19.5 6.5"
          stroke="currentColor"
          strokeWidth="2.5"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="zv-draw-check"
        />
      </svg>
    </span>
  );
}
