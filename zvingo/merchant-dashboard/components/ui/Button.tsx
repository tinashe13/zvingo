import * as React from "react";
import { cn } from "@/lib/cn";
import { Spinner } from "./Spinner";

// Historic import site: `import { cn } from "@/components/ui/Button"`.
// Kept so existing pages keep compiling; prefer `@/lib/cn` in new code.
export { cn };

export type ButtonVariant =
  | "primary"
  | "secondary"
  | "tertiary"
  | "destructive"
  | "icon"
  // Legacy aliases kept for pages written before the design system landed.
  | "outline"
  | "ghost"
  | "danger";

export type ButtonSize = "sm" | "md" | "lg" | "icon";

const VARIANT_ALIASES: Record<string, ButtonVariant> = {
  outline: "secondary",
  ghost: "tertiary",
  danger: "destructive",
};

/** DESIGN_SYSTEM §5.1 button contract. */
const VARIANT_CLASSES: Record<Exclude<ButtonVariant, "outline" | "ghost" | "danger">, string> = {
  primary:
    "bg-action text-neutral-0 hover:bg-action-hover active:bg-action-pressed " +
    "disabled:bg-action-disabled-bg disabled:text-action-disabled-fg",
  secondary:
    "bg-surface text-neutral-900 border border-border hover:bg-neutral-50 hover:border-neutral-300 " +
    "disabled:bg-surface disabled:text-action-disabled-fg disabled:border-border",
  tertiary:
    "bg-transparent text-neutral-900 hover:bg-neutral-100 " +
    "disabled:bg-transparent disabled:text-action-disabled-fg",
  destructive:
    "bg-error text-neutral-0 hover:bg-error/90 active:bg-error " +
    "disabled:bg-action-disabled-bg disabled:text-action-disabled-fg",
  icon:
    "bg-neutral-100 text-neutral-900 hover:bg-neutral-200 rounded-full " +
    "disabled:bg-neutral-100 disabled:text-action-disabled-fg",
};

const SIZE_CLASSES: Record<ButtonSize, string> = {
  // Dense dashboard rhythm: sm/md for in-table actions, lg (52px, §5.1) for
  // the single primary action on a screen.
  sm: "h-10 gap-1.5 px-3 text-caption",
  md: "h-11 gap-2 px-5 text-button",
  lg: "h-13 gap-2 px-6 text-button",
  icon: "h-11 w-11 gap-0 p-0",
};

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  /** Locks the button width and swaps the label for a spinner (§5.1). */
  loading?: boolean;
  /** Legacy alias for `loading`. */
  isLoading?: boolean;
  /** Icon before the label. Pass a 16–18px lucide icon. */
  leftIcon?: React.ReactNode;
  /** Icon after the label. */
  rightIcon?: React.ReactNode;
  fullWidth?: boolean;
  /**
   * Render the single child element instead of a `<button>`, merging classes
   * and props onto it. Use for `<Link>` that should look like a button.
   */
  asChild?: boolean;
  /**
   * Required when the button has no visible text (icon-only). Navigation and
   * icon affordances are never unlabelled (§5.4).
   */
  "aria-label"?: string;
}

export function buttonClasses({
  variant = "primary",
  size,
  fullWidth,
  className,
}: {
  variant?: ButtonVariant;
  size?: ButtonSize;
  fullWidth?: boolean;
  className?: string;
} = {}) {
  const resolvedVariant = VARIANT_ALIASES[variant] ?? variant;
  const resolvedSize: ButtonSize = size ?? (resolvedVariant === "icon" ? "icon" : "md");
  return cn(
    "relative inline-flex select-none items-center justify-center whitespace-nowrap rounded-md",
    "font-bold tracking-[-0.1px] transition-colors",
    "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action",
    "disabled:cursor-not-allowed",
    // Every control keeps a 48×48 hit area even when the visual is smaller.
    (resolvedSize === "sm" || resolvedSize === "icon") && "zv-touch",
    VARIANT_CLASSES[resolvedVariant as keyof typeof VARIANT_CLASSES],
    SIZE_CLASSES[resolvedSize],
    fullWidth && "w-full",
    className,
  );
}

type SlotProps = React.HTMLAttributes<HTMLElement> & { children: React.ReactNode };

/** Minimal `asChild` implementation — no runtime dependency on Radix. */
function mergeIntoChild(child: React.ReactNode, props: SlotProps): React.ReactElement | null {
  if (!React.isValidElement(child)) return null;
  const childProps = child.props as SlotProps;
  const { children: _slotChildren, ...rest } = props;
  void _slotChildren;
  return React.cloneElement(child, {
    ...rest,
    ...childProps,
    className: cn(props.className, childProps.className),
    style: { ...props.style, ...childProps.style },
  } as Partial<SlotProps>);
}

/**
 * The dashboard's only button. One filled `primary` per screen (§0.2);
 * everything else is `secondary`, `tertiary` or `icon`.
 */
export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    className,
    variant = "primary",
    size,
    loading,
    isLoading,
    leftIcon,
    rightIcon,
    fullWidth,
    asChild,
    children,
    disabled,
    type,
    ...props
  },
  ref,
) {
  const busy = Boolean(loading ?? isLoading);
  const classes = buttonClasses({ variant, size, fullWidth, className });

  if (asChild) {
    return mergeIntoChild(children, {
      className: classes,
      ...(props as React.HTMLAttributes<HTMLElement>),
      children,
    });
  }

  return (
    <button
      ref={ref}
      type={type ?? "button"}
      className={classes}
      disabled={disabled || busy}
      aria-busy={busy || undefined}
      {...props}
    >
      {/* Content stays mounted while loading so the width never shifts. */}
      <span
        className={cn(
          "inline-flex items-center justify-center gap-2",
          busy && "invisible",
        )}
      >
        {leftIcon}
        {children}
        {rightIcon}
      </span>
      {busy && (
        <span className="absolute inset-0 flex items-center justify-center">
          <Spinner size={18} label="Working" />
        </span>
      )}
    </button>
  );
});

export interface IconButtonProps extends Omit<ButtonProps, "variant" | "size" | "children"> {
  /** Required: the accessible name for a control with no visible text. */
  label: string;
  icon: React.ReactNode;
  /** Visual treatment. `icon` is the tinted circle from §5.1. */
  tone?: "icon" | "tertiary" | "secondary" | "destructive";
}

/** A 44×44 circular icon affordance with a 48×48 hit area and a real name. */
export const IconButton = React.forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { label, icon, tone = "icon", className, ...props },
  ref,
) {
  return (
    <Button
      ref={ref}
      variant={tone}
      size="icon"
      aria-label={label}
      title={label}
      className={cn(tone !== "icon" && "rounded-full", className)}
      {...props}
    >
      {icon}
    </Button>
  );
});
