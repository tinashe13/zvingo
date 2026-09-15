"use client";

import * as React from "react";
import { cn } from "@/lib/cn";
import { FieldShell, controlClasses, type FieldSize } from "./Field";

export interface InputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, "size"> {
  label?: React.ReactNode;
  help?: React.ReactNode;
  /** `string` renders the message; `true` marks the field invalid silently. */
  error?: string | boolean;
  hint?: React.ReactNode;
  inputSize?: FieldSize;
  /** 16–18px lucide icon rendered inside the field on the left. */
  leftIcon?: React.ReactNode;
  /** Icon or small control rendered inside the field on the right. */
  rightSlot?: React.ReactNode;
  /** Static prefix such as a currency symbol. */
  prefix?: string;
  containerClassName?: string;
}

export const Input = React.forwardRef<HTMLInputElement, InputProps>(function Input(
  {
    className,
    containerClassName,
    label,
    help,
    error,
    hint,
    required,
    inputSize = "md",
    leftIcon,
    rightSlot,
    prefix,
    id,
    type = "text",
    ...props
  },
  ref,
) {
  const reactId = React.useId();
  const inputId = id ?? `input-${reactId}`;
  const helpId = `${inputId}-help`;
  const errorId = `${inputId}-error`;
  const invalid = Boolean(error);
  const errorText = typeof error === "string" ? error : undefined;
  const hasAdornment = Boolean(leftIcon || prefix);

  const control = (
    <div className="relative w-full">
      {leftIcon && (
        <span
          className="pointer-events-none absolute left-4 top-1/2 flex -translate-y-1/2 items-center text-text-tertiary"
          aria-hidden="true"
        >
          {leftIcon}
        </span>
      )}
      {prefix && !leftIcon && (
        <span
          className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 type-body font-semibold text-text-secondary tabular-figures"
          aria-hidden="true"
        >
          {prefix}
        </span>
      )}
      <input
        ref={ref}
        id={inputId}
        type={type}
        required={required}
        aria-invalid={invalid || undefined}
        aria-required={required || undefined}
        aria-describedby={errorText ? errorId : help ? helpId : undefined}
        className={cn(
          controlClasses({
            size: inputSize,
            invalid,
            withLeftIcon: hasAdornment,
            withRightIcon: Boolean(rightSlot),
          }),
          (type === "number" || props.inputMode === "numeric" || props.inputMode === "decimal") &&
            "tabular-figures",
          className,
        )}
        {...props}
      />
      {rightSlot && (
        <span className="absolute right-3 top-1/2 flex -translate-y-1/2 items-center text-text-secondary">
          {rightSlot}
        </span>
      )}
    </div>
  );

  // Bare control when there is nothing to label — keeps historic call sites
  // (which wrap `Input` in their own `Field`) rendering exactly as before.
  if (!label && !help && !errorText && !hint) return control;

  return (
    <FieldShell
      label={label}
      help={help}
      error={errorText}
      hint={hint}
      required={required}
      htmlFor={inputId}
      describedById={helpId}
      errorId={errorId}
      className={containerClassName}
    >
      {control}
    </FieldShell>
  );
});
