"use client";

import * as React from "react";
import {
  BadgePercent,
  CalendarClock,
  CheckCircle2,
  Copy,
  Gift,
  Megaphone,
  Pencil,
  Plus,
  Tag,
  Ticket,
  Trash2,
  Truck,
  Users,
} from "lucide-react";
import { PageContainer, PageSection } from "@/components/AppShell";
import {
  Badge,
  Button,
  Card,
  Checkbox,
  ConfirmDialog,
  EmptyState,
  ErrorState,
  IconButton,
  Input,
  Select,
  Sheet,
  Skeleton,
  StatCard,
  StatusPill,
  Switch,
  Tabs,
  Textarea,
  type Tone,
  useToast,
} from "@/components/ui";
import { api, docId, type Promotion } from "@/lib/api";
import { useApi, useMerchantSession } from "@/lib/useApi";
import { formatDate, formatDateTime, formatMoney, pluralise, toDateTimeLocalValue } from "@/lib/format";

/* -------------------------------------------------------------------------- */
/* Contract — backend/app/catalog/router.py + promotion_service.py            */
/* -------------------------------------------------------------------------- */

/** `first_order_only` is on the backend model but not yet in the shared type. */
type MerchantPromotion = Promotion & { first_order_only?: boolean };

/** The four types `SUPPORTED_PROMO_TYPES` actually accepts. */
type PromoType = "percentage" | "flat" | "free_delivery" | "free_item";

const PROMO_TYPES: Array<{ value: PromoType; label: string; blurb: string }> = [
  { value: "percentage", label: "Percentage off", blurb: "Take a share off the food subtotal, e.g. 20% off." },
  { value: "flat", label: "Fixed amount off", blurb: "Take a set amount off, e.g. $5 off." },
  { value: "free_delivery", label: "Free delivery", blurb: "Waive the delivery fee. The food price is unchanged." },
  { value: "free_item", label: "Free item", blurb: "Give one dish from your menu away with the order." },
];

const ICON_OPTIONS = [
  { value: "local_offer", label: "Tag" },
  { value: "percent", label: "Percent" },
  { value: "delivery_dining", label: "Delivery" },
  { value: "card_giftcard", label: "Gift" },
];

function promoIcon(type: string) {
  if (type === "free_delivery") return Truck;
  if (type === "free_item") return Gift;
  if (type === "percentage") return BadgePercent;
  return Tag;
}

/* -------------------------------------------------------------------------- */
/* Lifecycle, mirrored from compute_discount's rejection order                */
/* -------------------------------------------------------------------------- */

type Lifecycle = "live" | "scheduled" | "paused" | "expired" | "exhausted";

const LIFECYCLE: Record<Lifecycle, { label: string; tone: Tone; hint: string }> = {
  live: { label: "Live", tone: "success", hint: "Customers can use this right now." },
  scheduled: { label: "Scheduled", tone: "info", hint: "Starts automatically — nothing else to do." },
  paused: { label: "Paused", tone: "neutral", hint: "Hidden from customers until you turn it back on." },
  expired: { label: "Expired", tone: "warning", hint: "The end date has passed." },
  exhausted: { label: "Fully redeemed", tone: "warning", hint: "The total redemption limit has been reached." },
};

function lifecycleOf(promo: MerchantPromotion, now: number): Lifecycle {
  const ends = promo.ends_at ? Date.parse(`${promo.ends_at.replace(/Z?$/, "")}Z`) : null;
  const starts = promo.starts_at ? Date.parse(`${promo.starts_at.replace(/Z?$/, "")}Z`) : null;
  if (ends !== null && Number.isFinite(ends) && ends < now) return "expired";
  if (promo.max_uses != null && promo.current_uses >= promo.max_uses) return "exhausted";
  if (!promo.is_active) return "paused";
  if (starts !== null && Number.isFinite(starts) && starts > now) return "scheduled";
  return "live";
}

/* -------------------------------------------------------------------------- */
/* Discount preview — a faithful copy of promotion_service.compute_discount    */
/* -------------------------------------------------------------------------- */

interface PreviewInput {
  promoType: PromoType;
  discountValue: number;
  minOrderUsd: number;
  maxDiscountUsd: number | null;
  freeItemPrice: number | null;
  subtotal: number;
  deliveryFee: number;
}

interface PreviewResult {
  eligible: boolean;
  reason?: string;
  /** Money off the food subtotal. */
  discount: number;
  /** Delivery fee the customer no longer pays. */
  feeWaived: number;
  /** What the order costs after the promo. */
  payable: number;
}

