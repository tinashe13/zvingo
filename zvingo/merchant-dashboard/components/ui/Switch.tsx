"use client";

import * as React from "react";
import { cn } from "@/lib/cn";
import { Spinner } from "./Spinner";

export interface SwitchProps {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  /** Visible label. Required unless `aria-label` is supplied. */
  label?: React.ReactNode;
  description?: React.ReactNode;
  disabled?: boolean;
  /** Shows a spinner in place of the thumb while a save is in flight. */
  busy?: boolean;
  /** Put the label after the control instead of before it. */
  labelPosition?: "start" | "end";
  size?: "sm" | "md";
  id?: string;
  className?: string;
  "aria-label"?: string;
}

/**
 * Toggle for an immediately-applied setting. A switch saves on change — if the
 * change needs a Save button, use a `Checkbox` instead.
 */
export const Switch = React.forwardRef<HTMLButtonElement, SwitchProps>(function Switch(
  {
    checked,
    onCheckedChange,
    label,
    description,
    disabled,
    busy,
    labelPosition = "start",
    size = "md",
    id,
    className,
    ...props
  },
  ref,
) {
  const reactId = React.useId();
  const switchId = id ?? `switch-${reactId}`;
  const labelId = `${switchId}-label`;
  const descriptionId = `${switchId}-description`;

  const track = size === "md" ? "h-7 w-12" : "h-6 w-10";
  const thumb = size === "md" ? "h-5 w-5" : "h-4 w-4";
  const travel = size === "md" ? "translate-x-5" : "translate-x-4";

  const control = (
    <button
      ref={ref}
      type="button"
      role="switch"
      id={switchId}
      aria-checked={checked}
      aria-labelledby={label ? labelId : undefined}
      aria-describedby={description ? descriptionId : undefined}
      disabled={disabled || busy}
      onClick={() => onCheckedChange(!checked)}
      className={cn(
        "zv-touch relative shrink-0 rounded-full p-1 transition-colors",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action",
        "disabled:cursor-not-allowed disabled:opacity-60",
        track,
        checked ? "bg-action" : "bg-neutral-300",
        className,
      )}
      {...props}
    >
      <span
        className={cn(
          "flex items-center justify-center rounded-full bg-neutral-0 shadow-sm transition-transform",
          thumb,
          checked && travel,
        )}
      >
        {busy && <Spinner size={12} label={null} className="text-neutral-600" />}
      </span>
    </button>
  );

  if (!label && !description) return control;

  return (
    <div
      className={cn(
        "flex min-h-12 items-center justify-between gap-4",
        labelPosition === "end" && "flex-row-reverse justify-end",
      )}
    >
      <span className="flex flex-col gap-0.5">
        {label && (
          <label
            id={labelId}
            htmlFor={switchId}
            className="type-body cursor-pointer font-semibold text-neutral-900"
          >
            {label}
          </label>
        )}
        {description && (
          <span id={descriptionId} className="type-caption text-text-secondary">
            {description}
          </span>
        )}
      </span>
      {control}
    </div>
  );
});
