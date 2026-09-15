"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  ChevronRight,
  LogOut,
  Menu,
  PanelLeftClose,
  PanelLeftOpen,
  Settings,
  User,
  X,
} from "lucide-react";
import { cn } from "@/lib/cn";
import Sidebar, { findNavItem } from "./Sidebar";
import StoreStatus from "./merchant/StoreStatus";
import { IconButton } from "@/components/ui/Button";
import { DropdownMenu } from "@/components/ui/DropdownMenu";
import { clearAuth } from "@/lib/api";
import { clearApiCache, useMerchantSession } from "@/lib/useApi";
import { initials } from "@/lib/format";
import { useEscapeKey, useFocusTrap, useLocalStorage, useLockBodyScroll } from "@/lib/hooks";

export interface Crumb {
  label: string;
  href?: string;
}

export interface AppShellProps {
  children: React.ReactNode;
  /** Overrides the title derived from the route. */
  title?: string;
  /** Overrides the breadcrumbs derived from the route. */
  breadcrumbs?: Crumb[];
  /** Page-level actions rendered at the right of the title bar. */
  actions?: React.ReactNode;
  /**
   * Rendered directly under the app bar and above the page — use it for the
   * `NewOrderAlert`, an offline banner, or anything that must stay on screen.
   */
  banner?: React.ReactNode;
  className?: string;
}

/**
 * The dashboard chrome: navigation, a bar that names where you are, the
 * store's open/closed state, and the account menu. Built for a counter tablet
 * in landscape (≥768px) and a back-office laptop.
 */
