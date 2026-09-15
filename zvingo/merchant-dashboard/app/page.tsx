"use client";

import * as React from "react";
import Link from "next/link";
import {
  ArrowRight,
  BadgePercent,
  Bike,
  ChefHat,
  ClipboardList,
  Clock3,
  LineChart,
  MapPin,
  Receipt,
  ShieldCheck,
  Sparkles,
  Store,
  Wallet,
} from "lucide-react";
import { Button } from "@/components/ui";
import { useIsMounted } from "@/lib/hooks";
import { formatMoney } from "@/lib/format";
import { Wordmark } from "./_auth/AuthShell";
import { hasAccessToken } from "./_auth/session";

/* -------------------------------------------------------------------------- */
/* Content                                                                    */
/* -------------------------------------------------------------------------- */

const CAPABILITIES = [
  {
    icon: ClipboardList,
    title: "One screen for the whole rush",
    body:
      "New orders land on a board with a chime you can hear over an extractor fan. Accept, mark ready, done — no paper, no phone calls.",
  },
  {
    icon: ChefHat,
    title: "Your menu, your prices",
    body:
      "Add dishes with photos, set prices in USD and switch anything to sold out the moment the pot is empty. Changes are live immediately.",
  },
  {
    icon: BadgePercent,
    title: "Promotions you actually control",
    body:
      "Run a percentage off, a flat discount, free delivery or a free item. Set the minimum spend, the dates and the usage cap yourself.",
  },
  {
    icon: LineChart,
    title: "Numbers you can read at a glance",
    body:
      "Orders and sales for today and all time, your busiest items, and your average prep time — with ZiG and ZAR at the day’s rate.",
  },
] as const;

const COST_FACTS = [
  {
    icon: Receipt,
    title: "0% commission on your food",
    body: "Your payout is your menu total. Zvingo does not take a cut of what you cook.",
  },
  {
    icon: Bike,
    title: "Delivery is $5 per 5 km",
    body:
      "Charged to the customer, rounded up to the next 5 km block. The driver keeps 85% of it; Zvingo keeps the remaining 15%.",
  },
  {
    icon: Wallet,
    title: "No listing fee, no monthly fee",
    body: "You are not billed for being on Zvingo. If you sell nothing, you pay nothing.",
  },
  {
    icon: ShieldCheck,
    title: "Discounts only come off if you choose",
    body:
      "A promotion Zvingo funds does not touch your payout. A promotion you fund yourself is deducted — and it says so before you launch it.",
  },
] as const;

const STEPS = [
  {
    title: "Create your partner account",
    body: "Your restaurant name, your mobile number and your address. About two minutes.",
  },
  {
    title: "Add your menu and hours",
    body: "Dishes, prices, photos and when you are open. Everything is editable afterwards.",
  },
  {
    title: "Switch your store open",
    body: "You appear in the app straight away. There is no waiting list and no approval queue.",
  },
] as const;

const FAQS = [
  {
    question: "Do I need my own drivers?",
    answer:
      "No. When you mark an order ready, Zvingo offers it to the nearest available driver and keeps offering until someone accepts. You never arrange a courier.",
  },
  {
    question: "What happens when the kitchen is slammed?",
    answer:
      "Pause your store from the dashboard. You disappear from new orders immediately and come back with one tap — customers see you as closed rather than getting a late delivery.",
  },
  {
    question: "Which currencies can I price in?",
    answer:
      "You set your menu in USD. Customers see the ZiG and ZAR equivalent at the day’s rate, and can pay by EcoCash, OneMoney, InnBucks or card through Paynow.",
  },
] as const;

/* The worked example below is the real formula from the pricing engine:
   6 km → ceil(6/5) = 2 blocks → $10.00 gross fee → driver 85%, Zvingo 15%. */
const EXAMPLE = {
  food: 18,
  deliveryFee: 10,
  driverShare: 8.5,
  platformShare: 1.5,
} as const;

/* -------------------------------------------------------------------------- */
/* Page                                                                       */
/* -------------------------------------------------------------------------- */

