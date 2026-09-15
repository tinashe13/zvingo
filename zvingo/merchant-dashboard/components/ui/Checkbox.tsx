"use client";

import * as React from "react";
import { AlertCircle, Check, Minus } from "lucide-react";
import { cn } from "@/lib/cn";

export interface CheckboxProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, "type" | "size"> {
  label?: React.ReactNode;
  /** Secondary line under the label. */
  description?: React.ReactNode;
  error?: string | boolean;
  /** Renders the mixed state (parent of a partially checked group). */
  indeterminate?: boolean;
  containerClassName?: string;
}

export const Checkbox = React.forwardRef<HTMLInputElement, CheckboxProps>(function Checkbox(
  { className, containerClassName, label, description, error, indeterminate, id, disabled, ...props },
  ref,
) {
  const reactId = React.useId();
  const fieldId = id ?? `checkbox-${reactId}`;
  const errorId = `${fieldId}-error`;
  const errorText = typeof error === "string" ? error : undefined;

  const innerRef = React.useRef<HTMLInputElement | null>(null);
  React.useImperativeHandle(ref, () => innerRef.current as HTMLInputElement);
  React.useEffect(() => {
    if (innerRef.current) innerRef.current.indeterminate = Boolean(indeterminate);
  }, [indeterminate]);

  return (
    <div className={cn("flex flex-col gap-2", containerClassName)}>
      <label
        htmlFor={fieldId}
        className={cn(
          "group flex min-h-12 cursor-pointer items-start gap-3 py-1",
          disabled && "cursor-not-allowed opacity-60",
        )}
      >
        <span className="relative mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center">
          <input
            ref={innerRef}
            id={fieldId}
            type="checkbox"
            disabled={disabled}
            aria-invalid={Boolean(error) || undefined}
            aria-describedby={errorText ? errorId : undefined}
            className="peer absolute inset-0 h-full w-full cursor-pointer opacity-0 disabled:cursor-not-allowed"
            {...props}
          />
          <span
            aria-hidden="true"
            className={cn(
              "pointer-events-none flex h-5 w-5 items-center justify-center rounded-sm border-[1.5px] border-neutral-300 bg-surface text-neutral-0",
              "transition-colors peer-checked:border-action peer-checked:bg-action",
              "peer-indeterminate:border-action peer-indeterminate:bg-action",
              "peer-checked:[&_svg]:opacity-100 peer-indeterminate:[&_svg]:opacity-100",
              "peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-action",
              Boolean(error) && "border-error",
              className,
            )}
          >
            {indeterminate ? (
              <Minus className="h-3.5 w-3.5" strokeWidth={3} />
            ) : (
              <Check className="h-3.5 w-3.5 opacity-0 transition-opacity" strokeWidth={3} />
            )}
          </span>
        </span>

        {(label || description) && (
          <span className="flex flex-col gap-0.5">
            {label && <span className="type-body font-semibold text-neutral-900">{label}</span>}
            {description && <span className="type-caption text-text-secondary">{description}</span>}
          </span>
        )}
      </label>

      {errorText && (
        <p id={errorId} className="type-caption flex items-start gap-1.5 text-error">
          <AlertCircle className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden="true" />
          <span>{errorText}</span>
        </p>
      )}
    </div>
  );
});
