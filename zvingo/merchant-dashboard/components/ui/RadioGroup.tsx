"use client";

import * as React from "react";
import { AlertCircle } from "lucide-react";
import { cn } from "@/lib/cn";

export interface RadioOption<T extends string = string> {
  value: T;
  label: React.ReactNode;
  description?: React.ReactNode;
  disabled?: boolean;
  /** Optional trailing content, e.g. a price or badge. */
  meta?: React.ReactNode;
}

export interface RadioGroupProps<T extends string = string> {
  /** Group label, rendered as the fieldset legend. */
  label?: React.ReactNode;
  name?: string;
  value: T | "";
  onValueChange: (value: T) => void;
  options: Array<RadioOption<T>>;
  help?: React.ReactNode;
  error?: string | boolean;
  /** `card` gives each option a selectable tile; `list` is a compact radio row. */
  variant?: "list" | "card";
  /** Lay the options out side by side above 640px. */
  orientation?: "vertical" | "horizontal";
  className?: string;
}

/**
 * Accessible radio group built on native inputs: arrow keys, Home/End and
 * screen-reader grouping all work without extra code.
 */
export function RadioGroup<T extends string = string>({
  label,
  name,
  value,
  onValueChange,
  options,
  help,
  error,
  variant = "list",
  orientation = "vertical",
  className,
}: RadioGroupProps<T>) {
  const reactId = React.useId();
  const groupName = name ?? `radio-${reactId}`;
  const errorId = `${groupName}-error`;
  const helpId = `${groupName}-help`;
  const errorText = typeof error === "string" ? error : undefined;

  return (
    <fieldset
      className={cn("flex w-full flex-col gap-2 border-0 p-0", className)}
      aria-invalid={Boolean(error) || undefined}
      aria-describedby={errorText ? errorId : help ? helpId : undefined}
    >
      {label && (
        <legend className="type-caption mb-2 p-0 font-semibold text-neutral-800">{label}</legend>
      )}

      <div
        className={cn(
          "flex gap-2",
          orientation === "horizontal" ? "flex-col sm:flex-row sm:gap-3" : "flex-col",
        )}
      >
        {options.map((option) => {
          const optionId = `${groupName}-${option.value}`;
          const selected = value === option.value;
          return (
            <label
              key={option.value}
              htmlFor={optionId}
              className={cn(
                "group flex min-h-12 flex-1 cursor-pointer items-start gap-3",
                variant === "card"
                  ? cn(
                      "rounded-md border-[1.5px] p-3 transition-colors",
                      selected
                        ? "border-action bg-neutral-50"
                        : "border-border bg-surface hover:border-neutral-300",
                    )
                  : "py-1",
                option.disabled && "cursor-not-allowed opacity-60",
              )}
            >
              <span className="relative mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center">
                <input
                  id={optionId}
                  type="radio"
                  name={groupName}
                  value={option.value}
                  checked={selected}
                  disabled={option.disabled}
                  onChange={() => onValueChange(option.value)}
                  className="peer absolute inset-0 h-full w-full cursor-pointer opacity-0 disabled:cursor-not-allowed"
                />
                <span
                  aria-hidden="true"
                  className={cn(
                    "pointer-events-none flex h-5 w-5 items-center justify-center rounded-full border-[1.5px] transition-colors",
                    "peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-action",
                    selected ? "border-action" : "border-neutral-300 bg-surface",
                    Boolean(error) && !selected && "border-error",
                  )}
                >
                  <span
                    className={cn(
                      "h-2.5 w-2.5 rounded-full bg-action transition-transform",
                      selected ? "scale-100" : "scale-0",
                    )}
                  />
                </span>
              </span>

              <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                <span className="type-body font-semibold text-neutral-900">{option.label}</span>
                {option.description && (
                  <span className="type-caption text-text-secondary">{option.description}</span>
                )}
              </span>

              {option.meta && (
                <span className="type-caption shrink-0 font-semibold text-neutral-900 tabular-figures">
                  {option.meta}
                </span>
              )}
            </label>
          );
        })}
      </div>

      {errorText ? (
        <p id={errorId} className="type-caption flex items-start gap-1.5 text-error">
          <AlertCircle className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden="true" />
          <span>{errorText}</span>
        </p>
      ) : help ? (
        <p id={helpId} className="type-caption text-text-secondary">
          {help}
        </p>
      ) : null}
    </fieldset>
  );
}