function previewDiscount(input: PreviewInput): PreviewResult {
  const { promoType, subtotal, deliveryFee } = input;
  const gross = subtotal + deliveryFee;

  if (subtotal < input.minOrderUsd) {
    return {
      eligible: false,
      reason: `Needs a ${formatMoney(input.minOrderUsd)} food subtotal — this basket is ${formatMoney(subtotal)}.`,
      discount: 0,
      feeWaived: 0,
      payable: gross,
    };
  }

  let discount = 0;
  let feeWaived = 0;

  if (promoType === "percentage") {
    const percent = Math.max(0, Math.min(input.discountValue, 100));
    discount = Math.round(subtotal * (percent / 100) * 100) / 100;
  } else if (promoType === "flat") {
    discount = Math.round(Math.max(0, input.discountValue) * 100) / 100;
  } else if (promoType === "free_delivery") {
    feeWaived = deliveryFee;
  } else if (promoType === "free_item") {
    if (input.freeItemPrice == null) {
      return {
        eligible: false,
        reason: "Choose which dish is free before this offer can be published.",
        discount: 0,
        feeWaived: 0,
        payable: gross,
      };
    }
    discount = Math.round(input.freeItemPrice * 100) / 100;
  }

  if (input.maxDiscountUsd != null) discount = Math.min(discount, input.maxDiscountUsd);
  discount = Math.min(discount, Math.round(subtotal * 100) / 100);
  discount = Math.max(0, Math.round(discount * 100) / 100);

  return { eligible: true, discount, feeWaived, payable: Math.max(0, gross - discount - feeWaived) };
}

/* -------------------------------------------------------------------------- */
/* Form                                                                       */
/* -------------------------------------------------------------------------- */

interface PromoForm {
  title: string;
  subtitle: string;
  description: string;
  icon: string;
  promo_type: PromoType;
  discount_value: string;
  min_order_usd: string;
  max_discount_usd: string;
  free_item_id: string;
  starts_at: string;
  ends_at: string;
  max_uses: string;
  max_uses_per_user: string;
  code: string;
  first_order_only: boolean;
  scope_to_restaurant: boolean;
}

const BLANK_FORM: PromoForm = {
  title: "",
  subtitle: "",
  description: "",
  icon: "local_offer",
  promo_type: "percentage",
  discount_value: "20",
  min_order_usd: "0",
  max_discount_usd: "",
  free_item_id: "",
  starts_at: "",
  ends_at: "",
  max_uses: "",
  max_uses_per_user: "1",
  code: "",
  first_order_only: false,
  scope_to_restaurant: true,
};

type FormErrors = Partial<Record<keyof PromoForm, string>>;

function validate(form: PromoForm): FormErrors {
  const errors: FormErrors = {};
  if (!form.title.trim()) errors.title = "Customers see this first — give the offer a name.";
  if (!form.subtitle.trim()) errors.subtitle = "One short line explaining the catch, e.g. “On orders over $15”.";

  const value = Number(form.discount_value);
  if (form.promo_type === "percentage") {
    if (!Number.isFinite(value) || value <= 0) errors.discount_value = "Enter how much to take off, e.g. 20.";
    else if (value > 100) errors.discount_value = "A discount cannot be more than 100%.";
  }
  if (form.promo_type === "flat" && (!Number.isFinite(value) || value <= 0)) {
    errors.discount_value = "Enter the amount to take off, e.g. 5.";
  }
  if (form.promo_type === "free_item" && !form.free_item_id) {
    errors.free_item_id = "Choose which dish customers get free.";
  }

  const minOrder = Number(form.min_order_usd);
  if (form.min_order_usd !== "" && (!Number.isFinite(minOrder) || minOrder < 0)) {
    errors.min_order_usd = "Enter 0 or more.";
  }
  if (form.max_discount_usd !== "") {
    const cap = Number(form.max_discount_usd);
    if (!Number.isFinite(cap) || cap <= 0) errors.max_discount_usd = "Leave blank for no cap, or enter an amount.";
  }
  if (form.max_uses !== "") {
    const uses = Number(form.max_uses);
    if (!Number.isInteger(uses) || uses < 1) errors.max_uses = "Leave blank for unlimited, or enter a whole number.";
  }
  const perUser = Number(form.max_uses_per_user);
  if (!Number.isInteger(perUser) || perUser < 1) errors.max_uses_per_user = "At least 1.";

  if (form.starts_at && form.ends_at && Date.parse(form.ends_at) <= Date.parse(form.starts_at)) {
    errors.ends_at = "The end has to come after the start.";
  }
  if (form.code && !/^[A-Z0-9-]{3,24}$/.test(form.code)) {
    errors.code = "Use 3–24 letters, numbers or dashes, e.g. DINNER20.";
  }
  return errors;
}

function formFromPromo(promo: MerchantPromotion): PromoForm {
  return {
    title: promo.title,
    subtitle: promo.subtitle,
    description: promo.description || "",
    icon: promo.icon || "local_offer",
    promo_type: (PROMO_TYPES.some((t) => t.value === promo.promo_type)
      ? promo.promo_type
      : "percentage") as PromoType,
    discount_value: String(promo.discount_value ?? 0),
    min_order_usd: String(promo.min_order_usd ?? 0),
    max_discount_usd: promo.max_discount_usd != null ? String(promo.max_discount_usd) : "",
    free_item_id: promo.free_item_id || "",
    starts_at: toDateTimeLocalValue(promo.starts_at),
    ends_at: toDateTimeLocalValue(promo.ends_at),
    max_uses: promo.max_uses != null ? String(promo.max_uses) : "",
    max_uses_per_user: String(promo.max_uses_per_user ?? 1),
    code: promo.code || "",
    first_order_only: Boolean(promo.first_order_only),
    scope_to_restaurant: Boolean(promo.restaurant_id),
  };
}

