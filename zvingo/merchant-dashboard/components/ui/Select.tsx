"use client";

import * as React from "react";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/cn";
import { FieldShell, controlClasses, type FieldSize } from "./Field";

export interface SelectOption {
  value: string;
  label: string;
  disabled?: boolean;
}

export interface SelectProps extends Omit<React.SelectHTMLAttributes<HTMLSelectElement>, "size"> {
  label?: React.ReactNode;
  help?: React.ReactNode;
  error?: string | boolean;
  hint?: React.ReactNode;
  selectSize?: FieldSize;
  /** Convenience: render these instead of passing `<option>` children. */
  options?: SelectOption[];
  /** Shown as a disabled first option when the value is empty. */
  placeholder?: string;
  containerClassName?: string;
}

/** Native select — keyboard, screen reader and tablet behaviour for free. */
export const Select = React.forwardRef<HTMLSelectElement, SelectProps>(function Select(
  {
    className,
    containerClassName,
    label,
    help,
    error,
    hint,
    required,
    selectSize = "md",
    options,
    placeholder,
    id,
    children,
    ...props
  },
  ref,
) {
  const reactId = React.useId();
  const fieldId = id ?? `select-${reactId}`;
  const helpId = `${fieldId}-help`;
  const errorId = `${fieldId}-error`;
  const invalid = Boolean(error);
  const errorText = typeof error === "string" ? error : undefined;

  const control = (
    <div className="relative w-full">
      <select
        ref={ref}
        id={fieldId}
        required={required}
        aria-invalid={invalid || undefined}
        aria-describedby={errorText ? errorId : help ? helpId : undefined}
        className={cn(
          controlClasses({ size: selectSize, invalid, withRightIcon: true }),
          "cursor-pointer appearance-none",
          className,
        )}
        {...props}
      >
        {placeholder && (
          <option value="" disabled>
            {placeholder}
          </option>
        )}
        {options?.map((option) => (
          <option key={option.value} value={option.value} disabled={option.disabled}>
            {option.label}
          </option>
        ))}
        {children}
      </select>
      <ChevronDown
        className="pointer-events-none absolute right-4 top-1/2 h-4 w-4 -translate-y-1/2 text-text-secondary"
        aria-hidden="true"
      />
    </div>
  );

  if (!label && !help && !errorText && !hint) return control;

  return (
    <FieldShell
      label={label}
      help={help}
      error={errorText}
      hint={hint}
      required={required}
      htmlFor={fieldId}
      describedById={helpId}
      errorId={errorId}
      className={containerClassName}
    >
      {control}
    </FieldShell>
  );
});
