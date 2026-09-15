"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  Banknote,
  Building2,
  Check,
  Clock,
  Copy,
  Crosshair,
  Info,
  LocateFixed,
  LogOut,
  Mail,
  MapPin,
  Minus,
  Phone,
  Plus,
  Search,
  ShieldCheck,
  Store,
  Trash2,
  X,
} from "lucide-react";
import { PageContainer, PageSection } from "@/components/AppShell";
import ImageUpload from "@/components/ImageUpload";
import StoreStatusPill, {
  DAY_LABELS,
  DAY_SHORT,
  fetchStoreStatus,
  localClock,
  localDayLabel,
  patchStoreStatus,
  statusTone,
  storeStatusKey,
  type Availability,
  type DayHours,
  type HoursInterval,
  type RestaurantStatus,
} from "@/components/merchant/StoreStatus";
import {
  Badge,
  Button,
  Card,
  ConfirmDialog,
  ErrorState,
  IconButton,
  Input,
  RadioGroup,
  Select,
  Skeleton,
  StatusPill,
  Switch,
  Textarea,
  Tooltip,
  useToast,
} from "@/components/ui";
import { api, clearAuth, endpoints, type Restaurant } from "@/lib/api";
import { clearApiCache, useApi, useMerchantSession } from "@/lib/useApi";
import { formatMoney, formatPhone } from "@/lib/format";

const MAP_TILE_URL =
  process.env.NEXT_PUBLIC_MAP_TILE_URL || "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

const TIMEZONES = [
  { value: "Africa/Harare", label: "Africa/Harare (CAT, UTC+2)" },
  { value: "Africa/Johannesburg", label: "Africa/Johannesburg (SAST, UTC+2)" },
  { value: "Africa/Lusaka", label: "Africa/Lusaka (CAT, UTC+2)" },
  { value: "UTC", label: "UTC" },
];

/* -------------------------------------------------------------------------- */
/* Unsaved-changes guard                                                      */
/* -------------------------------------------------------------------------- */

/**
 * A shift manager must not lose half an hour of edits by clicking "Orders".
 * Guards both the browser chrome (reload/close) and in-app navigation, which
 * the App Router gives no official hook for — so internal anchor clicks are
 * intercepted in the capture phase and replayed after the manager confirms.
 */
function useUnsavedGuard(dirty: boolean) {
  const router = useRouter();
  const [pendingHref, setPendingHref] = React.useState<string | null>(null);
  const dirtyRef = React.useRef(dirty);
  React.useEffect(() => {
    dirtyRef.current = dirty;
  }, [dirty]);

  React.useEffect(() => {
    if (!dirty) return;
    const onBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => window.removeEventListener("beforeunload", onBeforeUnload);
  }, [dirty]);

  React.useEffect(() => {
    const onClick = (event: MouseEvent) => {
      if (!dirtyRef.current) return;
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey) return;
      const anchor = (event.target as HTMLElement | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!anchor || anchor.target === "_blank" || anchor.hasAttribute("download")) return;
      const href = anchor.getAttribute("href") || "";
      if (!href.startsWith("/") || href.startsWith("//")) return;
      if (href === window.location.pathname) return;
      event.preventDefault();
      event.stopPropagation();
      setPendingHref(href);
    };
    document.addEventListener("click", onClick, true);
    return () => document.removeEventListener("click", onClick, true);
  }, []);

  const dialog = (
    <ConfirmDialog
      open={pendingHref !== null}
      tone="warning"
      title="Leave without saving?"
      consequence="You have edits on this page that have not been saved. Leaving now discards them — they are not kept as a draft."
      confirmLabel="Discard and leave"
      cancelLabel="Stay and save"
      onCancel={() => setPendingHref(null)}
      onConfirm={() => {
        const href = pendingHref;
        setPendingHref(null);
        if (href) router.push(href);
      }}
    />
  );

  return dialog;
}

/* -------------------------------------------------------------------------- */
/* Section shell — one save button per section, with its own dirty state      */
/* -------------------------------------------------------------------------- */

function SettingsSection({
  title,
  description,
  icon: Icon,
  dirty,
  saving,
  disabled,
  disabledReason,
  onSave,
  onReset,
  saveLabel = "Save",
  children,
  footerNote,
}: {
  title: string;
  description?: string;
  icon: React.ElementType;
  dirty: boolean;
  saving: boolean;
  disabled?: boolean;
  disabledReason?: string;
  onSave: () => void;
  onReset: () => void;
  saveLabel?: string;
  children: React.ReactNode;
  footerNote?: React.ReactNode;
}) {
  return (
    <Card flush as="section" className="overflow-hidden">
      <header className="flex items-start gap-3 border-b border-divider p-4">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-neutral-100 text-neutral-700">
          <Icon className="h-5 w-5" aria-hidden="true" />
        </span>
        <div className="min-w-0 flex-1">
          <h2 className="type-h3 text-text-primary">{title}</h2>
          {description && <p className="type-caption mt-0.5 text-text-secondary">{description}</p>}
        </div>
        {dirty && <Badge tone="warning">Unsaved</Badge>}
      </header>

      <div className="space-y-4 p-4">{children}</div>

      <footer className="flex flex-wrap items-center justify-between gap-3 border-t border-divider bg-neutral-50 px-4 py-3">
        <p className="type-caption text-text-secondary">
          {footerNote ?? (disabled && disabledReason) ?? (dirty ? "Unsaved changes on this section." : "Everything here is saved.")}
        </p>
        <div className="flex items-center gap-2">
          {dirty && (
            <Button variant="tertiary" size="md" onClick={onReset} disabled={saving}>
              Discard
            </Button>
          )}
          <Button
            variant="secondary"
            size="md"
            onClick={onSave}
            loading={saving}
            disabled={disabled || !dirty}
            leftIcon={dirty ? undefined : <Check className="h-4 w-4" />}
          >
            {dirty ? saveLabel : "Saved"}
          </Button>
        </div>
      </footer>
    </Card>
  );
}

/* -------------------------------------------------------------------------- */
/* Map: a small slippy map with a pin the merchant drags                      */
/* -------------------------------------------------------------------------- */

const TILE = 256;

