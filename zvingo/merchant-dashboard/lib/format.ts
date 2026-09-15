/**
 * Zvingo formatting helpers — Zimbabwe-first locale rules.
 *
 * Money ALWAYS renders with an explicit currency symbol and tabular figures
 * (DESIGN_SYSTEM §2). Never assume US formatting: the platform trades in USD
 * (primary), ZiG and ZAR, and phone numbers are E.164 +263.
 */

export type CurrencyCode = "USD" | "ZIG" | "ZAR";

type CurrencyMeta = {
  code: CurrencyCode;
  /** Short symbol placed before the amount. */
  symbol: string;
  /** Spoken/long name, for accessible labels and selects. */
  label: string;
  decimals: number;
};

export const CURRENCIES: Record<CurrencyCode, CurrencyMeta> = {
  USD: { code: "USD", symbol: "$", label: "US Dollar", decimals: 2 },
  ZIG: { code: "ZIG", symbol: "ZiG", label: "Zimbabwe Gold", decimals: 2 },
  ZAR: { code: "ZAR", symbol: "R", label: "South African Rand", decimals: 2 },
};

export const DEFAULT_CURRENCY: CurrencyCode = "USD";

function normaliseCurrency(input?: string | null): CurrencyMeta {
  if (!input) return CURRENCIES[DEFAULT_CURRENCY];
  const key = input.trim().toUpperCase();
  if (key === "ZWG" || key === "ZIG" || key === "ZWL") return CURRENCIES.ZIG;
  if (key in CURRENCIES) return CURRENCIES[key as CurrencyCode];
  return CURRENCIES[DEFAULT_CURRENCY];
}

export interface MoneyOptions {
  currency?: string | null;
  /** Hide the symbol (for inputs and edit fields). Default false. */
  bare?: boolean;
  /** Force a +/- sign. Useful for deltas and adjustments. */
  signed?: boolean;
  /** Drop the decimals when the value is a whole number. Default false. */
  compactZeros?: boolean;
}

/**
 * Format an amount with its currency symbol, e.g. `$12.50`, `ZiG 168.75`, `R230.00`.
 * Always pair with the `tabular-figures` class so digits do not jitter.
 */
export function formatMoney(value: number | null | undefined, options: MoneyOptions = {}): string {
  const meta = normaliseCurrency(options.currency);
  const amount = Number.isFinite(value) ? (value as number) : 0;
  const abs = Math.abs(amount);

  const fractionDigits =
    options.compactZeros && Number.isInteger(abs) ? 0 : meta.decimals;

  const digits = new Intl.NumberFormat("en-US", {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  }).format(abs);

  if (options.bare) {
    return amount < 0 ? `-${digits}` : options.signed && amount > 0 ? `+${digits}` : digits;
  }

  // ZiG is a multi-letter symbol; it reads better with a space.
  const joiner = meta.symbol.length > 1 ? " " : "";
  const body = `${meta.symbol}${joiner}${digits}`;

  if (amount < 0) return `-${body}`;
  if (options.signed && amount > 0) return `+${body}`;
  return body;
}

/** The bare symbol for a currency code, e.g. for input prefixes. */
export function currencySymbol(code?: string | null): string {
  return normaliseCurrency(code).symbol;
}

/** Human label for a currency code, e.g. for a `<Select>`. */
export function currencyLabel(code?: string | null): string {
  return normaliseCurrency(code).label;
}

/** Convert a USD amount using a rate table from `GET /finance/rates`. */
export function convertFromUsd(
  amountUsd: number,
  target: string | null | undefined,
  rates: Record<string, number> | null | undefined,
): number {
  const meta = normaliseCurrency(target);
  if (meta.code === "USD") return amountUsd;
  const rate = rates?.[meta.code];
  if (!rate || !Number.isFinite(rate)) return amountUsd;
  return amountUsd * rate;
}

/* -------------------------------------------------------------------------- */
/* Numbers                                                                    */
/* -------------------------------------------------------------------------- */