/* -------------------------------------------------------------------------- */
/* Page                                                                       */
/* -------------------------------------------------------------------------- */

type Filter = "all" | Lifecycle;

export default function PromotionsPage() {
  const toast = useToast();
  const { restaurant, restaurantId, isLoading: sessionLoading } = useMerchantSession();
  const promos = useApi<MerchantPromotion[]>(
    "promotions:mine",
    () => api.get<MerchantPromotion[]>("/catalog/promotions/merchant?limit=100"),
    { dedupeMs: 10_000 },
  );

  const [filter, setFilter] = React.useState<Filter>("all");
  const [editing, setEditing] = React.useState<MerchantPromotion | null>(null);
  const [creating, setCreating] = React.useState(false);
  const [deleteTarget, setDeleteTarget] = React.useState<MerchantPromotion | null>(null);
  const [pendingToggle, setPendingToggle] = React.useState<string | null>(null);

  const now = Date.now();
  const rows = React.useMemo(() => promos.data ?? [], [promos.data]);
  const withLifecycle = React.useMemo(
    () => rows.map((promo) => ({ promo, lifecycle: lifecycleOf(promo, now) })),
    [rows, now],
  );

  const counts = React.useMemo(() => {
    const base: Record<Lifecycle, number> = { live: 0, scheduled: 0, paused: 0, expired: 0, exhausted: 0 };
    withLifecycle.forEach(({ lifecycle }) => (base[lifecycle] += 1));
    return base;
  }, [withLifecycle]);

  const visible = React.useMemo(
    () => (filter === "all" ? withLifecycle : withLifecycle.filter((entry) => entry.lifecycle === filter)),
    [withLifecycle, filter],
  );

  const totalRedemptions = rows.reduce((sum, promo) => sum + (promo.current_uses || 0), 0);

  async function toggleActive(promo: MerchantPromotion) {
    const id = docId(promo);
    setPendingToggle(id);
    const optimistic = rows.map((entry) =>
      docId(entry) === id ? { ...entry, is_active: !entry.is_active } : entry,
    );
    promos.mutate(optimistic);
    try {
      const updated = await api.patch<MerchantPromotion>(`/catalog/promotions/${id}/toggle`);
      promos.mutate(rows.map((entry) => (docId(entry) === id ? updated : entry)));
      toast.success(updated.is_active ? "Offer is live" : "Offer paused", {
        description: updated.is_active
          ? "Customers can see and use it now."
          : "It stays saved — turn it back on whenever you like.",
      });
    } catch (error) {
      promos.mutate(rows);
      toast.error("That did not save", {
        description: error instanceof Error ? error.message : undefined,
        action: { label: "Try again", onClick: () => void toggleActive(promo) },
      });
    } finally {
      setPendingToggle(null);
    }
  }

  async function remove(promo: MerchantPromotion) {
    const id = docId(promo);
    setDeleteTarget(null);
    try {
      await api.delete(`/catalog/promotions/${id}`);
      promos.mutate(rows.filter((entry) => docId(entry) !== id));
      toast.success("Offer deleted", { description: `“${promo.title}” is gone from the customer app.` });
    } catch (error) {
      toast.error("Could not delete that offer", {
        description: error instanceof Error ? error.message : undefined,
      });
      void promos.refresh();
    }
  }

  const showSkeleton = promos.isLoading || sessionLoading;

  return (
    <PageContainer>
      <PageSection
        title="Promotions"
        description="Offers published straight into the Zvingo app. Edit, pause or retire one at any time."
        actions={
          <Button leftIcon={<Plus className="h-4 w-4" />} onClick={() => setCreating(true)}>
            New offer
          </Button>
        }
      >
        <div className="grid gap-3 sm:grid-cols-3">
          <StatCard
            label="Offers"
            value={rows.length}
            icon={Megaphone}
            hint={`${counts.live} live · ${counts.scheduled} scheduled`}
            loading={showSkeleton}
          />
          <StatCard
            label="Redemptions"
            value={totalRedemptions}
            icon={Ticket}
            hint="Times customers have used your offers"
            loading={showSkeleton}
          />
          <StatCard
            label="Needs attention"
            value={counts.expired + counts.exhausted}
            icon={CalendarClock}
            hint={
              counts.expired + counts.exhausted
                ? "Expired or fully redeemed — edit or delete them"
                : "Nothing expired or used up"
            }
            loading={showSkeleton}
          />
        </div>
      </PageSection>

      <PageSection>
        <Tabs
          label="Filter offers by state"
          variant="segmented"
          value={filter}
          onValueChange={(value) => setFilter(value as Filter)}
          items={[
            { value: "all", label: "All", count: rows.length },
            { value: "live", label: "Live", count: counts.live },
            { value: "scheduled", label: "Scheduled", count: counts.scheduled },
            { value: "paused", label: "Paused", count: counts.paused },
            { value: "expired", label: "Expired", count: counts.expired },
            { value: "exhausted", label: "Used up", count: counts.exhausted },
          ]}
          className="mb-4"
        />

        {promos.error && !rows.length ? (
          <ErrorState
            error={promos.error}
            title="We could not load your offers"
            onRetry={() => void promos.refresh()}
          />
        ) : showSkeleton ? (
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {[0, 1, 2].map((i) => (
              <Card key={i} className="space-y-3">
                <Skeleton className="h-28 w-full rounded-md" />
                <Skeleton shape="text" className="w-2/3" />
                <Skeleton shape="text" className="w-1/3" />
              </Card>
            ))}
          </div>
        ) : !rows.length ? (
          <EmptyState
            icon={Tag}
            title="No offers yet"
            description="A first-order discount or free delivery is the fastest way to get a new customer to try your food."
            action={
              <Button leftIcon={<Plus className="h-4 w-4" />} onClick={() => setCreating(true)}>
                Create your first offer
              </Button>
            }
          />
        ) : !visible.length ? (
          <EmptyState
            icon={Tag}
            title={`Nothing ${LIFECYCLE[filter as Lifecycle]?.label.toLowerCase() ?? "here"}`}
            description="Switch to another tab to see the rest of your offers."
            action={<Button variant="secondary" onClick={() => setFilter("all")}>Show all offers</Button>}
          />
        ) : (
          <ul className="zv-stagger grid list-none gap-3 md:grid-cols-2 xl:grid-cols-3">
            {visible.map(({ promo, lifecycle }) => (
              <PromotionCard
                key={docId(promo)}
                promo={promo}
                lifecycle={lifecycle}
                deliveryFee={restaurant?.delivery_fee_usd ?? 0}
                toggling={pendingToggle === docId(promo)}
                onToggle={() => void toggleActive(promo)}
                onEdit={() => setEditing(promo)}
                onDelete={() => setDeleteTarget(promo)}
                onCopyCode={() => {
                  void navigator.clipboard?.writeText(promo.code || "");
                  toast.success("Code copied", { description: promo.code ?? undefined });
                }}
              />
            ))}
          </ul>
        )}
      </PageSection>

      <PageSection
        title="What we can show you"
        description="Zvingo reports what it actually records. Anything it does not measure is named here rather than invented."
      >
        <Card className="space-y-3">
          <div className="flex items-start gap-3">
            <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-success" aria-hidden="true" />
            <p className="type-body text-text-secondary">
              <span className="font-semibold text-text-primary">Redemptions are real.</span> Every card shows the
              count the backend increments when an order actually uses the code, plus how much of the limit is left.
            </p>
          </div>
          <div className="flex items-start gap-3">
            <CalendarClock className="mt-0.5 h-4 w-4 shrink-0 text-text-tertiary" aria-hidden="true" />
            <p className="type-body text-text-secondary">
              <span className="font-semibold text-text-primary">Revenue influenced is not measured yet.</span> Orders
              do not record which promotion they used, so Zvingo cannot honestly attribute revenue to an offer. We are
              not going to show you a number we made up.
            </p>
          </div>
        </Card>
      </PageSection>

      <PromotionEditor
        open={creating || editing !== null}
        promo={editing}
        restaurantId={restaurantId}
        deliveryFee={restaurant?.delivery_fee_usd ?? 0}
        menu={restaurant?.menu ?? []}
        onClose={() => {
          setCreating(false);
          setEditing(null);
        }}
        onSaved={(saved, wasNew) => {
          setCreating(false);
          setEditing(null);
          const id = docId(saved);
          promos.mutate(
            wasNew ? [saved, ...rows] : rows.map((entry) => (docId(entry) === id ? saved : entry)),
          );
          toast.success(wasNew ? "Offer published" : "Offer updated", {
            description: saved.is_active
              ? "Customers will see it in the Zvingo app."
              : "It is saved but paused — turn it on when you are ready.",
          });
        }}
      />

      <ConfirmDialog
        open={deleteTarget !== null}
        tone="destructive"
        title={deleteTarget ? `Delete “${deleteTarget.title}”?` : "Delete this offer?"}
        consequence={
          deleteTarget
            ? `This offer disappears from the Zvingo app immediately and its ${pluralise(
                deleteTarget.current_uses || 0,
                "redemption",
              )} record goes with it. This cannot be undone — pause it instead if you might use it again.`
            : ""
        }
        confirmLabel="Delete offer"
        cancelLabel="Keep it"
        onCancel={() => setDeleteTarget(null)}
        onConfirm={async () => {
          if (deleteTarget) await remove(deleteTarget);
        }}
      />
    </PageContainer>
  );
}