export default function LandingPage() {
  const mounted = useIsMounted();
  const signedIn = mounted && hasAccessToken();

  return (
    <div className="min-h-screen bg-background">
      <a
        href="#main"
        className="absolute left-4 -top-24 z-50 rounded-md bg-action px-4 py-3 type-button text-neutral-0 transition-[top] focus-visible:top-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-lime"
      >
        Skip to content
      </a>

      <SiteHeader signedIn={signedIn} />

      <main id="main">
        <Hero signedIn={signedIn} />
        <Capabilities />
        <Pricing />
        <HowItWorks />
        <Faq />
        <ClosingCta signedIn={signedIn} />
      </main>

      <SiteFooter />
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Header                                                                     */
/* -------------------------------------------------------------------------- */

function SiteHeader({ signedIn }: { signedIn: boolean }) {
  return (
    <header className="sticky top-0 z-40 border-b border-border/70 bg-surface/85 backdrop-blur">
      <div className="mx-auto flex h-18 max-w-[1180px] items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
        <Link
          href="/"
          className="rounded-md focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-action"
        >
          <Wordmark />
          <span className="zv-sr-only">Zvingo Partner home</span>
        </Link>

        <nav aria-label="Page sections" className="hidden items-center gap-1 md:flex">
          <HeaderLink href="#what-you-get">What you get</HeaderLink>
          <HeaderLink href="#what-it-costs">What it costs</HeaderLink>
          <HeaderLink href="#how-to-start">How to start</HeaderLink>
        </nav>

        <div className="flex items-center gap-2">
          {signedIn ? (
            <Button asChild variant="secondary" size="md">
              <Link href="/dashboard">Go to my dashboard</Link>
            </Button>
          ) : (
            <>
              <Button asChild variant="tertiary" size="md">
                <Link href="/login">Sign in</Link>
              </Button>
              <Button asChild variant="secondary" size="md" className="max-sm:hidden">
                <Link href="/register">Add your restaurant</Link>
              </Button>
            </>
          )}
        </div>
      </div>
    </header>
  );
}

function HeaderLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a
      href={href}
      className="rounded-md px-3 py-2 type-caption font-bold text-text-secondary transition-colors hover:bg-neutral-100 hover:text-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
    >
      {children}
    </a>
  );
}

/* -------------------------------------------------------------------------- */
/* Hero                                                                       */
/* -------------------------------------------------------------------------- */

function Hero({ signedIn }: { signedIn: boolean }) {
  return (
    <section className="border-b border-border bg-surface">
      <div className="mx-auto grid max-w-[1180px] gap-12 px-4 py-14 sm:px-6 sm:py-20 lg:grid-cols-[minmax(0,1.05fr)_minmax(0,0.95fr)] lg:items-center lg:gap-16 lg:px-8 lg:py-24">
        <div className="zv-stagger max-w-xl">
          <p className="type-overline text-brand-green">Zvingo for restaurants</p>
          <h1 className="mt-3 type-display text-neutral-900">
            Your kitchen, on every phone in the city.
          </h1>
          <p className="mt-5 max-w-lg type-h3 font-normal text-text-secondary">
            Zvingo puts your menu in front of people who are already hungry, sends a driver to your door
            when the food is ready, and keeps the whole service on one screen behind the pass.
          </p>

          <div className="mt-8 flex flex-col gap-3 sm:flex-row sm:items-center">
            <Button asChild variant="primary" size="lg" rightIcon={<ArrowRight className="h-[18px] w-[18px]" />}>
              <Link href={signedIn ? "/dashboard" : "/register"}>
                {signedIn ? "Go to my dashboard" : "Add your restaurant"}
              </Link>
            </Button>
            {!signedIn && (
              <p className="type-caption text-text-secondary sm:ml-2">
                Already a partner?{" "}
                <Link
                  href="/login"
                  className="rounded-sm font-bold text-neutral-900 underline decoration-neutral-300 underline-offset-4 transition-colors hover:decoration-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
                >
                  Sign in
                </Link>
              </p>
            )}
          </div>

          <ul className="mt-10 flex flex-wrap gap-x-6 gap-y-3">
            {[
              { icon: Receipt, label: "No commission on your food" },
              { icon: Clock3, label: "Live the same day" },
              { icon: Wallet, label: "USD, ZiG and ZAR" },
            ].map(({ icon: Icon, label }) => (
              <li key={label} className="flex items-center gap-2 type-caption font-semibold text-neutral-800">
                <Icon className="h-4 w-4 text-brand-green" aria-hidden="true" />
                {label}
              </li>
            ))}
          </ul>
        </div>

        <OrderTicket />
      </div>
    </section>
  );
}