export function formatNumber(value: number | null | undefined, maximumFractionDigits = 0): string {
  const n = Number.isFinite(value) ? (value as number) : 0;
  return new Intl.NumberFormat("en-US", { maximumFractionDigits }).format(n);
}

/** `1.2k`, `48`, `3.4M` — for dense KPI tiles. */
export function formatCompactNumber(value: number | null | undefined): string {
  const n = Number.isFinite(value) ? (value as number) : 0;
  return new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 }).format(n);
}

/** `+12.4%` / `-3%`. Returns `—` when there is no comparable baseline. */
export function formatPercentDelta(
  current: number | null | undefined,
  previous: number | null | undefined,
): string {
  const a = Number.isFinite(current) ? (current as number) : 0;
  const b = Number.isFinite(previous) ? (previous as number) : 0;
  if (!b) return a ? "New" : "—";
  const delta = ((a - b) / Math.abs(b)) * 100;
  const rounded = Math.abs(delta) >= 10 ? Math.round(delta) : Math.round(delta * 10) / 10;
  return `${rounded > 0 ? "+" : ""}${rounded}%`;
}

/* -------------------------------------------------------------------------- */
/* Time                                                                       */
/* -------------------------------------------------------------------------- */

function toDate(input: string | number | Date | null | undefined): Date | null {
  if (input === null || input === undefined) return null;
  if (input instanceof Date) return Number.isNaN(input.getTime()) ? null : input;
  // The API emits naive UTC ISO strings for some documents; treat a timestamp
  // without a zone designator as UTC rather than as browser-local time.
  const raw =
    typeof input === "string" && /^\d{4}-\d{2}-\d{2}T[\d:.]+$/.test(input) ? `${input}Z` : input;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? null : date;
}

/** `Just now`, `4 min ago`, `2 h 10 min ago`, `Yesterday`, `14 Mar`. */
export function formatRelativeTime(
  input: string | number | Date | null | undefined,
  now: number = Date.now(),
): string {
  const date = toDate(input);
  if (!date) return "—";
  const diffMs = now - date.getTime();
  const future = diffMs < 0;
  const mins = Math.floor(Math.abs(diffMs) / 60_000);

  if (mins < 1) return "Just now";
  if (mins < 60) return future ? `in ${mins} min` : `${mins} min ago`;

  const hours = Math.floor(mins / 60);
  const rem = mins % 60;
  if (hours < 24) {
    const label = rem ? `${hours} h ${rem} min` : `${hours} h`;
    return future ? `in ${label}` : `${label} ago`;
  }

  const days = Math.floor(hours / 24);
  if (days === 1) return future ? "Tomorrow" : "Yesterday";
  if (days < 7) return future ? `in ${days} days` : `${days} days ago`;

  return new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short" }).format(date);
}

/** Elapsed minutes since a timestamp — the number a kitchen actually cares about. */
export function minutesSince(
  input: string | number | Date | null | undefined,
  now: number = Date.now(),
): number {
  const date = toDate(input);
  if (!date) return 0;
  return Math.max(0, Math.floor((now - date.getTime()) / 60_000));
}

/** `8 min`, `1 h 04 min` — for order age and prep timers. */
export function formatDuration(minutes: number | null | undefined): string {
  const m = Math.max(0, Math.round(Number.isFinite(minutes) ? (minutes as number) : 0));
  if (m < 1) return "Just now";
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  const rem = m % 60;
  return rem ? `${h} h ${String(rem).padStart(2, "0")} min` : `${h} h`;
}

/** `14:35` — 24-hour clock, which is what Zimbabwean rosters use. */
export function formatTime(input: string | number | Date | null | undefined): string {
  const date = toDate(input);
  if (!date) return "—";
  return new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false }).format(date);
}

