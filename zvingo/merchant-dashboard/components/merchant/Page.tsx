"use client";

import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/cn";
import { EmptyState as UiEmptyState } from "@/components/ui/EmptyState";
import { Modal as UiModal } from "@/components/ui/Modal";
import { Switch } from "@/components/ui/Switch";
import { Badge } from "@/components/ui/Badge";
import { Skeleton, SkeletonRegion, StatCardSkeleton, TableRowsSkeleton } from "@/components/ui/Skeleton";

/**
 * Page-level layout helpers.
 *
 * These names predate the component library; they are kept so existing screens
 * keep working, but each one now delegates to `components/ui`. New screens
 * should prefer `AppShell` / `PageContainer` / `PageSection` and the `ui`
 * primitives directly.
 */

export function PageShell({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn("mx-auto w-full max-w-[1480px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8", className)}>
      {children}
    </div>
  );
}

export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
}: {
  eyebrow: string;
  title: string;
  description: string;
  actions?: ReactNode;
}) {
  return (
    <header className="mb-8 flex flex-wrap items-end justify-between gap-4">
      <div className="min-w-0">
        <p className="type-overline mb-1.5 text-brand-green">{eyebrow}</p>
        <h1 className="type-h1 text-neutral-900">{title}</h1>
        <p className="type-body mt-2 max-w-2xl text-text-secondary">{description}</p>
      </div>
      {actions && <div className="flex shrink-0 items-center gap-3">{actions}</div>}
    </header>
  );
}

export function Panel({
  title,
  description,
  action,
  children,
  className,
}: {
  title?: string;
  description?: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={cn("overflow-hidden rounded-lg border border-border bg-surface shadow-sm", className)}>
      {(title || description || action) && (
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-divider px-4 py-4 sm:px-5">
          <div className="min-w-0">
            {title && <h2 className="type-h3 text-neutral-900">{title}</h2>}
            {description && <p className="type-caption mt-0.5 text-text-secondary">{description}</p>}
          </div>
          {action}
        </div>
      )}
      {children}
    </section>
  );
}

export function Field({
  label,
  hint,
  required,
  children,
  className,
}: {
  label: string;
  hint?: string;
  required?: boolean;
  children: ReactNode;
  className?: string;
}) {
  return (
    <label className={cn("block", className)}>
      <span className="type-caption mb-2 block font-semibold text-neutral-800">
        {label}
        {required && (
          <span className="ml-1 text-error" aria-hidden="true">
            *
          </span>
        )}
      </span>
      {children}
      {hint && <span className="type-caption mt-2 block text-text-secondary">{hint}</span>}
    </label>
  );
}

export function Toggle({
  checked,
  onChange,
  label,
  description,
}: {
  checked: boolean;
  onChange: () => void;
  label?: string;
  description?: string;
}) {
  return (
    <Switch
      checked={checked}
      onCheckedChange={onChange}
      label={label}
      description={description}
      aria-label={label ? undefined : "Toggle"}
    />
  );
}

export function StatusBadge({
  active,
  activeLabel = "Active",
  inactiveLabel = "Paused",
}: {
  active: boolean;
  activeLabel?: string;
  inactiveLabel?: string;
}) {
  return (
    <Badge tone={active ? "success" : "neutral"} dot>
      {active ? activeLabel : inactiveLabel}
    </Badge>
  );
}

export function EmptyState({
  icon,
  title,
  description,
  action,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return <UiEmptyState icon={icon} title={title} description={description} action={action} />;
}

/**
 * Layout-matched loading placeholder (§4.3 — skeletons, not spinners): a KPI
 * row above a list, which is the shape of every screen in this dashboard.
 */
export function LoadingState() {
  return (
    <SkeletonRegion label="Loading page" className="w-full">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, index) => (
          <StatCardSkeleton key={index} />
        ))}
      </div>
      <div className="mt-8 overflow-hidden rounded-lg border border-border bg-surface shadow-sm">
        <div className="flex items-center justify-between border-b border-divider px-4 py-4">
          <Skeleton className="h-4 w-40" />
          <Skeleton className="h-10 w-28 rounded-md" />
        </div>
        <table className="w-full">
          <tbody>
            <TableRowsSkeleton rows={6} columns={4} />
          </tbody>
        </table>
      </div>
    </SkeletonRegion>
  );
}

export function Modal({
  title,
  description,
  onClose,
  children,
  footer,
  wide = false,
}: {
  title: string;
  description?: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
  wide?: boolean;
}) {
  return (
    <UiModal
      open
      onClose={onClose}
      title={title}
      description={description}
      size={wide ? "lg" : "md"}
      footer={footer}
    >
      {children}
    </UiModal>
  );
}