/**
 * An illustrative order ticket — clearly labelled as an example so nobody
 * mistakes it for live data. Built only from design tokens, so it reads as the
 * same product as the dashboard behind it.
 */
function OrderTicket() {
  return (
    <figure className="zv-enter relative m-0">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -inset-6 rounded-xl bg-brand-green-surface/70 blur-2xl"
      />
      <div className="relative rounded-xl border border-border bg-surface p-5 shadow-lg sm:p-6">
        <div className="flex items-center justify-between gap-3">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-brand-lime-surface px-2.5 py-1 type-overline text-neutral-900">
            <Sparkles className="h-3 w-3" aria-hidden="true" />
            New order
          </span>
          <span className="type-caption tabular-figures text-text-tertiary">#A93F21</span>
        </div>

        <p className="mt-4 type-h2 text-neutral-900">2 × Peri-peri quarter chicken</p>
        <p className="mt-1 type-body text-text-secondary">1 × Sadza &amp; greens · 1 × Mazoe</p>

        <dl className="mt-5 flex flex-col gap-2 border-t border-divider pt-4">
          <Row label="Food total" value={formatMoney(EXAMPLE.food)} strong />
          <Row label="Delivery (6 km, paid by the customer)" value={formatMoney(EXAMPLE.deliveryFee)} />
        </dl>

        <div className="mt-5 flex items-center gap-3 rounded-md bg-success-surface p-3">
          <Bike className="h-[18px] w-[18px] shrink-0 text-success" aria-hidden="true" />
          <p className="type-caption text-neutral-900">
            <span className="font-bold">Driver assigned</span> — 4 minutes away
          </p>
        </div>

        <div className="mt-5 flex items-center justify-between gap-3 rounded-md border border-border bg-neutral-50 p-3">
          <span className="type-caption text-text-secondary">You receive</span>
          <span className="type-h3 tabular-figures text-neutral-900">{formatMoney(EXAMPLE.food)}</span>
        </div>
      </div>
      <figcaption className="mt-3 text-center type-caption text-text-tertiary">
        Example order — your dashboard shows the real thing.
      </figcaption>
    </figure>
  );
}