/** `14 Mar 2026, 14:35`. */
export function formatDateTime(input: string | number | Date | null | undefined): string {
  const date = toDate(input);
  if (!date) return "—";
  return new Intl.DateTimeFormat("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
}

/** `14 Mar 2026`. */
export function formatDate(input: string | number | Date | null | undefined): string {
  const date = toDate(input);
  if (!date) return "—";
  return new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric" }).format(date);
}

/** `2026-03-14T12:00` for a `datetime-local` input. */
export function toDateTimeLocalValue(input: string | number | Date | null | undefined): string {
  const date = toDate(input);
  if (!date) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/* -------------------------------------------------------------------------- */
/* Distance                                                                   */
/* -------------------------------------------------------------------------- */

/** `450 m`, `2.4 km`, `18 km` — metric, because Zimbabwe is metric. */
export function formatDistance(metres: number | null | undefined): string {
  const m = Number.isFinite(metres) ? Math.max(0, metres as number) : 0;
  if (m < 1000) return `${Math.round(m / 10) * 10} m`;
  const km = m / 1000;
  return km < 10 ? `${km.toFixed(1)} km` : `${Math.round(km)} km`;
}

/** Great-circle distance in metres between two lat/lng pairs. */
export function haversineMetres(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6_371_000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.sin(dLng / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2);
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/* -------------------------------------------------------------------------- */
/* Phone — E.164, Zimbabwe default                                            */
/* -------------------------------------------------------------------------- */

const ZW_COUNTRY_CODE = "263";

/**
 * Normalise local Zimbabwean input (`0771234567`, `771234567`, `+263 77 123 4567`)
 * to strict E.164 (`+263771234567`). Returns `null` when it cannot be trusted,
 * so callers can show an error instead of posting garbage to the API.
 */
export function toE164(input: string | null | undefined, countryCode = ZW_COUNTRY_CODE): string | null {
  if (!input) return null;
  let digits = input.replace(/[^\d+]/g, "");
  if (digits.startsWith("+")) digits = digits.slice(1);
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.startsWith(countryCode)) {
    digits = digits.slice(countryCode.length);
  } else if (digits.startsWith("0")) {
    digits = digits.slice(1);
  }
  if (!/^\d{9}$/.test(digits)) return null;
  return `+${countryCode}${digits}`;
}

/** True when a string is already valid strict E.164 for Zimbabwe. */
export function isValidZwPhone(input: string | null | undefined): boolean {
  return toE164(input) !== null;
}

/** `+263 77 123 4567` — grouped for reading aloud over a noisy kitchen. */
export function formatPhone(input: string | null | undefined): string {
  const e164 = toE164(input);
  if (!e164) return input?.trim() || "—";
  const national = e164.slice(1 + ZW_COUNTRY_CODE.length);
  return `+${ZW_COUNTRY_CODE} ${national.slice(0, 2)} ${national.slice(2, 5)} ${national.slice(5)}`;
}

/** `tel:` href built from any accepted input shape. */
export function telHref(input: string | null | undefined): string | undefined {
  const e164 = toE164(input);
  return e164 ? `tel:${e164}` : undefined;
}

/* -------------------------------------------------------------------------- */
/* Misc                                                                       */
/* -------------------------------------------------------------------------- */

/** `#A93F21` — short, readable order reference from a Mongo id. */
export function formatOrderRef(id: string | null | undefined): string {
  if (!id) return "—";
  return `#${id.slice(-6).toUpperCase()}`;
}

/** `ORDER_READY` / `OrderState.DELIVERED` → `Ready`. */
export function humaniseState(state: string | null | undefined): string {
  if (!state) return "—";
  const bare = state.replace(/^OrderState\./, "").replace(/_/g, " ").trim().toLowerCase();
  return bare.charAt(0).toUpperCase() + bare.slice(1);
}

export function pluralise(count: number, singular: string, plural = `${singular}s`): string {
  return `${count} ${Math.abs(count) === 1 ? singular : plural}`;
}

/** Initials for an avatar, max two letters. */
export function initials(name: string | null | undefined, fallback = "ZP"): string {
  const parts = (name || "").trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return fallback;
  return parts.slice(0, 2).map((p) => p[0]!.toUpperCase()).join("");
}