export default function AppShell({
  children,
  title,
  breadcrumbs,
  actions,
  banner,
  className,
}: AppShellProps) {
  const pathname = usePathname() ?? "";
  const router = useRouter();
  const { user, restaurant } = useMerchantSession();

  const [railCollapsed, setRailCollapsed] = useLocalStorage("zvingo_nav_collapsed", false);
  const [drawerOpen, setDrawerOpen] = React.useState(false);
  const drawerRef = React.useRef<HTMLDivElement>(null);

  useLockBodyScroll(drawerOpen);
  useFocusTrap(drawerRef, drawerOpen);
  useEscapeKey(() => setDrawerOpen(false), drawerOpen);

  // Close the drawer whenever the route changes.
  React.useEffect(() => setDrawerOpen(false), [pathname]);

  const navItem = findNavItem(pathname);
  const pageTitle = title ?? navItem?.name ?? "Dashboard";
  const crumbs: Crumb[] =
    breadcrumbs ??
    (navItem && navItem.href !== "/dashboard"
      ? [{ label: "Overview", href: "/dashboard" }, { label: navItem.name }]
      : [{ label: "Overview" }]);

  const signOut = () => {
    clearAuth();
    clearApiCache();
    router.replace("/login");
  };

  const displayName = user?.full_name || restaurant?.name || "My restaurant";

  return (
    <div className={cn("flex h-screen overflow-hidden bg-background", className)}>
      {/* Permanent navigation from 768px up. */}
      <div className="max-md:hidden">
        <Sidebar collapsed={railCollapsed} />
      </div>

      {/* Mobile / narrow-tablet drawer. */}
      {drawerOpen && (
        <div className="fixed inset-0 z-50 md:hidden" role="presentation">
          <div
            className="zv-fade absolute inset-0 bg-neutral-900/55"
            onClick={() => setDrawerOpen(false)}
            aria-hidden="true"
          />
          <div
            ref={drawerRef}
            role="dialog"
            aria-modal="true"
            aria-label="Main navigation"
            className="zv-sheet-left absolute inset-y-0 left-0 flex w-[264px] max-w-[85vw]"
          >
            <Sidebar onNavigate={() => setDrawerOpen(false)} className="w-full" />
            <IconButton
              label="Close navigation"
              icon={<X className="h-4 w-4" />}
              onClick={() => setDrawerOpen(false)}
              className="absolute right-3 top-4 bg-neutral-800 text-neutral-0 hover:bg-neutral-700"
            />
          </div>
        </div>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="z-30 shrink-0 border-b border-border bg-surface">
          <div className="flex h-18 items-center gap-3 px-4 sm:px-6">
            <IconButton
              label="Open navigation"
              icon={<Menu className="h-5 w-5" />}
              onClick={() => setDrawerOpen(true)}
              className="md:hidden"
            />

            <IconButton
              label={railCollapsed ? "Expand navigation" : "Collapse navigation"}
              icon={
                railCollapsed ? (
                  <PanelLeftOpen className="h-5 w-5" />
                ) : (
                  <PanelLeftClose className="h-5 w-5" />
                )
              }
              tone="tertiary"
              onClick={() => setRailCollapsed(!railCollapsed)}
              className="max-md:hidden"
            />

            {/* Where am I? — breadcrumbs above, page title below. */}
            <div className="min-w-0 flex-1">
              <nav aria-label="Breadcrumb" className="max-sm:hidden">
                <ol className="flex items-center gap-1 type-caption text-text-tertiary">
                  {crumbs.map((crumb, index) => (
                    <li key={`${crumb.label}-${index}`} className="flex items-center gap-1">
                      {index > 0 && (
                        <ChevronRight className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                      )}
                      {crumb.href && index < crumbs.length - 1 ? (
                        <Link
                          href={crumb.href}
                          className="rounded-xs underline-offset-4 hover:text-neutral-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
                        >
                          {crumb.label}
                        </Link>
                      ) : (
                        <span aria-current={index === crumbs.length - 1 ? "page" : undefined}>
                          {crumb.label}
                        </span>
                      )}
                    </li>
                  ))}
                </ol>
              </nav>
              <h1 className="type-h2 truncate text-neutral-900">{pageTitle}</h1>
            </div>

            <div className="flex shrink-0 items-center gap-2 sm:gap-3">
              {actions}
              <StoreStatus className="max-sm:hidden" />

              <DropdownMenu
                label="Account"
                heading={displayName}
                trigger={
                  <button
                    type="button"
                    className="zv-touch flex h-11 items-center gap-2 rounded-full border border-border py-1 pl-1 pr-3 type-caption font-bold text-neutral-800 transition-colors hover:bg-neutral-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
                  >
                    <span
                      aria-hidden="true"
                      className="flex h-8 w-8 items-center justify-center rounded-full bg-neutral-900 text-overline text-neutral-0"
                    >
                      {initials(displayName)}
                    </span>
                    <span className="max-w-32 truncate max-lg:hidden">{displayName}</span>
                    <span className="zv-sr-only">Open account menu</span>
                  </button>
                }
                items={[
                  {
                    id: "account",
                    label: "Account & store details",
                    description: user?.phone,
                    icon: <User />,
                    onSelect: () => router.push("/dashboard/settings"),
                  },
                  {
                    id: "settings",
                    label: "Settings",
                    icon: <Settings />,
                    onSelect: () => router.push("/dashboard/settings"),
                  },
                  {
                    id: "signout",
                    label: "Sign out",
                    icon: <LogOut />,
                    destructive: true,
                    separatorBefore: true,
                    onSelect: signOut,
                  },
                ]}
              />
            </div>
          </div>

          {/* The store state stays visible on phones too, on its own row. */}
          <div className="flex items-center gap-3 border-t border-divider px-4 py-2 sm:hidden">
            <StoreStatus />
          </div>
        </header>

        {banner}

        <main id="main" className="min-w-0 flex-1 overflow-y-auto">
          {children}
        </main>
      </div>
    </div>
  );
}

export interface PageSectionProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Section heading. */
  title?: string;
  description?: string;
  /** Actions for this section, e.g. "Add item". */
  actions?: React.ReactNode;
}

/**
 * Standard content wrapper: the screen's horizontal padding (§3.1) and the
 * 32px gap between sections, in one place.
 */
export function PageContainer({
  className,
  children,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn("mx-auto w-full max-w-[1480px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8", className)}
      {...props}
    >
      {children}
    </div>
  );
}

/** A titled region inside a page, with an optional action cluster. */
export function PageSection({
  title,
  description,
  actions,
  className,
  children,
  ...props
}: PageSectionProps) {
  return (
    <section className={cn("mb-8 last:mb-0", className)} {...props}>
      {(title || actions) && (
        <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
          <div className="min-w-0">
            {title && <h2 className="type-h2 text-neutral-900">{title}</h2>}
            {description && (
              <p className="type-caption mt-1 text-text-secondary">{description}</p>
            )}
          </div>
          {actions && <div className="flex shrink-0 items-center gap-2">{actions}</div>}
        </div>
      )}
      {children}
    </section>
  );
}

/** Skip link target helper — put this at the very top of a page if needed. */
export function SkipToContent() {
  return (
    <a
      href="#main"
      className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[70] focus:inline-flex focus:h-11 focus:items-center focus:rounded-md focus:bg-action focus:px-4 focus:text-button focus:font-bold focus:text-neutral-0"
    >
      Skip to content
    </a>
  );
}
