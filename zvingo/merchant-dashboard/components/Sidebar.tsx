"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  ArrowUpRight,
  Home,
  Settings,
  ShoppingBag,
  Tag,
  Utensils,
  Zap,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/cn";
import { Tooltip } from "@/components/ui/Tooltip";

export interface NavItem {
  name: string;
  href: string;
  icon: LucideIcon;
  /** One line explaining the destination — used in tooltips and the drawer. */
  description: string;
  /** Match child routes as well as the exact path. */
  matchNested?: boolean;
}

/** The dashboard's five destinations. Five is the cap (§5.4). */
export const NAV_ITEMS: NavItem[] = [
  { name: "Overview", href: "/dashboard", icon: Home, description: "Today's sales at a glance" },
  {
    name: "Orders",
    href: "/dashboard/orders",
    icon: ShoppingBag,
    description: "Accept, prepare and hand over orders",
    matchNested: true,
  },
  {
    name: "Menu",
    href: "/dashboard/menu",
    icon: Utensils,
    description: "Items, prices and availability",
    matchNested: true,
  },
  {
    name: "Promotions",
    href: "/dashboard/promotions",
    icon: Tag,
    description: "Offers and promo codes",
    matchNested: true,
  },
  {
    name: "Settings",
    href: "/dashboard/settings",
    icon: Settings,
    description: "Store details, hours and account",
    matchNested: true,
  },
];

export function isNavItemActive(item: NavItem, pathname: string): boolean {
  if (item.matchNested) return pathname === item.href || pathname.startsWith(`${item.href}/`);
  return pathname === item.href;
}

/** The nav item matching the current route — used to title the page bar. */
export function findNavItem(pathname: string): NavItem | undefined {
  const nested = NAV_ITEMS.filter((item) => item.matchNested);
  return (
    nested.find((item) => pathname === item.href || pathname.startsWith(`${item.href}/`)) ??
    NAV_ITEMS.find((item) => item.href === pathname)
  );
}

export interface SidebarProps {
  /**
   * Icon-only rail for narrow desktop widths. Labels stay reachable through
   * tooltips — an unlabelled nav is banned (§5.4).
   */
  collapsed?: boolean;
  /** Called after a destination is chosen (closes the mobile drawer). */
  onNavigate?: () => void;
  className?: string;
}

/**
 * Primary navigation. Always labelled, always shows where you are, and always
 * reachable — on a tablet it becomes a drawer rather than disappearing.
 */
export default function Sidebar({ collapsed = false, onNavigate, className }: SidebarProps) {
  const pathname = usePathname() ?? "";

  return (
    <aside
      className={cn(
        "flex h-full shrink-0 flex-col bg-neutral-900 text-neutral-0",
        collapsed ? "w-[76px]" : "w-[248px]",
        className,
      )}
    >
      <Link
        href="/dashboard"
        onClick={onNavigate}
        aria-label="Zvingo Partner — go to overview"
        className={cn(
          "flex h-18 items-center gap-3 px-5 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-brand-lime",
          collapsed && "justify-center px-0",
        )}
      >
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-brand-lime text-neutral-900">
          <Zap className="h-5 w-5" fill="currentColor" aria-hidden="true" />
        </span>
        {!collapsed && (
          <span className="type-h3 tracking-[-0.04em]">
            zvingo<span className="text-brand-lime">partner</span>
          </span>
        )}
      </Link>

      <nav aria-label="Main" className="flex-1 overflow-y-auto px-3 pb-3">
        <ul className="flex flex-col gap-1">
          {NAV_ITEMS.map((item) => {
            const active = isNavItemActive(item, pathname);
            const link = (
              <Link
                href={item.href}
                onClick={onNavigate}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "group relative flex min-h-12 w-full items-center gap-3 rounded-md px-3 type-button transition-colors",
                  "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-brand-lime",
                  active
                    ? "bg-neutral-0 text-neutral-900"
                    : "text-neutral-300 hover:bg-neutral-800 hover:text-neutral-0",
                  collapsed && "justify-center px-0",
                )}
              >
                {/* Active marker: shape as well as colour, for colour-blind users. */}
                <span
                  aria-hidden="true"
                  className={cn(
                    "absolute left-0 top-1/2 h-6 w-1 -translate-y-1/2 rounded-full bg-brand-lime transition-opacity",
                    active ? "opacity-100" : "opacity-0",
                  )}
                />
                <item.icon
                  className={cn(
                    "h-5 w-5 shrink-0",
                    active ? "text-brand-green" : "text-neutral-400 group-hover:text-neutral-0",
                  )}
                  aria-hidden="true"
                />
                {collapsed ? <span className="zv-sr-only">{item.name}</span> : <span>{item.name}</span>}
              </Link>
            );

            return (
              <li key={item.href} className="relative">
                {collapsed ? (
                  <Tooltip content={item.name} placement="right">
                    {link}
                  </Tooltip>
                ) : (
                  link
                )}
              </li>
            );
          })}
        </ul>
      </nav>

      {!collapsed && (
        <div className="m-3 rounded-lg bg-neutral-800 p-4">
          <span
            aria-hidden="true"
            className="mb-3 flex h-9 w-9 items-center justify-center rounded-md bg-brand-lime text-neutral-900"
          >
            <ArrowUpRight className="h-5 w-5" />
          </span>
          <p className="type-body-strong text-neutral-0">Grow your orders</p>
          <p className="type-caption mt-1 text-neutral-400">
            A promotion brings regulars back and fills quiet hours.
          </p>
          <Link
            href="/dashboard/promotions"
            onClick={onNavigate}
            className="mt-3 inline-flex min-h-11 items-center type-caption font-bold text-brand-lime underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-lime"
          >
            Create an offer
          </Link>
        </div>
      )}
    </aside>
  );
}