function Row({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <dt className="type-caption text-text-secondary">{label}</dt>
      <dd
        className={
          strong
            ? "type-body-strong tabular-figures text-neutral-900"
            : "type-caption tabular-figures text-text-secondary"
        }
      >
        {value}
      </dd>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Capabilities                                                               */
/* -------------------------------------------------------------------------- */

function Section({
  id,
  eyebrow,
  title,
  lead,
  children,
  tone = "default",
}: {
  id?: string;
  eyebrow: string;
  title: string;
  lead?: string;
  children: React.ReactNode;
  tone?: "default" | "muted";
}) {
  return (
    <section
      id={id}
      className={tone === "muted" ? "border-b border-border bg-background" : "border-b border-border bg-surface"}
    >
      <div className="mx-auto max-w-[1180px] px-4 py-16 sm:px-6 sm:py-20 lg:px-8">
        <div className="max-w-2xl">
          <p className="type-overline text-brand-green">{eyebrow}</p>
          <h2 className="mt-3 type-h1 text-neutral-900">{title}</h2>
          {lead && <p className="mt-4 type-body text-text-secondary">{lead}</p>}
        </div>
        <div className="mt-10">{children}</div>
      </div>
    </section>
  );
}

function Capabilities() {
  return (
    <Section
      id="what-you-get"
      eyebrow="What you get"
      title="Everything the front of house never sees."
      lead="Zvingo Partner is the back-office half of Zvingo: the board your team works from during service, and the tools you use between services."
      tone="muted"
    >
      <ul className="zv-stagger grid gap-3 sm:grid-cols-2">
        {CAPABILITIES.map(({ icon: Icon, title, body }) => (
          <li
            key={title}
            className="rounded-lg border border-border bg-surface p-5 shadow-sm transition-shadow hover:shadow-md sm:p-6"
          >
            <span
              aria-hidden="true"
              className="flex h-10 w-10 items-center justify-center rounded-md bg-brand-green-surface text-brand-green"
            >
              <Icon className="h-5 w-5" />
            </span>
            <h3 className="mt-4 type-h3 text-neutral-900">{title}</h3>
            <p className="mt-2 type-body text-text-secondary">{body}</p>
          </li>
        ))}
      </ul>
    </Section>
  );
}

/* -------------------------------------------------------------------------- */
/* Pricing                                                                    */
/* -------------------------------------------------------------------------- */

function Pricing() {
  return (
    <Section
      id="what-it-costs"
      eyebrow="What it costs"
      title="Zvingo earns from the delivery, not from your kitchen."
      lead="Here is the whole commission model, in the order the money moves. No tier tables, no hidden percentage on your food."
    >
      <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.85fr)] lg:gap-10">
        <ul className="zv-stagger flex flex-col gap-3">
          {COST_FACTS.map(({ icon: Icon, title, body }) => (
            <li key={title} className="flex gap-4 rounded-lg border border-border bg-surface p-5 shadow-sm">
              <span
                aria-hidden="true"
                className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-neutral-100 text-neutral-900"
              >
                <Icon className="h-5 w-5" />
              </span>
              <div className="min-w-0">
                <h3 className="type-h3 text-neutral-900">{title}</h3>
                <p className="mt-1.5 type-body text-text-secondary">{body}</p>
              </div>
            </li>
          ))}
        </ul>

        <aside className="zv-enter rounded-lg border border-border bg-neutral-900 p-6 text-neutral-0 shadow-md">
          <p className="type-overline text-brand-lime">Worked example</p>
          <h3 className="mt-3 type-h2 text-neutral-0">
            A {formatMoney(EXAMPLE.food)} order, delivered 6 km.
          </h3>
          <p className="mt-3 type-caption font-normal text-neutral-300">
            Six kilometres rounds up to two 5 km blocks, so the customer pays{" "}
            {formatMoney(EXAMPLE.deliveryFee)} for delivery on top of the food.
          </p>

          <dl className="mt-6 flex flex-col gap-3 border-t border-neutral-0/15 pt-5">
            <SplitRow label="You receive" value={formatMoney(EXAMPLE.food)} emphasis />
            <SplitRow label="The driver receives" value={formatMoney(EXAMPLE.driverShare)} />
            <SplitRow label="Zvingo receives" value={formatMoney(EXAMPLE.platformShare)} />
          </dl>

          <p className="mt-6 type-caption font-normal text-neutral-400">
            The customer pays {formatMoney(EXAMPLE.food + EXAMPLE.deliveryFee)} in total. Every cent of the
            food is yours.
          </p>
        </aside>
      </div>
    </Section>
  );
}