/* -------------------------------------------------------------------------- */
/* Card                                                                       */
/* -------------------------------------------------------------------------- */

function headlineFor(promo: MerchantPromotion): string {
  switch (promo.promo_type) {
    case "percentage":
      return `${promo.discount_value}% off`;
    case "flat":
      return `${formatMoney(promo.discount_value)} off`;
    case "free_delivery":
      return "Free delivery";
    case "free_item":
      return promo.free_item_name ? `Free ${promo.free_item_name}` : "Free item";
    default:
      return promo.title;
  }
}

function PromotionCard({
  promo,
  lifecycle,
  deliveryFee,
  toggling,
  onToggle,
  onEdit,
  onDelete,
  onCopyCode,
}: {
  promo: MerchantPromotion;
  lifecycle: Lifecycle;
  deliveryFee: number;
  toggling: boolean;
  onToggle: () => void;
  onEdit: () => void;
  onDelete: () => void;
  onCopyCode: () => void;
}) {
  const Icon = promoIcon(promo.promo_type);
  const meta = LIFECYCLE[lifecycle];
  const usesLeft = promo.max_uses != null ? Math.max(0, promo.max_uses - promo.current_uses) : null;
  const usedPercent =
    promo.max_uses != null && promo.max_uses > 0
      ? Math.min(100, Math.round((promo.current_uses / promo.max_uses) * 100))
      : 0;

  return (
    <Card as="li" flush className="flex flex-col overflow-hidden">
      <div className="flex items-start justify-between gap-3 bg-deal-surface p-4">
        <div className="min-w-0">
          <span className="flex h-10 w-10 items-center justify-center rounded-md bg-neutral-0 text-deal">
            <Icon className="h-5 w-5" aria-hidden="true" />
          </span>
          <p className="type-h2 mt-3 truncate text-text-primary">{headlineFor(promo)}</p>
          <p className="type-caption mt-0.5 line-clamp-2 text-text-secondary">{promo.subtitle}</p>
        </div>
        <StatusPill tone={meta.tone} label={meta.label} />
      </div>

      <div className="flex flex-1 flex-col gap-3 p-4">
        <div>
          <h3 className="type-h3 truncate text-text-primary">{promo.title}</h3>
          <p className="type-caption mt-1 text-text-secondary">{meta.hint}</p>
        </div>

        <dl className="grid gap-1.5 type-caption">
          <div className="flex items-baseline justify-between gap-3">
            <dt className="text-text-secondary">Runs</dt>
            <dd className="tabular-figures font-semibold text-text-primary">
              {formatDate(promo.starts_at)} – {promo.ends_at ? formatDate(promo.ends_at) : "no end date"}
            </dd>
          </div>
          <div className="flex items-baseline justify-between gap-3">
            <dt className="text-text-secondary">Minimum spend</dt>
            <dd className="tabular-figures font-semibold text-text-primary">
              {promo.min_order_usd > 0 ? formatMoney(promo.min_order_usd) : "None"}
            </dd>
          </div>
          {promo.promo_type === "free_delivery" && (
            <div className="flex items-baseline justify-between gap-3">
              <dt className="text-text-secondary">Fee waived</dt>
              <dd className="tabular-figures font-semibold text-text-primary">{formatMoney(deliveryFee)}</dd>
            </div>
          )}
          <div className="flex items-baseline justify-between gap-3">
            <dt className="text-text-secondary">Redemptions</dt>
            <dd className="tabular-figures font-semibold text-text-primary">
              {promo.current_uses}
              {promo.max_uses != null ? ` of ${promo.max_uses}` : ""}
            </dd>
          </div>
        </dl>

        {promo.max_uses != null && (
          <div>
            <div
              className="h-1.5 w-full overflow-hidden rounded-full bg-neutral-200"
              role="progressbar"
              aria-valuenow={usedPercent}
              aria-valuemin={0}
              aria-valuemax={100}
              aria-label={`${promo.current_uses} of ${promo.max_uses} redemptions used`}
            >
              <span
                className={usedPercent >= 100 ? "block h-full bg-warning" : "block h-full bg-action"}
                style={{ width: `${usedPercent}%` }}
              />
            </div>
            <p className="type-caption mt-1 text-text-secondary">
              {usesLeft === 0 ? "No redemptions left" : `${pluralise(usesLeft ?? 0, "redemption")} left`}
            </p>
          </div>
        )}

        <div className="flex flex-wrap items-center gap-1.5">
          {promo.code && (
            <button
              type="button"
              onClick={onCopyCode}
              className="zv-touch inline-flex items-center gap-1.5 rounded-sm bg-neutral-100 px-2.5 py-1.5 type-caption font-bold text-neutral-800 hover:bg-neutral-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
              aria-label={`Copy promo code ${promo.code}`}
            >
              <Copy className="h-3.5 w-3.5" aria-hidden="true" />
              {promo.code}
            </button>
          )}
          {promo.first_order_only && (
            <Badge tone="info" icon={<Users className="h-3.5 w-3.5" aria-hidden="true" />}>
              First order only
            </Badge>
          )}
          {promo.max_uses_per_user > 1 && <Badge tone="neutral">{promo.max_uses_per_user} per customer</Badge>}
          {!promo.restaurant_id && <Badge tone="neutral">All my restaurants</Badge>}
        </div>

        <div className="mt-auto flex items-center justify-between gap-2 border-t border-divider pt-3">
          <Switch
            checked={promo.is_active}
            onCheckedChange={onToggle}
            busy={toggling}
            size="sm"
            label={promo.is_active ? "Visible" : "Hidden"}
          />
          <div className="flex items-center gap-1">
            <IconButton
              label={`Edit ${promo.title}`}
              tone="tertiary"
              icon={<Pencil className="h-4 w-4" />}
              onClick={onEdit}
            />
            <IconButton
              label={`Delete ${promo.title}`}
              tone="destructive"
              icon={<Trash2 className="h-4 w-4" />}
              onClick={onDelete}
            />
          </div>
        </div>
      </div>
    </Card>
  );
}