function lngToTileX(lng: number, zoom: number) {
  return ((lng + 180) / 360) * 2 ** zoom;
}
function latToTileY(lat: number, zoom: number) {
  const clamped = Math.max(-85.05112878, Math.min(85.05112878, lat));
  const rad = (clamped * Math.PI) / 180;
  return ((1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2) * 2 ** zoom;
}
function tileXToLng(x: number, zoom: number) {
  return (x / 2 ** zoom) * 360 - 180;
}
function tileYToLat(y: number, zoom: number) {
  const n = Math.PI - (2 * Math.PI * y) / 2 ** zoom;
  return (180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
}

interface Coords {
  lat: number;
  lng: number;
}

interface GeocodeHit {
  display_name: string;
  lat: number;
  lng: number;
  type: string;
}

/**
 * Pickup-point picker. Raster tiles are drawn as CSS backgrounds (no image
 * elements, no map dependency) and OpenStreetMap attribution is always on
 * screen, which its licence requires.
 */
function LocationPicker({
  value,
  onChange,
  disabled,
}: {
  value: Coords | null;
  onChange: (next: Coords) => void;
  disabled?: boolean;
}) {
  const [zoom, setZoom] = React.useState(15);
  const [centre, setCentre] = React.useState<Coords>(value ?? { lat: -17.8252, lng: 31.0335 });
  const [size, setSize] = React.useState({ width: 640, height: 260 });
  const [locating, setLocating] = React.useState(false);
  const [locateError, setLocateError] = React.useState("");
  const frameRef = React.useRef<HTMLDivElement>(null);
  const dragRef = React.useRef<{ mode: "pan" | "pin"; x: number; y: number; centre: Coords } | null>(null);

  // Re-centre when the pin moves far outside the current view (e.g. a search hit).
  React.useEffect(() => {
    if (!value) return;
    setCentre((prev) =>
      Math.abs(prev.lat - value.lat) > 0.02 || Math.abs(prev.lng - value.lng) > 0.02 ? value : prev,
    );
  }, [value]);

  React.useEffect(() => {
    const element = frameRef.current;
    if (!element || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(([entry]) => {
      if (!entry) return;
      setSize({
        width: Math.max(160, Math.round(entry.contentRect.width)),
        height: Math.max(160, Math.round(entry.contentRect.height)),
      });
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const originX = lngToTileX(centre.lng, zoom) * TILE - size.width / 2;
  const originY = latToTileY(centre.lat, zoom) * TILE - size.height / 2;

  const tiles: Array<{ key: string; left: number; top: number; url: string }> = [];
  const scale = 2 ** zoom;
  const firstX = Math.floor(originX / TILE);
  const lastX = Math.floor((originX + size.width) / TILE);
  const firstY = Math.floor(originY / TILE);
  const lastY = Math.floor((originY + size.height) / TILE);
  for (let x = firstX; x <= lastX; x += 1) {
    for (let y = firstY; y <= lastY; y += 1) {
      if (y < 0 || y >= scale) continue;
      const wrappedX = ((x % scale) + scale) % scale;
      tiles.push({
        key: `${zoom}-${x}-${y}`,
        left: x * TILE - originX,
        top: y * TILE - originY,
        url: MAP_TILE_URL.replace("{z}", String(zoom))
          .replace("{x}", String(wrappedX))
          .replace("{y}", String(y)),
      });
    }
  }

  const pinLeft = value ? lngToTileX(value.lng, zoom) * TILE - originX : size.width / 2;
  const pinTop = value ? latToTileY(value.lat, zoom) * TILE - originY : size.height / 2;
  const pinVisible =
    pinLeft >= -40 && pinLeft <= size.width + 40 && pinTop >= -60 && pinTop <= size.height + 40;

  function pixelToCoords(left: number, top: number): Coords {
    return {
      lat: tileYToLat((originY + top) / TILE, zoom),
      lng: tileXToLng((originX + left) / TILE, zoom),
    };
  }

  function beginDrag(mode: "pan" | "pin", event: React.PointerEvent) {
    if (disabled) return;
    (event.currentTarget as HTMLElement).setPointerCapture?.(event.pointerId);
    dragRef.current = { mode, x: event.clientX, y: event.clientY, centre };
    event.preventDefault();
  }

  function onPointerMove(event: React.PointerEvent) {
    const drag = dragRef.current;
    if (!drag) return;
    const dx = event.clientX - drag.x;
    const dy = event.clientY - drag.y;

    if (drag.mode === "pan") {
      const baseX = lngToTileX(drag.centre.lng, zoom) * TILE;
      const baseY = latToTileY(drag.centre.lat, zoom) * TILE;
      setCentre({
        lng: tileXToLng((baseX - dx) / TILE, zoom),
        lat: tileYToLat((baseY - dy) / TILE, zoom),
      });
      return;
    }

    const rect = frameRef.current?.getBoundingClientRect();
    if (!rect) return;
    onChange(pixelToCoords(event.clientX - rect.left, event.clientY - rect.top));
  }

  function endDrag(event: React.PointerEvent) {
    (event.currentTarget as HTMLElement).releasePointerCapture?.(event.pointerId);
    dragRef.current = null;
  }

  function nudge(deltaLat: number, deltaLng: number) {
    if (!value || disabled) return;
    const step = 360 / (2 ** zoom * TILE); // one screen pixel in degrees of longitude
    onChange({ lat: value.lat + deltaLat * step, lng: value.lng + deltaLng * step });
  }

  function useMyLocation() {
    if (!navigator.geolocation) {
      setLocateError("This browser cannot share its location. Type the address instead, or drag the pin.");
      return;
    }
    setLocating(true);
    setLocateError("");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        const next = { lat: position.coords.latitude, lng: position.coords.longitude };
        onChange(next);
        setCentre(next);
        setZoom((z) => Math.max(z, 16));
        setLocating(false);
      },
      (error) => {
        setLocating(false);
        setLocateError(
          error.code === error.PERMISSION_DENIED
            ? "Your browser blocked location access. Allow it in the address bar, or drag the pin to your door."
            : "We could not work out where you are. Drag the pin to your door instead.",
        );
      },
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 60_000 },
    );
  }

  return (
    <div className="space-y-3">
      <div
        ref={frameRef}
        onPointerDown={(e) => beginDrag("pan", e)}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        className="relative h-64 w-full touch-none select-none overflow-hidden rounded-lg border border-border bg-neutral-100"
        style={{ cursor: disabled ? "not-allowed" : "grab" }}
        role="group"
        aria-label="Map showing the pickup point. Drag to pan, or use the latitude and longitude fields below."
      >
        {tiles.map((tile) => (
          <div
            key={tile.key}
            aria-hidden="true"
            className="absolute bg-neutral-200 bg-cover"
            style={{
              left: tile.left,
              top: tile.top,
              width: TILE,
              height: TILE,
              backgroundImage: `url("${tile.url}")`,
            }}
          />
        ))}

        {pinVisible && (
          <button
            type="button"
            disabled={disabled}
            onPointerDown={(e) => {
              e.stopPropagation();
              beginDrag("pin", e);
            }}
            onPointerMove={onPointerMove}
            onPointerUp={endDrag}
            onKeyDown={(e) => {
              const map: Record<string, [number, number]> = {
                ArrowUp: [1, 0],
                ArrowDown: [-1, 0],
                ArrowLeft: [0, -1],
                ArrowRight: [0, 1],
              };
              const move = map[e.key];
              if (!move) return;
              e.preventDefault();
              const factor = e.shiftKey ? 20 : 4;
              nudge(move[0] * factor, move[1] * factor);
            }}
            className="absolute z-10 -translate-x-1/2 -translate-y-full cursor-grab focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-action"
            style={{ left: pinLeft, top: pinTop }}
            aria-label="Pickup point. Drag it, or use the arrow keys to move it."
          >
            <MapPin className="h-9 w-9 fill-deal text-neutral-0 drop-shadow-[0_2px_4px_rgba(16,18,16,0.35)]" />
          </button>
        )}

        <div className="absolute right-2 top-2 z-10 flex flex-col gap-1">
          <IconButton
            label="Zoom in"
            tone="secondary"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => setZoom((z) => Math.min(19, z + 1))}
            className="bg-neutral-0"
          />
          <IconButton
            label="Zoom out"
            tone="secondary"
            icon={<Minus className="h-4 w-4" />}
            onClick={() => setZoom((z) => Math.max(3, z - 1))}
            className="bg-neutral-0"
          />
          {value && (
            <IconButton
              label="Centre the map on the pin"
              tone="secondary"
              icon={<Crosshair className="h-4 w-4" />}
              onClick={() => setCentre(value)}
              className="bg-neutral-0"
            />
          )}
        </div>

        <p className="absolute bottom-0 right-0 z-10 rounded-tl-sm bg-neutral-0/85 px-1.5 py-0.5 type-caption text-text-secondary">
          ©{" "}
          <a
            href="https://www.openstreetmap.org/copyright"
            target="_blank"
            rel="noreferrer noopener"
            className="underline"
          >
            OpenStreetMap
          </a>{" "}
          contributors
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <Button
          type="button"
          variant="secondary"
          size="md"
          onClick={useMyLocation}
          loading={locating}
          disabled={disabled}
          leftIcon={<LocateFixed className="h-4 w-4" />}
        >
          Use my current location
        </Button>
        <Tooltip content="Drag the pin, or type exact coordinates below.">
          <span className="type-caption text-text-secondary">
            {value
              ? `Pin at ${value.lat.toFixed(5)}, ${value.lng.toFixed(5)}`
              : "No pickup point set yet"}
          </span>
        </Tooltip>
      </div>

      {locateError && (
        <p role="alert" className="type-caption text-error">
          {locateError}
        </p>
      )}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Opening-hours editor                                                       */
/* -------------------------------------------------------------------------- */

type Week = DayHours[];

function emptyWeek(): Week {
  return Array.from({ length: 7 }, (_, day) => ({ day, intervals: [] as HoursInterval[] }));
}

function weekFromStatus(hours: DayHours[] | undefined): Week {
  const week = emptyWeek();
  (hours ?? []).forEach((entry) => {
    const slot = week[entry.day];
    if (slot) slot.intervals = entry.intervals.map((i) => ({ open: i.open, close: i.close }));
  });
  return week;
}

function minutesOf(value: string): number {
  const [h, m] = value.split(":");
  return (Number(h) || 0) * 60 + (Number(m) || 0);
}

/** Client-side copy of the backend's overlap rule, so errors arrive instantly. */
function weekProblems(week: Week): string[] {
  const problems: string[] = [];
  week.forEach((day) => {
    const spans = day.intervals
      .map((interval) => {
        const start = minutesOf(interval.open);
        let end = minutesOf(interval.close);
        if (end <= start) end += 24 * 60;
        return { start, end };
      })
      .sort((a, b) => a.start - b.start);
    for (let i = 1; i < spans.length; i += 1) {
      if (spans[i]!.start < spans[i - 1]!.end) {
        problems.push(`${DAY_LABELS[day.day]} has two opening times that overlap.`);
        break;
      }
    }
    day.intervals.forEach((interval) => {
      if (!/^\d{2}:\d{2}$/.test(interval.open) || !/^\d{2}:\d{2}$/.test(interval.close)) {
        problems.push(`${DAY_LABELS[day.day]} has an incomplete opening time.`);
      }
    });
  });
  return Array.from(new Set(problems));
}

function describeDay(day: DayHours): string {
  if (!day.intervals.length) return "Closed";
  return day.intervals
    .map((i) => (i.open === i.close ? "Open 24 hours" : `${i.open}–${i.close}`))
    .join(", ");
}

function HoursEditor({
  week,
  onChange,
  disabled,
}: {
  week: Week;
  onChange: (next: Week) => void;
  disabled?: boolean;
}) {
  function patchDay(day: number, intervals: HoursInterval[]) {
    onChange(week.map((entry) => (entry.day === day ? { ...entry, intervals } : entry)));
  }

  return (
    <div className="space-y-2">
      {week.map((day) => {
        const open = day.intervals.length > 0;
        return (
          <div
            key={day.day}
            className="grid gap-3 rounded-md border border-border p-3 sm:grid-cols-[150px_1fr] sm:items-start"
          >
            <div className="flex items-center justify-between gap-2 sm:block">
              <p className="type-body-strong text-text-primary">{DAY_LABELS[day.day]}</p>
              <Switch
                size="sm"
                checked={open}
                disabled={disabled}
                aria-label={`${DAY_LABELS[day.day]} — open for orders`}
                label={open ? "Open" : "Closed"}
                onCheckedChange={(next) =>
                  patchDay(day.day, next ? [{ open: "08:00", close: "22:00" }] : [])
                }
              />
            </div>

            {open ? (
              <div className="space-y-2">
                {day.intervals.map((interval, index) => (
                  <div key={index} className="flex flex-wrap items-end gap-2">
                    <Input
                      label={index === 0 ? "Opens" : undefined}
                      aria-label={`${DAY_LABELS[day.day]} window ${index + 1} opens`}
                      type="time"
                      inputSize="sm"
                      disabled={disabled}
                      value={interval.open}
                      containerClassName="w-36"
                      onChange={(e) =>
                        patchDay(
                          day.day,
                          day.intervals.map((entry, i) =>
                            i === index ? { ...entry, open: e.target.value } : entry,
                          ),
                        )
                      }
                    />
                    <Input
                      label={index === 0 ? "Closes" : undefined}
                      aria-label={`${DAY_LABELS[day.day]} window ${index + 1} closes`}
                      type="time"
                      inputSize="sm"
                      disabled={disabled}
                      value={interval.close}
                      containerClassName="w-36"
                      onChange={(e) =>
                        patchDay(
                          day.day,
                          day.intervals.map((entry, i) =>
                            i === index ? { ...entry, close: e.target.value } : entry,
                          ),
                        )
                      }
                    />
                    {day.intervals.length > 1 && (
                      <IconButton
                        label={`Remove ${DAY_LABELS[day.day]} window ${index + 1}`}
                        tone="tertiary"
                        disabled={disabled}
                        icon={<X className="h-4 w-4" />}
                        onClick={() =>
                          patchDay(
                            day.day,
                            day.intervals.filter((_, i) => i !== index),
                          )
                        }
                      />
                    )}
                  </div>
                ))}
                <div className="flex flex-wrap gap-2">
                  <Button
                    type="button"
                    variant="tertiary"
                    size="md"
                    disabled={disabled}
                    onClick={() =>
                      patchDay(day.day, [...day.intervals, { open: "18:00", close: "22:00" }])
                    }
                    leftIcon={<Plus className="h-4 w-4" />}
                  >
                    Split shift
                  </Button>
                  <Button
                    type="button"
                    variant="tertiary"
                    size="md"
                    disabled={disabled}
                    onClick={() =>
                      onChange(
                        week.map((entry) => ({
                          ...entry,
                          intervals: day.intervals.map((i) => ({ ...i })),
                        })),
                      )
                    }
                    leftIcon={<Copy className="h-4 w-4" />}
                  >
                    Copy to every day
                  </Button>
                </div>
                {day.intervals.some((i) => i.open === i.close) && (
                  <p className="type-caption text-text-secondary">
                    Same opening and closing time means open for the full 24 hours.
                  </p>
                )}
                {day.intervals.some((i) => minutesOf(i.close) < minutesOf(i.open)) && (
                  <p className="type-caption text-text-secondary">
                    Closing before opening means you trade past midnight into the next day.
                  </p>
                )}
              </div>
            ) : (
              <p className="type-caption self-center text-text-secondary">
                Customers see you as closed all {DAY_LABELS[day.day]}.
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Page                                                                       */
/* -------------------------------------------------------------------------- */

export default function SettingsPage() {
  const router = useRouter();
  const toast = useToast();
  const session = useMerchantSession();
  const restaurantId = session.restaurantId;

  const status = useApi<RestaurantStatus>(
    restaurantId ? storeStatusKey(restaurantId) : null,
    () => fetchStoreStatus(restaurantId),
    { refreshInterval: 60_000, dedupeMs: 10_000 },
  );

  /* --- Availability -------------------------------------------------- */
  const [overrideChoice, setOverrideChoice] = React.useState<"schedule" | "open" | "closed">("schedule");
  const [acceptsScheduled, setAcceptsScheduled] = React.useState(true);
  const [savingAvailability, setSavingAvailability] = React.useState(false);
  const [confirmDelist, setConfirmDelist] = React.useState(false);

  /* --- Hours --------------------------------------------------------- */
  const [week, setWeek] = React.useState<Week>(emptyWeek());
  const [timezone, setTimezone] = React.useState("Africa/Harare");
  const [savingHours, setSavingHours] = React.useState(false);

  /* --- Profile ------------------------------------------------------- */
  const [name, setName] = React.useState("");
  const [description, setDescription] = React.useState("");
  const [imageUrl, setImageUrl] = React.useState("");
  const [bannerUrl, setBannerUrl] = React.useState("");
  const [cuisines, setCuisines] = React.useState<string[]>([]);
  const [cuisineDraft, setCuisineDraft] = React.useState("");
  const [cuisineGap, setCuisineGap] = React.useState(false);
  const [savingProfile, setSavingProfile] = React.useState(false);

  /* --- Location ------------------------------------------------------ */
  const [address, setAddress] = React.useState("");
  const [pin, setPin] = React.useState<Coords | null>(null);
  const [addressQuery, setAddressQuery] = React.useState("");
  const [addressHits, setAddressHits] = React.useState<GeocodeHit[]>([]);
  const [searchingAddress, setSearchingAddress] = React.useState(false);
  const [savingLocation, setSavingLocation] = React.useState(false);

  /* --- Delivery ------------------------------------------------------ */
  const [prepMin, setPrepMin] = React.useState("30");
  const [prepMax, setPrepMax] = React.useState("45");
  const [deliveryFee, setDeliveryFee] = React.useState("2");
  const [freeThreshold, setFreeThreshold] = React.useState("");
  const [savingDelivery, setSavingDelivery] = React.useState(false);

  /* --- Contact ------------------------------------------------------- */
  const [fullName, setFullName] = React.useState("");
  const [email, setEmail] = React.useState("");
  const [savingContact, setSavingContact] = React.useState(false);

  /* --- Hydration ----------------------------------------------------- */
  const restaurant = session.restaurant;
  const user = session.user;

  const resetAvailability = React.useCallback(() => {
    const data = status.data;
    setOverrideChoice(
      data?.is_open_override === true ? "open" : data?.is_open_override === false ? "closed" : "schedule",
    );
    setAcceptsScheduled(data?.accepts_scheduled_orders ?? true);
  }, [status.data]);

  const resetHours = React.useCallback(() => {
    setWeek(weekFromStatus(status.data?.hours));
    setTimezone(status.data?.timezone || "Africa/Harare");
  }, [status.data]);

  const resetProfile = React.useCallback(() => {
    setName(restaurant?.name ?? "");
    setDescription(restaurant?.description ?? "");
    setImageUrl(restaurant?.image_url ?? "");
    setBannerUrl(restaurant?.banner_url ?? "");
    setCuisines(restaurant?.categories ?? []);
    setCuisineDraft("");
  }, [restaurant]);

  const resetLocation = React.useCallback(() => {
    setAddress(restaurant?.address ?? "");
    const coords = restaurant?.location?.coordinates;
    setPin(coords && coords.length === 2 ? { lng: coords[0], lat: coords[1] } : null);
    setAddressQuery("");
    setAddressHits([]);
  }, [restaurant]);

  const resetDelivery = React.useCallback(() => {
    setPrepMin(String(restaurant?.delivery_time_min ?? 30));
    setPrepMax(String(restaurant?.delivery_time_max ?? 45));
    setDeliveryFee(String(restaurant?.delivery_fee_usd ?? 2));
    setFreeThreshold(restaurant?.free_delivery_threshold != null ? String(restaurant.free_delivery_threshold) : "");
  }, [restaurant]);

  const resetContact = React.useCallback(() => {
    setFullName(user?.full_name ?? "");
    setEmail(user?.email ?? "");
  }, [user]);

  React.useEffect(resetAvailability, [resetAvailability]);
  React.useEffect(resetHours, [resetHours]);
  React.useEffect(resetProfile, [resetProfile]);
  React.useEffect(resetLocation, [resetLocation]);
  React.useEffect(resetDelivery, [resetDelivery]);
  React.useEffect(resetContact, [resetContact]);

  /* --- Address search ------------------------------------------------ */
  React.useEffect(() => {
    const query = addressQuery.trim();
    if (query.length < 4) {
      setAddressHits([]);
      return;
    }
    // Nominatim asks for at most one request a second; 700 ms of quiet plus a
    // 4-character floor keeps a dashboard well inside that.
    const timer = window.setTimeout(async () => {
      setSearchingAddress(true);
      try {
        const hits = await api.get<GeocodeHit[]>(
          `/location/geocode?q=${encodeURIComponent(query)}&country=zw`,
        );
        setAddressHits(Array.isArray(hits) ? hits.slice(0, 5) : []);
      } catch {
        setAddressHits([]);
      } finally {
        setSearchingAddress(false);
      }
    }, 700);
    return () => window.clearTimeout(timer);
  }, [addressQuery]);

  /* --- Dirty tracking ------------------------------------------------ */
  const availabilityDirty =
    status.data !== undefined &&
    (overrideChoice !==
      (status.data.is_open_override === true
        ? "open"
        : status.data.is_open_override === false
          ? "closed"
          : "schedule") ||
      acceptsScheduled !== status.data.accepts_scheduled_orders);

  const hoursDirty =
    status.data !== undefined &&
    (JSON.stringify(week) !== JSON.stringify(weekFromStatus(status.data.hours)) ||
      timezone !== (status.data.timezone || "Africa/Harare"));

  const profileDirty =
    restaurant !== undefined &&
    (name !== (restaurant.name ?? "") ||
      description !== (restaurant.description ?? "") ||
      imageUrl !== (restaurant.image_url ?? "") ||
      bannerUrl !== (restaurant.banner_url ?? "") ||
      JSON.stringify(cuisines) !== JSON.stringify(restaurant.categories ?? []));

  const savedPin = restaurant?.location?.coordinates;
  const locationDirty =
    restaurant !== undefined &&
    (address !== (restaurant.address ?? "") ||
      (pin
        ? !savedPin ||
          Math.abs(savedPin[1]! - pin.lat) > 1e-7 ||
          Math.abs(savedPin[0]! - pin.lng) > 1e-7
        : false));

  const deliveryDirty =
    restaurant !== undefined &&
    (prepMin !== String(restaurant.delivery_time_min ?? 30) ||
      prepMax !== String(restaurant.delivery_time_max ?? 45) ||
      deliveryFee !== String(restaurant.delivery_fee_usd ?? 2) ||
      freeThreshold !==
        (restaurant.free_delivery_threshold != null ? String(restaurant.free_delivery_threshold) : ""));

  const contactDirty =
    user !== undefined && (fullName !== (user.full_name ?? "") || email !== (user.email ?? ""));

  const anyDirty =
    availabilityDirty || hoursDirty || profileDirty || locationDirty || deliveryDirty || contactDirty;
  const guardDialog = useUnsavedGuard(anyDirty);

  /* --- Saves --------------------------------------------------------- */
  function applyRestaurant(updated: Restaurant) {
    session.patchRestaurant(updated);
  }

  async function saveAvailability() {
    if (!restaurantId) return;
    setSavingAvailability(true);
    try {
      const next = await patchStoreStatus(restaurantId, {
        is_open_override: overrideChoice === "schedule" ? null : overrideChoice === "open",
        accepts_scheduled_orders: acceptsScheduled,
        resume: true,
      });
      status.mutate(next);
      toast.success("Availability saved", { description: next.availability.reason });
    } catch (error) {
      toast.error("Availability did not save", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSavingAvailability(false);
    }
  }

  async function pause(minutes: number) {
    if (!restaurantId) return;
    setSavingAvailability(true);
    try {
      const next = await patchStoreStatus(restaurantId, { pause_minutes: minutes });
      status.mutate(next);
      toast.success(`Paused for ${minutes} minutes`, {
        description: "Zvingo re-opens you automatically when the timer runs out.",
      });
    } catch (error) {
      toast.error("Could not pause the store", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSavingAvailability(false);
    }
  }

  async function resume() {
    if (!restaurantId) return;
    setSavingAvailability(true);
    try {
      const next = await patchStoreStatus(restaurantId, { resume: true });
      status.mutate(next);
      toast.success("Pause cancelled");
    } catch (error) {
      toast.error("Could not resume", { description: error instanceof Error ? error.message : undefined });
    } finally {
      setSavingAvailability(false);
    }
  }

  async function setListed(listed: boolean) {
    if (!restaurantId) return;
    setConfirmDelist(false);
    setSavingAvailability(true);
    try {
      const next = await patchStoreStatus(restaurantId, { is_active: listed });
      status.mutate(next);
      session.patchRestaurant({ is_active: listed });
      toast.success(listed ? "Your restaurant is listed again" : "Your restaurant is delisted");
    } catch (error) {
      toast.error("Could not change your listing", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSavingAvailability(false);
    }
  }

  const hourProblems = weekProblems(week);

  async function saveHours() {
    if (!restaurantId) return;
    if (hourProblems.length) {
      toast.error("Fix the opening hours first", { description: hourProblems[0] });
      return;
    }
    setSavingHours(true);
    try {
      const next = await patchStoreStatus(restaurantId, { hours: week, timezone });
      status.mutate(next);
      session.patchRestaurant({ operating_hours: next.operating_hours });
      toast.success("Opening hours saved", {
        description: next.operating_hours
          ? `Customers now see: ${next.operating_hours}.`
          : "Your restaurant is marked closed every day.",
      });
    } catch (error) {
      toast.error("Opening hours did not save", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSavingHours(false);
    }
  }

  async function saveProfile() {
    if (!restaurantId) return;
    if (!name.trim()) {
      toast.error("Your restaurant needs a name");
      return;
    }
    setSavingProfile(true);
    try {
      const updated = await endpoints.catalog.updateRestaurant(restaurantId, {
        name: name.trim(),
        description: description.trim(),
        image_url: imageUrl,
        banner_url: bannerUrl,
        categories: cuisines,
      });
      applyRestaurant(updated);
      // `RestaurantUpdate` has no `categories` field, so the server quietly
      // ignores it. Say so rather than showing a tick over a discarded edit.
      const kept = JSON.stringify(updated.categories ?? []) === JSON.stringify(cuisines);
      setCuisineGap(!kept);
      if (kept) {
        toast.success("Profile saved");
      } else {
        setCuisines(updated.categories ?? []);
        toast.warning("Saved, except your cuisine tags", {
          description: "Zvingo cannot change cuisine tags after a restaurant is created yet. Everything else saved.",
        });
      }
    } catch (error) {
      toast.error("Profile did not save", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSavingProfile(false);
    }
  }

  async function saveLocation() {
    if (!restaurantId) return;
    if (!pin) {
      toast.error("Set the pickup pin first", {
        description: "Drivers need a point to collect from. Use your current location or drag the pin.",
      });
      return;
    }
    setSavingLocation(true);
    try {
      const updated = await endpoints.catalog.updateRestaurant(restaurantId, {
        address: address.trim(),
        ...({ lat: pin.lat, lng: pin.lng } as Partial<Restaurant>),
      });
      applyRestaurant(updated);
      toast.success("Pickup point saved", { description: "Drivers will be sent to this pin." });
    } catch (error) {
      toast.error("Pickup point did not save", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSavingLocation(false);
    }
  }

  async function saveDelivery() {
    if (!restaurantId) return;
    const min = Number(prepMin);
    const max = Number(prepMax);
    if (!Number.isFinite(min) || !Number.isFinite(max) || min < 1 || max < min) {
      toast.error("Check your prep times", {
        description: "The fastest time must be at least 1 minute and no more than the slowest.",
      });
      return;
    }
    setSavingDelivery(true);
    try {
      const updated = await endpoints.catalog.updateRestaurant(restaurantId, {
        delivery_time_min: Math.round(min),
        delivery_time_max: Math.round(max),
        delivery_fee_usd: Number(deliveryFee) || 0,
        ...(freeThreshold === "" ? {} : { free_delivery_threshold: Number(freeThreshold) }),
      });
      applyRestaurant(updated);
      toast.success("Delivery settings saved");
    } catch (error) {
      toast.error("Delivery settings did not save", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSavingDelivery(false);
    }
  }

  async function saveContact() {
    if (!fullName.trim()) {
      toast.error("Your name cannot be empty");
      return;
    }
    setSavingContact(true);
    try {
      const updated = await endpoints.auth.updateMe({
        full_name: fullName.trim(),
        ...(email.trim() ? { email: email.trim() } : {}),
      });
      // Keep the session cache in step so the shell shows the new name.
      session.refresh().catch(() => undefined);
      setFullName(updated.full_name);
      setEmail(updated.email ?? "");
      toast.success("Contact details saved");
    } catch (error) {
      toast.error("Contact details did not save", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSavingContact(false);
    }
  }

  function signOut() {
    clearAuth();
    clearApiCache();
    router.push("/login");
  }

  /* --- Render -------------------------------------------------------- */

  if (session.isLoading) {
    return (
      <PageContainer>
        <div className="space-y-4">
          <Skeleton className="h-9 w-56" />
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-56 w-full rounded-lg" />
          ))}
        </div>
      </PageContainer>
    );
  }

  if (session.error && !restaurant) {
    return (
      <PageContainer>
        <ErrorState
          error={session.error}
          title="We could not load your settings"
          onRetry={() => void session.refresh()}
        />
      </PageContainer>
    );
  }

  if (!restaurantId) {
    return (
      <PageContainer>
        <Card className="space-y-3">
          <h1 className="type-h1 text-text-primary">Settings</h1>
          <p className="type-body text-text-secondary">
            You do not have a restaurant on Zvingo yet. Create your storefront from the Menu page first — then
            every setting on this page becomes available.
          </p>
          <Button onClick={() => router.push("/dashboard/menu")}>Set up my restaurant</Button>
        </Card>
      </PageContainer>
    );
  }

  const availability: Availability | undefined = status.data?.availability;
  const pauseUntil = status.data?.pause_until ?? null;

  return (
    <PageContainer>
      <PageSection
        title="Settings"
        description="Everything customers and drivers see about your restaurant. Each section saves on its own."
      >
        <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_320px] xl:items-start">
          <div className="space-y-4">
            {/* ---------------- Availability ---------------- */}
            <SettingsSection
              title="Are you open?"
              description="This decides whether customers can order right now. It beats your opening hours."
              icon={Store}
              dirty={availabilityDirty}
              saving={savingAvailability}
              onSave={() => void saveAvailability()}
              onReset={resetAvailability}
              footerNote={
                availability
                  ? `Right now: ${availability.reason}. Local time ${availability.local_time} (${availability.timezone}).`
                  : undefined
              }
            >
              {status.error && !status.data ? (
                <ErrorState
                  size="sm"
                  error={status.error}
                  title="Store status unavailable"
                  onRetry={() => void status.refresh()}
                />
              ) : !status.data ? (
                <Skeleton className="h-32 w-full rounded-md" />
              ) : (
                <>
                  <div className="flex flex-wrap items-center gap-3 rounded-md bg-neutral-50 p-3">
                    <StatusPill
                      tone={
                        statusTone(availability?.status ?? "closed") === "open"
                          ? "success"
                          : statusTone(availability?.status ?? "closed") === "paused"
                            ? "warning"
                            : statusTone(availability?.status ?? "closed") === "unlisted"
                              ? "error"
                              : "neutral"
                      }
                      label={availability?.reason ?? "Unknown"}
                    />
                    {availability?.closes_at && (
                      <span className="type-caption tabular-figures text-text-secondary">
                        Closes at {localClock(availability.closes_at)}
                      </span>
                    )}
                    {availability?.opens_at && !availability.is_open && (
                      <span className="type-caption tabular-figures text-text-secondary">
                        Next open {localDayLabel(availability.opens_at)} {localClock(availability.opens_at)}
                      </span>
                    )}
                  </div>

                  <RadioGroup
                    label="Ordering switch"
                    variant="card"
                    value={overrideChoice}
                    onValueChange={(value) => setOverrideChoice(value)}
                    options={[
                      {
                        value: "schedule",
                        label: "Follow my opening hours",
                        description:
                          status.data.operating_hours ||
                          "No weekly hours set yet — set them below so this works by itself.",
                      },
                      {
                        value: "open",
                        label: "Open now, whatever the schedule says",
                        description: "Stays open until you change it back. Use it for a late night.",
                      },
                      {
                        value: "closed",
                        label: "Closed until I say otherwise",
                        description: "Customers cannot order, even inside your opening hours.",
                      },
                    ]}
                  />

                  {pauseUntil ? (
                    <div className="flex flex-wrap items-center justify-between gap-3 rounded-md bg-warning-surface p-3">
                      <p className="type-body text-warning">
                        Paused until {localClock(availability?.opens_at)} — orders resume automatically.
                      </p>
                      <Button variant="secondary" size="md" onClick={() => void resume()} loading={savingAvailability}>
                        Resume now
                      </Button>
                    </div>
                  ) : (
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="type-caption text-text-secondary">Slammed right now? Pause for</span>
                      {[15, 30, 60].map((minutes) => (
                        <Button
                          key={minutes}
                          variant="secondary"
                          size="md"
                          disabled={savingAvailability}
                          onClick={() => void pause(minutes)}
                        >
                          {minutes} min
                        </Button>
                      ))}
                    </div>
                  )}

                  <Switch
                    checked={acceptsScheduled}
                    onCheckedChange={setAcceptsScheduled}
                    label="Take pre-orders while closed"
                    description="Customers can schedule an order for later even when you are shut."
                  />

                  <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-border p-3">
                    <div className="min-w-0">
                      <p className="type-body-strong text-text-primary">
                        {status.data.is_active ? "Listed on Zvingo" : "Not listed on Zvingo"}
                      </p>
                      <p className="type-caption text-text-secondary">
                        {status.data.is_active
                          ? "Your restaurant appears in search and browse."
                          : "Nobody can find you, whatever your hours say."}
                      </p>
                    </div>
                    <Button
                      variant={status.data.is_active ? "secondary" : "primary"}
                      size="md"
                      onClick={() => (status.data?.is_active ? setConfirmDelist(true) : void setListed(true))}
                      loading={savingAvailability}
                    >
                      {status.data.is_active ? "Remove my listing" : "List my restaurant"}
                    </Button>
                  </div>
                </>
              )}
            </SettingsSection>

            {/* ---------------- Opening hours ---------------- */}
            <SettingsSection
              title="Opening hours"
              description="The whole week, in your own time. Zvingo opens and closes you automatically."
              icon={Clock}
              dirty={hoursDirty}
              saving={savingHours}
              onSave={() => void saveHours()}
              onReset={resetHours}
              saveLabel="Save hours"
              footerNote={
                hourProblems.length ? (
                  <span className="text-error">{hourProblems[0]}</span>
                ) : status.data?.operating_hours ? (
                  `Customers currently see: ${status.data.operating_hours}`
                ) : undefined
              }
            >
              {!status.data ? (
                <Skeleton className="h-64 w-full rounded-md" />
              ) : (
                <>
                  <Select
                    label="Time zone"
                    value={timezone}
                    onChange={(e) => setTimezone(e.target.value)}
                    options={TIMEZONES}
                    help="Every time below is wall-clock time in this zone."
                  />
                  <HoursEditor week={week} onChange={setWeek} disabled={savingHours} />
                  <div className="rounded-md bg-neutral-50 p-3">
                    <p className="type-overline text-text-secondary">Preview</p>
                    <ul className="mt-1.5 grid gap-0.5 type-caption sm:grid-cols-2">
                      {week.map((day) => (
                        <li key={day.day} className="flex justify-between gap-3 tabular-figures">
                          <span className="text-text-secondary">{DAY_SHORT[day.day]}</span>
                          <span className={day.intervals.length ? "text-text-primary" : "text-text-tertiary"}>
                            {describeDay(day)}
                          </span>
                        </li>
                      ))}
                    </ul>
                  </div>
                  {hourProblems.map((problem) => (
                    <p key={problem} role="alert" className="type-caption text-error">
                      {problem}
                    </p>
                  ))}
                </>
              )}
            </SettingsSection>

            {/* ---------------- Profile ---------------- */}
            <SettingsSection
              title="Restaurant profile"
              description="Your name, story and photography as customers see them."
              icon={Building2}
              dirty={profileDirty}
              saving={savingProfile}
              onSave={() => void saveProfile()}
              onReset={resetProfile}
            >
              <Input
                label="Restaurant name"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
                maxLength={80}
              />
              <Textarea
                label="Description"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                maxLength={280}
                showCount
                help="One or two sentences on what makes your food worth ordering."
              />
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <p className="type-caption mb-2 font-semibold text-text-primary">Logo</p>
                  <ImageUpload value={imageUrl} onChange={setImageUrl} placeholder="Upload logo" help="Square photos look best. Shown next to your name." />
                </div>
                <div>
                  <p className="type-caption mb-2 font-semibold text-text-primary">Storefront banner</p>
                  <ImageUpload
                    value={bannerUrl}
                    onChange={setBannerUrl}
                    placeholder="Upload banner"
                    help="A wide photo of your food, shown at the top of your page."
                  />
                </div>
              </div>

              <div>
                <p className="type-caption font-semibold text-text-primary">Cuisine tags</p>
                <p className="type-caption mt-0.5 text-text-secondary">
                  How customers filter for you: Pizza, Sadza, Grill, Vegetarian.
                </p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {cuisines.map((tag) => (
                    <span
                      key={tag}
                      className="inline-flex items-center gap-1 rounded-sm bg-neutral-100 py-1 pl-2.5 pr-1 type-caption font-semibold text-neutral-800"
                    >
                      {tag}
                      <button
                        type="button"
                        onClick={() => setCuisines(cuisines.filter((entry) => entry !== tag))}
                        className="zv-touch flex h-6 w-6 items-center justify-center rounded-full hover:bg-neutral-200 focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-action"
                        aria-label={`Remove ${tag}`}
                      >
                        <X className="h-3.5 w-3.5" aria-hidden="true" />
                      </button>
                    </span>
                  ))}
                  {!cuisines.length && <span className="type-caption text-text-tertiary">No tags yet.</span>}
                </div>
                <div className="mt-2 flex flex-wrap items-end gap-2">
                  <Input
                    aria-label="New cuisine tag"
                    inputSize="sm"
                    value={cuisineDraft}
                    placeholder="Add a tag"
                    containerClassName="w-48"
                    onChange={(e) => setCuisineDraft(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key !== "Enter") return;
                      e.preventDefault();
                      const tag = cuisineDraft.trim();
                      if (tag && !cuisines.includes(tag)) setCuisines([...cuisines, tag]);
                      setCuisineDraft("");
                    }}
                  />
                  <Button
                    type="button"
                    variant="secondary"
                    size="md"
                    onClick={() => {
                      const tag = cuisineDraft.trim();
                      if (tag && !cuisines.includes(tag)) setCuisines([...cuisines, tag]);
                      setCuisineDraft("");
                    }}
                  >
                    Add tag
                  </Button>
                </div>
                {cuisineGap && (
                  <p role="status" className="mt-2 flex items-start gap-2 type-caption text-warning">
                    <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
                    Zvingo cannot change cuisine tags after a restaurant is created yet. They were set when your
                    restaurant was added; support can change them for you.
                  </p>
                )}
              </div>
            </SettingsSection>

            {/* ---------------- Location ---------------- */}
            <SettingsSection
              title="Pickup address"
              description="Where the driver walks in. Get this wrong and every delivery is late."
              icon={MapPin}
              dirty={locationDirty}
              saving={savingLocation}
              onSave={() => void saveLocation()}
              onReset={resetLocation}
              saveLabel="Save pickup point"
            >
              <Textarea
                label="Street address"
                value={address}
                onChange={(e) => setAddress(e.target.value)}
                rows={2}
                maxLength={200}
                help="Shown to the driver, including the shop number or landmark."
              />

              <div>
                <Input
                  label="Find it on the map"
                  leftIcon={<Search className="h-4 w-4" />}
                  value={addressQuery}
                  onChange={(e) => setAddressQuery(e.target.value)}
                  placeholder="e.g. Sam Levy's Village, Borrowdale"
                  help="Search Zimbabwe addresses, then fine-tune by dragging the pin."
                />
                {searchingAddress && <p className="type-caption mt-1.5 text-text-secondary">Searching…</p>}
                {!!addressHits.length && (
                  <ul className="mt-2 divide-y divide-divider overflow-hidden rounded-md border border-border">
                    {addressHits.map((hit) => (
                      <li key={`${hit.lat}-${hit.lng}-${hit.display_name}`}>
                        <button
                          type="button"
                          onClick={() => {
                            setPin({ lat: hit.lat, lng: hit.lng });
                            if (!address.trim()) setAddress(hit.display_name);
                            setAddressHits([]);
                            setAddressQuery("");
                          }}
                          className="flex w-full items-start gap-2 p-3 text-left type-caption hover:bg-neutral-50 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-action"
                        >
                          <MapPin className="mt-0.5 h-4 w-4 shrink-0 text-text-tertiary" aria-hidden="true" />
                          <span className="text-text-primary">{hit.display_name}</span>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              <LocationPicker value={pin} onChange={setPin} disabled={savingLocation} />

              <div className="grid gap-4 sm:grid-cols-2">
                <Input
                  label="Latitude"
                  type="number"
                  step="0.000001"
                  inputSize="sm"
                  value={pin ? pin.lat.toFixed(6) : ""}
                  onChange={(e) => {
                    const lat = Number(e.target.value);
                    if (Number.isFinite(lat)) setPin({ lat, lng: pin?.lng ?? 31.0335 });
                  }}
                />
                <Input
                  label="Longitude"
                  type="number"
                  step="0.000001"
                  inputSize="sm"
                  value={pin ? pin.lng.toFixed(6) : ""}
                  onChange={(e) => {
                    const lng = Number(e.target.value);
                    if (Number.isFinite(lng)) setPin({ lat: pin?.lat ?? -17.8252, lng });
                  }}
                />
              </div>
            </SettingsSection>

            {/* ---------------- Delivery ---------------- */}
            <SettingsSection
              title="Delivery and prep time"
              description="The estimate customers see at checkout, and what they pay for delivery."
              icon={Clock}
              dirty={deliveryDirty}
              saving={savingDelivery}
              onSave={() => void saveDelivery()}
              onReset={resetDelivery}
            >
              <div className="grid gap-4 sm:grid-cols-2">
                <Input
                  label="Fastest, in minutes"
                  type="number"
                  min="1"
                  step="1"
                  value={prepMin}
                  onChange={(e) => setPrepMin(e.target.value)}
                />
                <Input
                  label="Slowest, in minutes"
                  type="number"
                  min="1"
                  step="1"
                  value={prepMax}
                  onChange={(e) => setPrepMax(e.target.value)}
                  help={`Customers see “${prepMin || "?"}–${prepMax || "?"} min”.`}
                />
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <Input
                  label="Delivery fee"
                  type="number"
                  min="0"
                  step="0.25"
                  prefix="$"
                  value={deliveryFee}
                  onChange={(e) => setDeliveryFee(e.target.value)}
                />
                <Input
                  label="Free delivery over"
                  type="number"
                  min="0"
                  step="0.5"
                  prefix="$"
                  value={freeThreshold}
                  onChange={(e) => setFreeThreshold(e.target.value)}
                  placeholder="No free-delivery threshold"
                  help={
                    freeThreshold
                      ? `Orders over ${formatMoney(Number(freeThreshold) || 0)} ship free.`
                      : "Leave blank to always charge the fee."
                  }
                />
              </div>
              <p className="flex items-start gap-2 rounded-md bg-neutral-50 p-3 type-caption text-text-secondary">
                <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
                <span>
                  <strong className="font-semibold text-text-primary">Delivery radius is set by Zvingo,</strong>{" "}
                  not per restaurant — dispatch matches drivers by distance from your pin. There is no per-restaurant
                  radius to set yet.
                </span>
              </p>
            </SettingsSection>

            {/* ---------------- Contact ---------------- */}
            <SettingsSection
              title="Account contact"
              description="How Zvingo reaches you about orders, payouts and outages."
              icon={Phone}
              dirty={contactDirty}
              saving={savingContact}
              onSave={() => void saveContact()}
              onReset={resetContact}
            >
              <Input
                label="Your name"
                required
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                maxLength={120}
              />
              <Input
                label="Email"
                type="email"
                leftIcon={<Mail className="h-4 w-4" />}
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@restaurant.co.zw"
                help="Used for receipts and account notices."
              />
              <Input
                label="Phone"
                value={formatPhone(user?.phone)}
                readOnly
                disabled
                leftIcon={<Phone className="h-4 w-4" />}
                help="Your phone number is your Zvingo sign-in. Contact support to change it."
              />
            </SettingsSection>

            {/* ---------------- Payouts ---------------- */}
            <Card as="section" flush className="overflow-hidden">
              <header className="flex items-start gap-3 border-b border-divider p-4">
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-neutral-100 text-neutral-700">
                  <Banknote className="h-5 w-5" aria-hidden="true" />
                </span>
                <div className="min-w-0 flex-1">
                  <h2 className="type-h3 text-text-primary">Payout details</h2>
                  <p className="type-caption mt-0.5 text-text-secondary">
                    Where Zvingo sends the money you have earned.
                  </p>
                </div>
                <Badge tone="warning">Not available yet</Badge>
              </header>
              <div className="space-y-3 p-4">
                <p className="type-body text-text-secondary">
                  Zvingo does not store merchant payout accounts yet, so there is nothing here to fill in. Rather
                  than show you a form that throws your bank details away, we have left it out until the backend can
                  hold them.
                </p>
                <p className="type-caption text-text-secondary">
                  Until then, payouts are arranged by the Zvingo finance team from the order ledger. Your settled
                  totals are on the Dashboard.
                </p>
              </div>
            </Card>

            {/* ---------------- Sign out ---------------- */}
            <Card className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="type-body-strong text-text-primary">Signed in as {user?.full_name || "merchant"}</p>
                <p className="type-caption text-text-secondary">
                  {formatPhone(user?.phone)} · {user?.role || "merchant"}
                </p>
              </div>
              <Button variant="destructive" size="md" onClick={signOut} leftIcon={<LogOut className="h-4 w-4" />}>
                Sign out
              </Button>
            </Card>
          </div>

          {/* ---------------- Live preview rail ---------------- */}
          <aside className="space-y-4 xl:sticky xl:top-6">
            <Card flush className="overflow-hidden">
              <div className="relative h-32 bg-neutral-900">
                {bannerUrl ? (
                  <div
                    className="absolute inset-0 bg-cover bg-center"
                    style={{ backgroundImage: `url("${bannerUrl}")` }}
                    aria-hidden="true"
                  />
                ) : (
                  <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,var(--color-brand-lime),transparent_55%)]" />
                )}
                <div className="absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-neutral-900/70 to-transparent" />
                <div className="absolute bottom-3 left-3 flex items-end gap-3">
                  {imageUrl ? (
                    <div
                      className="h-12 w-12 rounded-md border-2 border-neutral-0 bg-cover bg-center"
                      style={{ backgroundImage: `url("${imageUrl}")` }}
                      aria-hidden="true"
                    />
                  ) : (
                    <span className="flex h-12 w-12 items-center justify-center rounded-md border-2 border-neutral-0 bg-neutral-0 text-neutral-900">
                      <Store className="h-5 w-5" aria-hidden="true" />
                    </span>
                  )}
                  <div className="pb-0.5 text-neutral-0">
                    <p className="type-h3">{name || "Your restaurant"}</p>
                    <p className="type-caption opacity-80">
                      {prepMin}–{prepMax} min · {formatMoney(Number(deliveryFee) || 0)} delivery
                    </p>
                  </div>
                </div>
              </div>
              <div className="space-y-3 p-4">
                <StoreStatusPill />
                <p className="type-caption line-clamp-3 text-text-secondary">
                  {description || "Add a description so customers know what you are famous for."}
                </p>
                {!!cuisines.length && (
                  <div className="flex flex-wrap gap-1.5">
                    {cuisines.slice(0, 5).map((tag) => (
                      <Badge key={tag} tone="neutral">
                        {tag}
                      </Badge>
                    ))}
                  </div>
                )}
                <p className="flex items-start gap-2 type-caption text-text-secondary">
                  <MapPin className="mt-0.5 h-4 w-4 shrink-0 text-text-tertiary" aria-hidden="true" />
                  {address || "No pickup address set yet."}
                </p>
              </div>
            </Card>

            <Card className="space-y-2">
              <p className="type-overline text-text-secondary">Account</p>
              <div className="flex items-center gap-2 type-caption text-text-secondary">
                <ShieldCheck className="h-4 w-4 text-success" aria-hidden="true" />
                Merchant account {user?.is_active === false ? "suspended" : "active"}
              </div>
              <div className="flex items-center gap-2 type-caption text-text-secondary">
                <Trash2 className="h-4 w-4 text-text-tertiary" aria-hidden="true" />
                Closing your Zvingo account is handled by support — email them from the address above.
              </div>
            </Card>
          </aside>
        </div>
      </PageSection>

      <ConfirmDialog
        open={confirmDelist}
        tone="destructive"
        title="Remove your restaurant from Zvingo?"
        consequence="Customers will not find you in search or browse at all, and no new orders can arrive — this is stronger than closing for the day. Your menu, offers and history are kept, and you can list again at any time."
        confirmLabel="Remove my listing"
        cancelLabel="Stay listed"
        onCancel={() => setConfirmDelist(false)}
        onConfirm={() => void setListed(false)}
      />

      {guardDialog}
    </PageContainer>
  );
}
