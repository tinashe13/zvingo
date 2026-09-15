"use client";

import * as React from "react";
import Link from "next/link";
import { ArrowLeft, BadgeCheck, Bike, ChevronRight, ReceiptText } from "lucide-react";
import { cn } from "@/lib/cn";

/** The Zvingo Partner wordmark. Lime is an accent only (§1.1), never a fill. */
export function Wordmark({ className, tone = "dark" }: { className?: string; tone?: "dark" | "light" }) {
  return (
    <span
      className={cn(
        "type-h3 inline-flex items-center gap-2 font-extrabold tracking-[-0.04em]",
        tone === "light" ? "text-neutral-0" : "text-neutral-900",
        className,
      )}
    >
      <span
        aria-hidden="true"
        className="flex h-8 w-8 items-center justify-center rounded-md bg-brand-lime text-[15px] font-black text-neutral-900"
      >
        Z
      </span>
      <span>
        zvingo<span className="text-brand-green">partner</span>
      </span>
    </span>
  );
}

const REASSURANCE = [
  {
    icon: ReceiptText,
    title: "No commission on your food",
    body: "Your payout is your menu total. Zvingo earns from the delivery fee, not your kitchen.",
  },
  {
    icon: Bike,
    title: "Drivers are already out there",
    body: "Accept an order and dispatch finds the nearest rider. You never arrange a courier.",
  },
  {
    icon: BadgeCheck,
    title: "Live the same day",
    body: "Add your menu, set your hours, switch the store open. There is no waiting list.",
  },
];

export interface AuthShellProps {
  /** Small uppercase eyebrow above the title. */
  eyebrow?: string;
  title: string;
  description?: React.ReactNode;
  children: React.ReactNode;
  /** Back affordance in the top-left (§5.4). Always labelled. */
  back?: { href: string; label: string };
  /** Rendered under the card, e.g. "Already a partner? Sign in". */
  footer?: React.ReactNode;
  /** Progress indicator rendered above the title. */
  progress?: React.ReactNode;
  /** Widen the card for the multi-step sign-up. */
  width?: "md" | "lg";
}

/**
 * The frame every auth screen shares: a dark brand column on large screens, a
 * single content card, one back affordance, one primary action inside.
 */
export function AuthShell({
  eyebrow,
  title,
  description,
  children,
  back,
  footer,
  progress,
  width = "md",
}: AuthShellProps) {
  return (
    <div className="min-h-screen bg-background lg:grid lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
      {/* Brand column — decorative on mobile, informative from 1024px. */}
      <aside className="relative hidden overflow-hidden bg-neutral-900 px-8 py-12 text-neutral-0 lg:flex lg:flex-col lg:justify-between xl:px-12">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -left-24 -top-32 h-80 w-80 rounded-full bg-brand-green/25 blur-3xl"
        />
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -bottom-28 -right-20 h-96 w-96 rounded-full bg-brand-lime/10 blur-3xl"
        />

        <Link href="/" className="relative z-10 inline-flex w-fit rounded-md focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand-lime">
          <Wordmark tone="light" />
          <span className="zv-sr-only">Zvingo Partner home</span>
        </Link>

        <div className="relative z-10 zv-stagger max-w-md">
          <p className="type-overline text-brand-lime">For restaurants in Zimbabwe</p>
          <h2 className="mt-3 type-display text-neutral-0">
            Run the busiest hour of your day from one screen.
          </h2>
          <ul className="mt-8 flex flex-col gap-5">
            {REASSURANCE.map(({ icon: Icon, title: itemTitle, body }) => (
              <li key={itemTitle} className="flex gap-3">
                <span
                  aria-hidden="true"
                  className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-neutral-0/10 text-brand-lime"
                >
                  <Icon className="h-[18px] w-[18px]" />
                </span>
                <span>
                  <span className="block type-body-strong text-neutral-0">{itemTitle}</span>
                  <span className="mt-1 block type-caption font-normal text-neutral-300">{body}</span>
                </span>
              </li>
            ))}
          </ul>
        </div>

        <p className="relative z-10 type-caption text-neutral-400">
          Prices in USD, ZiG and ZAR. Paid out through EcoCash, OneMoney and InnBucks.
        </p>
      </aside>

      {/* Form column */}
      <main
        id="main"
        className="flex min-h-screen flex-col px-4 py-8 sm:px-6 lg:px-10 lg:py-12"
      >
        <div className="flex items-center justify-between gap-4 lg:hidden">
          <Link href="/" className="inline-flex rounded-md focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-action">
            <Wordmark />
            <span className="zv-sr-only">Zvingo Partner home</span>
          </Link>
        </div>

        <div className="flex flex-1 items-center justify-center">
          <div className={cn("w-full py-8", width === "lg" ? "max-w-xl" : "max-w-md")}>
            {back && (
              <Link
                href={back.href}
                className="zv-touch mb-5 -ml-1 inline-flex items-center gap-2 rounded-md px-1 py-2 type-caption font-semibold text-text-secondary transition-colors hover:text-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
              >
                <ArrowLeft className="h-4 w-4" aria-hidden="true" />
                {back.label}
              </Link>
            )}

            <div className="zv-enter rounded-lg border border-border bg-surface p-6 shadow-sm sm:p-8">
              {progress}
              {eyebrow && <p className="type-overline text-brand-green">{eyebrow}</p>}
              <h1 className={cn("type-h1 text-neutral-900", eyebrow ? "mt-2" : progress ? "mt-6" : "")}>
                {title}
              </h1>
              {description && (
                <div className="mt-3 type-body text-text-secondary">{description}</div>
              )}
              <div className="mt-8">{children}</div>
            </div>

            {footer && <div className="mt-6 text-center type-caption text-text-secondary">{footer}</div>}
          </div>
        </div>
      </main>
    </div>
  );
}

/** Inline text link used in auth footers. */
export function AuthLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="rounded-sm font-bold text-neutral-900 underline decoration-neutral-300 underline-offset-4 transition-colors hover:decoration-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
    >
      {children}
    </Link>
  );
}

/** A right-chevron row link, for "what happens next" style lists. */
export function NextStepLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="zv-tap flex min-h-12 items-center justify-between gap-3 rounded-md border border-border bg-surface px-4 py-3 type-body-strong text-neutral-900 transition-colors hover:bg-neutral-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
    >
      <span>{children}</span>
      <ChevronRight className="h-4 w-4 shrink-0 text-text-tertiary" aria-hidden="true" />
    </Link>
  );
}
