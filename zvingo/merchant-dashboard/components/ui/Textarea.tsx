"use client";

import * as React from "react";
import { cn } from "@/lib/cn";
import { FieldShell, controlClasses } from "./Field";

export interface TextareaProps extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: React.ReactNode;
  help?: React.ReactNode;
  error?: string | boolean;
  hint?: React.ReactNode;
  /** Show a live `used / max` counter. Requires `maxLength`. */
  showCount?: boolean;
  containerClassName?: string;
}

export const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(function Textarea(
  {
    className,
    containerClassName,
    label,
    help,
    error,
    hint,
    required,
    rows = 4,
    showCount,
    maxLength,
    id,
    value,
    defaultValue,
    onChange,
    ...props
  },
  ref,
) {
  const reactId = React.useId();
  const fieldId = id ?? `textarea-${reactId}`;
  const helpId = `${fieldId}-help`;
  const errorId = `${fieldId}-error`;
  const invalid = Boolean(error);
  const errorText = typeof error === "string" ? error : undefined;

  const [length, setLength] = React.useState(
    String(value ?? defaultValue ?? "").length,
  );
  React.useEffect(() => {
    if (value !== undefined) setLength(String(value).length);
  }, [value]);

  const counter =
    showCount && maxLength ? (
      <span className="tabular-figures">
        {length}/{maxLength}
      </span>
    ) : undefined;

  return (
    <FieldShell
      label={label}
      help={help}
      error={errorText}
      hint={hint ?? counter}
      required={required}
      htmlFor={fieldId}
      describedById={helpId}
      errorId={errorId}
      className={containerClassName}
    >
      <textarea
        ref={ref}
        id={fieldId}
        rows={rows}
        required={required}
        maxLength={maxLength}
        value={value}
        defaultValue={defaultValue}
        aria-invalid={invalid || undefined}
        aria-describedby={errorText ? errorId : help ? helpId : undefined}
        onChange={(event) => {
          setLength(event.target.value.length);
          onChange?.(event);
        }}
        className={cn(
          controlClasses({ invalid }),
          "h-auto resize-y py-3 leading-[22px]",
          className,
        )}
        {...props}
      />
    </FieldShell>
  );
});