function SplitRow({ label, value, emphasis }: { label: string; value: string; emphasis?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <dt className={emphasis ? "type-body-strong text-neutral-0" : "type-body text-neutral-300"}>{label}</dt>
      <dd
        className={
          emphasis
            ? "type-h2 tabular-figures text-brand-lime"
            : "type-body-strong tabular-figures text-neutral-0"
        }
      >
        {value}
      </dd>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* How it works                                                               */
/* -------------------------------------------------------------------------- */

function HowItWorks() {
  return (
    <Section
      id="how-to-start"
      eyebrow="How to start"
      title="Three steps, and you are taking orders."
      lead="You need a Zimbabwean mobile number, your restaurant’s address, and your menu. That is the whole list."
      tone="muted"
    >
      <ol className="zv-stagger grid gap-3 md:grid-cols-3">
        {STEPS.map((step, index) => (
          <li key={step.title} className="rounded-lg border border-border bg-surface p-6 shadow-sm">
            <span
              aria-hidden="true"
              className="flex h-10 w-10 items-center justify-center rounded-full bg-action type-h3 text-neutral-0 tabular-figures"
            >
              {index + 1}
            </span>
            <h3 className="mt-4 type-h3 text-neutral-900">{step.title}</h3>
            <p className="mt-2 type-body text-text-secondary">{step.body}</p>
          </li>
        ))}
      </ol>

      <div className="mt-6 flex items-start gap-3 rounded-lg border border-border bg-surface p-5 shadow-sm">
        <MapPin className="mt-0.5 h-[18px] w-[18px] shrink-0 text-brand-green" aria-hidden="true" />
        <p className="type-body text-text-secondary">
          You will be asked to place your restaurant on the map during sign-up. That pin is what dispatch
          uses to work out which driver is nearest and what the delivery costs, so it is worth getting right
          — you can share your current location if you are standing in the shop.
        </p>
      </div>
    </Section>
  );
}

/* -------------------------------------------------------------------------- */
/* FAQ                                                                        */
/* -------------------------------------------------------------------------- */

function Faq() {
  return (
    <Section eyebrow="Before you ask" title="The three questions every owner asks first.">
      <div className="zv-stagger flex max-w-3xl flex-col gap-3">
        {FAQS.map(({ question, answer }) => (
          <details
            key={question}
            className="group rounded-lg border border-border bg-surface px-5 py-4 shadow-sm open:shadow-md"
          >
            <summary className="flex cursor-pointer list-none items-center justify-between gap-4 type-h3 text-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action">
              {question}
              <span
                aria-hidden="true"
                className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-neutral-100 text-neutral-900 transition-transform group-open:rotate-45"
              >
                +
              </span>
            </summary>
            <p className="mt-3 type-body text-text-secondary">{answer}</p>
          </details>
        ))}
      </div>
    </Section>
  );
}

/* -------------------------------------------------------------------------- */
/* Closing                                                                    */
/* -------------------------------------------------------------------------- */

function ClosingCta({ signedIn }: { signedIn: boolean }) {
  return (
    <section className="bg-neutral-900">
      <div className="mx-auto max-w-[1180px] px-4 py-16 sm:px-6 sm:py-20 lg:px-8">
        <div className="zv-enter flex flex-col items-start gap-8 lg:flex-row lg:items-center lg:justify-between">
          <div className="max-w-xl">
            <span
              aria-hidden="true"
              className="flex h-11 w-11 items-center justify-center rounded-md bg-neutral-0/10 text-brand-lime"
            >
              <Store className="h-5 w-5" />
            </span>
            <h2 className="mt-5 type-h1 text-neutral-0">Put tonight’s service on Zvingo.</h2>
            <p className="mt-4 type-body text-neutral-300">
              Setting up takes about two minutes and costs nothing. You can be taking your first order
              before the dinner rush.
            </p>
          </div>

          <Button
            asChild
            size="lg"
            className="bg-neutral-0 text-neutral-900 hover:bg-neutral-100 active:bg-neutral-200 max-lg:w-full"
            rightIcon={<ArrowRight className="h-[18px] w-[18px]" />}
          >
            <Link href={signedIn ? "/dashboard" : "/register"}>
              {signedIn ? "Go to my dashboard" : "Add your restaurant"}
            </Link>
          </Button>
        </div>
      </div>
    </section>
  );
}

function SiteFooter() {
  return (
    <footer className="border-t border-border bg-surface">
      <div className="mx-auto flex max-w-[1180px] flex-col gap-6 px-4 py-10 sm:px-6 lg:flex-row lg:items-center lg:justify-between lg:px-8">
        <div>
          <Wordmark />
          <p className="mt-3 max-w-md type-caption text-text-secondary">
            Zvingo Partner is the restaurant side of Zvingo — food delivery built for Zimbabwe, priced in
            USD, ZiG and ZAR.
          </p>
        </div>
        <nav aria-label="Account" className="flex flex-wrap items-center gap-x-6 gap-y-2">
          <FooterLink href="/login">Sign in</FooterLink>
          <FooterLink href="/register">Add your restaurant</FooterLink>
          <FooterLink href="/forgot-password">Reset your password</FooterLink>
        </nav>
      </div>
    </footer>
  );
}

function FooterLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="zv-touch rounded-md py-2 type-caption font-bold text-neutral-900 transition-colors hover:text-brand-green focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
    >
      {children}
    </Link>
  );
}