/* -------------------------------------------------------------------------- */
/* Editor                                                                     */
/* -------------------------------------------------------------------------- */

interface MenuLite {
  id: string;
  name: string;
  price_usd: number;
}

function PromotionEditor({
  open,
  promo,
  restaurantId,
  deliveryFee,
  menu,
  onClose,
  onSaved,
}: {
  open: boolean;
  promo: MerchantPromotion | null;
  restaurantId: string;
  deliveryFee: number;
  menu: MenuLite[];
  onClose: () => void;
  onSaved: (promo: MerchantPromotion, wasNew: boolean) => void;
}) {
  const toast = useToast();
  const [form, setForm] = React.useState<PromoForm>(BLANK_FORM);
  const [errors, setErrors] = React.useState<FormErrors>({});
  const [submitted, setSubmitted] = React.useState(false);
  const [saving, setSaving] = React.useState(false);
  const [basket, setBasket] = React.useState("20");

  React.useEffect(() => {
    if (!open) return;
    setForm(promo ? formFromPromo(promo) : BLANK_FORM);
    setErrors({});
    setSubmitted(false);
  }, [open, promo]);

  const set = <K extends keyof PromoForm>(key: K, value: PromoForm[K]) =>
    setForm((prev) => ({ ...prev, [key]: value }));

  React.useEffect(() => {
    if (submitted) setErrors(validate(form));
  }, [form, submitted]);

  const freeItem = menu.find((item) => item.id === form.free_item_id) ?? null;
  const subtotal = Math.max(0, Number(basket) || 0);
  const preview = previewDiscount({
    promoType: form.promo_type,
    discountValue: Number(form.discount_value) || 0,
    minOrderUsd: Number(form.min_order_usd) || 0,
    maxDiscountUsd: form.max_discount_usd === "" ? null : Number(form.max_discount_usd),
    freeItemPrice: freeItem?.price_usd ?? null,
    subtotal,
    deliveryFee,
  });

  async function submit() {
    setSubmitted(true);
    const found = validate(form);
    setErrors(found);
    if (Object.keys(found).length) {
      toast.error("Some details need fixing", { description: Object.values(found)[0] });
      return;
    }

    const body = {
      title: form.title.trim(),
      subtitle: form.subtitle.trim(),
      description: form.description.trim() || null,
      icon: form.icon,
      promo_type: form.promo_type,
      discount_value:
        form.promo_type === "percentage" || form.promo_type === "flat" ? Number(form.discount_value) || 0 : 0,
      min_order_usd: Number(form.min_order_usd) || 0,
      max_discount_usd: form.max_discount_usd === "" ? null : Number(form.max_discount_usd),
      free_item_id: form.promo_type === "free_item" ? form.free_item_id || null : null,
      free_item_name: form.promo_type === "free_item" ? freeItem?.name ?? null : null,
      starts_at: form.starts_at ? new Date(form.starts_at).toISOString() : null,
      ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null,
      max_uses: form.max_uses === "" ? null : Number(form.max_uses),
      max_uses_per_user: Number(form.max_uses_per_user) || 1,
      code: form.code.trim() || null,
      first_order_only: form.first_order_only,
      restaurant_id: form.scope_to_restaurant ? restaurantId || null : null,
    };

    setSaving(true);
    try {
      const saved = promo
        ? await api.put<MerchantPromotion>(`/catalog/promotions/${docId(promo)}`, body)
        : await api.post<MerchantPromotion>("/catalog/promotions", body);
      onSaved(saved, !promo);
    } catch (error) {
      toast.error("The offer did not save", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSaving(false);
    }
  }

  const typeMeta = PROMO_TYPES.find((t) => t.value === form.promo_type);
  const PreviewIcon = promoIcon(form.promo_type);
  const valueLabel = form.promo_type === "percentage" ? "Percentage off" : "Amount off";
  const showValue = form.promo_type === "percentage" || form.promo_type === "flat";

  return (
    <Sheet
      open={open}
      onClose={onClose}
      width="lg"
      title={promo ? `Edit “${promo.title}”` : "New offer"}
      description="Everything here is exactly what the Zvingo app will show and charge."
      footer={
        <>
          <Button variant="secondary" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={() => void submit()} loading={saving}>
            {promo ? "Save changes" : "Publish offer"}
          </Button>
        </>
      }
    >
      <div className="space-y-6">
        {/* Live customer preview — the point of the whole screen. */}
        <section aria-labelledby="promo-preview-heading">
          <h3 id="promo-preview-heading" className="type-overline text-text-secondary">
            What the customer sees
          </h3>
          <Card className="mt-2 bg-deal-surface">
            <div className="flex items-start gap-3">
              <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-md bg-neutral-0 text-deal">
                <PreviewIcon className="h-5 w-5" aria-hidden="true" />
              </span>
              <div className="min-w-0">
                <p className="type-h3 truncate text-text-primary">
                  {form.title.trim() || "Your offer title"}
                </p>
                <p className="type-caption mt-0.5 text-text-secondary">
                  {form.subtitle.trim() || "The one-line explanation goes here"}
                </p>
              </div>
            </div>
          </Card>

          <Card className="mt-3">
            <div className="flex flex-wrap items-end gap-3">
              <Input
                label="Try it on a basket of"
                type="number"
                min="0"
                step="0.5"
                inputSize="sm"
                prefix="$"
                value={basket}
                onChange={(e) => setBasket(e.target.value)}
                containerClassName="w-44"
                help={`Delivery fee ${formatMoney(deliveryFee)}`}
              />
            </div>

            {preview.eligible ? (
              <dl className="mt-3 space-y-1.5 type-body">
                <div className="flex items-baseline justify-between gap-3">
                  <dt className="text-text-secondary">Food</dt>
                  <dd className="tabular-figures">{formatMoney(subtotal)}</dd>
                </div>
                <div className="flex items-baseline justify-between gap-3">
                  <dt className="text-text-secondary">Delivery</dt>
                  <dd className="tabular-figures">
                    {preview.feeWaived > 0 ? (
                      <>
                        <span className="text-text-tertiary line-through">{formatMoney(deliveryFee)}</span>{" "}
                        <span className="font-semibold text-success">Free</span>
                      </>
                    ) : (
                      formatMoney(deliveryFee)
                    )}
                  </dd>
                </div>
                {preview.discount > 0 && (
                  <div className="flex items-baseline justify-between gap-3 text-deal">
                    <dt className="font-semibold">Offer</dt>
                    <dd className="tabular-figures font-semibold">−{formatMoney(preview.discount)}</dd>
                  </div>
                )}
                <div className="flex items-baseline justify-between gap-3 border-t border-divider pt-2">
                  <dt className="font-bold text-text-primary">They pay</dt>
                  <dd className="type-h3 tabular-figures text-text-primary">{formatMoney(preview.payable)}</dd>
                </div>
                <p className="type-caption pt-1 text-success">
                  {preview.discount + preview.feeWaived > 0
                    ? `They save ${formatMoney(preview.discount + preview.feeWaived)} on this order.`
                    : "This basket saves nothing yet — check the offer value."}
                </p>
              </dl>
            ) : (
              <p className="mt-3 type-body text-warning">{preview.reason}</p>
            )}
          </Card>
        </section>

        <section className="space-y-4" aria-labelledby="promo-basics-heading">
          <h3 id="promo-basics-heading" className="type-overline text-text-secondary">
            The offer
          </h3>
          <Input
            label="Title"
            required
            value={form.title}
            error={errors.title}
            onChange={(e) => set("title", e.target.value)}
            placeholder="20% off dinner"
            maxLength={60}
          />
          <Input
            label="One-line subtitle"
            required
            value={form.subtitle}
            error={errors.subtitle}
            onChange={(e) => set("subtitle", e.target.value)}
            placeholder="On all orders over $15 this week"
            maxLength={80}
          />
          <Select
            label="Offer type"
            value={form.promo_type}
            help={typeMeta?.blurb}
            onChange={(e) => set("promo_type", e.target.value as PromoType)}
            options={PROMO_TYPES.map((t) => ({ value: t.value, label: t.label }))}
          />

          {showValue && (
            <Input
              label={valueLabel}
              required
              type="number"
              min="0"
              step={form.promo_type === "percentage" ? "1" : "0.5"}
              prefix={form.promo_type === "percentage" ? undefined : "$"}
              rightSlot={form.promo_type === "percentage" ? <span className="type-body">%</span> : undefined}
              value={form.discount_value}
              error={errors.discount_value}
              onChange={(e) => set("discount_value", e.target.value)}
            />
          )}

          {form.promo_type === "free_item" &&
            (menu.length ? (
              <Select
                label="Which dish is free?"
                required
                value={form.free_item_id}
                error={errors.free_item_id}
                placeholder="Choose a dish"
                onChange={(e) => set("free_item_id", e.target.value)}
                options={menu.map((item) => ({
                  value: item.id,
                  label: `${item.name} — ${formatMoney(item.price_usd)}`,
                }))}
                help="The customer has to add this dish to the basket for the offer to apply."
              />
            ) : (
              <p className="type-caption rounded-md bg-warning-surface p-3 text-warning">
                Add a dish to your menu first — a free-item offer has to point at something you sell.
              </p>
            ))}

          {form.promo_type === "percentage" && (
            <Input
              label="Cap the discount at"
              type="number"
              min="0"
              step="0.5"
              prefix="$"
              value={form.max_discount_usd}
              error={errors.max_discount_usd}
              onChange={(e) => set("max_discount_usd", e.target.value)}
              placeholder="No cap"
              help="Protects your margin on a very large basket. Leave blank for no cap."
            />
          )}

          <Input
            label="Minimum spend"
            type="number"
            min="0"
            step="0.5"
            prefix="$"
            value={form.min_order_usd}
            error={errors.min_order_usd}
            onChange={(e) => set("min_order_usd", e.target.value)}
            help="Food subtotal the basket must reach. Enter 0 for no minimum."
          />
          <Select
            label="Icon in the app"
            value={form.icon}
            onChange={(e) => set("icon", e.target.value)}
            options={ICON_OPTIONS}
          />
        </section>

        <section className="space-y-4" aria-labelledby="promo-limits-heading">
          <h3 id="promo-limits-heading" className="type-overline text-text-secondary">
            Who can use it, and when
          </h3>
          <Input
            label="Promo code"
            value={form.code}
            error={errors.code}
            onChange={(e) => set("code", e.target.value.toUpperCase().replace(/\s+/g, ""))}
            placeholder="DINNER20"
            help="Leave blank to run the offer automatically, with no code to type."
          />
          <div className="grid gap-4 sm:grid-cols-2">
            <Input
              label="Starts"
              type="datetime-local"
              value={form.starts_at}
              onChange={(e) => set("starts_at", e.target.value)}
              help="Leave blank to start now."
            />
            <Input
              label="Ends"
              type="datetime-local"
              value={form.ends_at}
              error={errors.ends_at}
              onChange={(e) => set("ends_at", e.target.value)}
              help="Leave blank to run until you pause it."
            />
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <Input
              label="Total redemptions"
              type="number"
              min="1"
              step="1"
              value={form.max_uses}
              error={errors.max_uses}
              onChange={(e) => set("max_uses", e.target.value)}
              placeholder="Unlimited"
              help="Across all customers."
            />
            <Input
              label="Per customer"
              type="number"
              min="1"
              step="1"
              value={form.max_uses_per_user}
              error={errors.max_uses_per_user}
              onChange={(e) => set("max_uses_per_user", e.target.value)}
            />
          </div>
          <Checkbox
            label="First orders only"
            description="Only customers who have never completed a Zvingo order can use this."
            checked={form.first_order_only}
            onChange={(e) => set("first_order_only", e.target.checked)}
          />
          <Checkbox
            label="Limit to this restaurant"
            description={
              restaurantId
                ? "Uncheck to let the offer apply across every restaurant you own."
                : "You do not have a restaurant yet, so this offer will apply everywhere you own."
            }
            checked={form.scope_to_restaurant && Boolean(restaurantId)}
            disabled={!restaurantId}
            onChange={(e) => set("scope_to_restaurant", e.target.checked)}
          />
          <Textarea
            label="Terms customers should know"
            value={form.description}
            onChange={(e) => set("description", e.target.value)}
            maxLength={280}
            showCount
            placeholder="Dine-in excluded. One per household."
          />
        </section>

        {promo && (
          <section aria-labelledby="promo-history-heading">
            <h3 id="promo-history-heading" className="type-overline text-text-secondary">
              History
            </h3>
            <Card className="mt-2 space-y-1.5 type-caption">
              <div className="flex justify-between gap-3">
                <span className="text-text-secondary">Created</span>
                <span className="tabular-figures">{formatDateTime(promo.created_at)}</span>
              </div>
              <div className="flex justify-between gap-3">
                <span className="text-text-secondary">Last edited</span>
                <span className="tabular-figures">{formatDateTime(promo.updated_at)}</span>
              </div>
              <div className="flex justify-between gap-3">
                <span className="text-text-secondary">Redeemed</span>
                <span className="tabular-figures">{pluralise(promo.current_uses || 0, "time")}</span>
              </div>
            </Card>
          </section>
        )}
      </div>
    </Sheet>
  );
}
