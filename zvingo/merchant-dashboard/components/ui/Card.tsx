import * as React from "react";
import { cn } from "@/lib/cn";

export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Lifts to shadow/md on hover — only for cards that are themselves clickable. */
  interactive?: boolean;
  /** Remove the default 16px padding (image-led cards, tables, lists). */
  flush?: boolean;
  /** Render as a different element, e.g. `section` or `li`. */
  as?: "div" | "section" | "article" | "li";
}

/**
 * DESIGN_SYSTEM §5.2 — surface `neutral/0`, `radius/lg`, `shadow/sm`, a 1px
 * `neutral/200` hairline and 16px padding. Shadows are never stacked.
 */
export const Card = React.forwardRef<HTMLDivElement, CardProps>(function Card(
  { className, interactive, flush, as = "div", ...props },
  ref,
) {
  const Tag = as as React.ElementType;
  return (
    <Tag
      ref={ref}
      className={cn(
        "rounded-lg border border-border bg-surface text-neutral-900 shadow-sm",
        !flush && "p-4",
        interactive &&
          "cursor-pointer transition-shadow hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action",
        className,
      )}
      {...props}
    />
  );
});

export const CardHeader = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  function CardHeader({ className, ...props }, ref) {
    return (
      <div
        ref={ref}
        className={cn("flex items-start justify-between gap-4 px-4 pb-3 pt-4", className)}
        {...props}
      />
    );
  },
);

export const CardTitle = React.forwardRef<HTMLHeadingElement, React.HTMLAttributes<HTMLHeadingElement>>(
  function CardTitle({ className, ...props }, ref) {
    return <h3 ref={ref} className={cn("type-h3 text-neutral-900", className)} {...props} />;
  },
);

export const CardDescription = React.forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLParagraphElement>
>(function CardDescription({ className, ...props }, ref) {
  return <p ref={ref} className={cn("type-caption mt-1 text-text-secondary", className)} {...props} />;
});

/** The card's main content region. */
export const CardBody = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  function CardBody({ className, ...props }, ref) {
    return <div ref={ref} className={cn("px-4 pb-4", className)} {...props} />;
  },
);

/** Legacy alias of `CardBody` (pre-design-system pages import this name). */
export const CardContent = CardBody;

export const CardFooter = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  function CardFooter({ className, ...props }, ref) {
    return (
      <div
        ref={ref}
        className={cn("flex items-center gap-3 border-t border-divider px-4 py-3", className)}
        {...props}
      />
    );
  },
);

export interface CardMediaProps extends React.HTMLAttributes<HTMLDivElement> {
  /** 16:9 for restaurants, 1:1 for menu items (§5.2). */
  ratio?: "16/9" | "1/1" | "4/3";
}

/** Edge-to-edge media slot that keeps the card radius on the top corners only. */
export const CardMedia = React.forwardRef<HTMLDivElement, CardMediaProps>(function CardMedia(
  { className, ratio = "16/9", style, ...props },
  ref,
) {
  return (
    <div
      ref={ref}
      style={{ aspectRatio: ratio, ...style }}
      className={cn(
        "-mx-px -mt-px overflow-hidden rounded-t-lg bg-neutral-100 [&_img]:h-full [&_img]:w-full [&_img]:object-cover",
        className,
      )}
      {...props}
    />
  );
});
