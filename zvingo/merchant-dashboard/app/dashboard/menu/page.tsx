"use client";

import * as React from "react";
import {
  AlertTriangle,
  ArrowDown,
  ArrowUp,
  ChevronDown,
  Copy,
  FolderInput,
  Info,
  LocateFixed,
  Pencil,
  Plus,
  Search,
  SlidersHorizontal,
  Timer,
  Trash2,
  UtensilsCrossed,
  X,
} from "lucide-react";
import { PageContainer, PageSection } from "@/components/AppShell";
import ImageUpload from "@/components/ImageUpload";
import MultiImageUpload from "@/components/MultiImageUpload";
import {
  Badge,
  Button,
  Card,
  Checkbox,
  ConfirmDialog,
  DropdownMenu,
  EmptyState,
  ErrorState,
  IconButton,
  Input,
  MenuRowSkeleton,
  Modal,
  SafeImage,
  Select,
  Sheet,
  StatCard,
  Switch,
  Textarea,
  useToast,
} from "@/components/ui";
import { api, type MenuItem, type Restaurant } from "@/lib/api";
import { useMerchantSession } from "@/lib/useApi";
import { formatMoney, pluralise } from "@/lib/format";

/* -------------------------------------------------------------------------- */
/* Item shape                                                                 */
/* -------------------------------------------------------------------------- */

/**
 * One choice inside an option group, e.g. "Large" at +$2.00.
 * `price_delta_usd` may be negative (a smaller portion costs less).
 */
export interface ModifierOption {
  id: string;
  name: string;
  price_delta_usd: number;
  is_available: boolean;
  is_default: boolean;
}

/**
 * A question the customer answers before the dish goes in the basket.
 *
 * `min_select` 0 makes the group optional; 1 or more makes it required.
 * `max_select` 1 renders as radio buttons, more than 1 as checkboxes.
 */
export interface ModifierGroup {
  id: string;
  name: string;
  description?: string | null;
  min_select: number;
  max_select: number;
  options: ModifierOption[];
}

export interface MenuItemExt extends MenuItem {
  /** Minutes this dish takes to cook, for a per-item prep estimate. */
  prep_time_minutes?: number | null;
  modifier_groups?: ModifierGroup[];
  /** Position within its category; lower comes first. */
  sort_order?: number | null;
}

function newId(): string {
  const random = globalThis.crypto?.randomUUID?.();
  return (random ?? `${Date.now().toString(16)}${Math.random().toString(16).slice(2)}`).replace(/-/g, "").slice(0, 12);
}

/* -------------------------------------------------------------------------- */
/* Backend capability probes                                                  */
/* -------------------------------------------------------------------------- */

/**
 * Beanie serialises every model field, so if the backend knows about a field,
 * *every* item carries it. Probing the payload means these editors light up by
 * themselves the day the backend gains the field — and until then we say so
 * instead of quietly discarding what the merchant typed.
 */
function supports(menu: MenuItemExt[], field: keyof MenuItemExt): boolean {
  return menu.length > 0 && menu.some((item) => item[field] !== undefined);
}

/* -------------------------------------------------------------------------- */
/* Page                                                                       */
/* -------------------------------------------------------------------------- */

export default function MenuPage() {
  const toast = useToast();
  const session = useMerchantSession();
  const restaurantId = session.restaurantId;
  const restaurant = session.restaurant;

  const items = React.useMemo<MenuItemExt[]>(
    () => (restaurant?.menu as MenuItemExt[] | undefined) ?? [],
    [restaurant],
  );

  const canOrder = supports(items, "sort_order");
  const canPrepTime = supports(items, "prep_time_minutes");
  const canModifiers = supports(items, "modifier_groups");

  const [search, setSearch] = React.useState("");
  const [categoryFilter, setCategoryFilter] = React.useState("All");
  const [availabilityFilter, setAvailabilityFilter] = React.useState<"all" | "available" | "sold_out">("all");
  const [selected, setSelected] = React.useState<Set<string>>(new Set());
  const [editing, setEditing] = React.useState<MenuItemExt | null>(null);
  const [creating, setCreating] = React.useState(false);
  const [busyIds, setBusyIds] = React.useState<Set<string>>(new Set());
  const [deleteTarget, setDeleteTarget] = React.useState<MenuItemExt | null>(null);
  const [bulkDelete, setBulkDelete] = React.useState(false);
  const [renameCategory, setRenameCategory] = React.useState<string | null>(null);
  const [moveTarget, setMoveTarget] = React.useState<MenuItemExt[] | null>(null);

  const categories = React.useMemo(() => {
    const seen: string[] = [];
    items.forEach((item) => {
      const category = item.category || "Uncategorised";
      if (!seen.includes(category)) seen.push(category);
    });
    return seen;
  }, [items]);

  const filtered = React.useMemo(() => {
    const query = search.trim().toLowerCase();
    return items.filter((item) => {
      if (categoryFilter !== "All" && (item.category || "Uncategorised") !== categoryFilter) return false;
      if (availabilityFilter === "available" && !item.is_available) return false;
      if (availabilityFilter === "sold_out" && item.is_available) return false;
      if (!query) return true;
      return (
        item.name.toLowerCase().includes(query) ||
        (item.description || "").toLowerCase().includes(query) ||
        (item.category || "").toLowerCase().includes(query)
      );
    });
  }, [items, search, categoryFilter, availabilityFilter]);

  const grouped = React.useMemo(() => {
    const map = new Map<string, MenuItemExt[]>();
    filtered.forEach((item) => {
      const key = item.category || "Uncategorised";
      const list = map.get(key);
      if (list) list.push(item);
      else map.set(key, [item]);
    });
    if (canOrder) {
      map.forEach((list) => list.sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0)));
    }
    return Array.from(map.entries());
  }, [filtered, canOrder]);

  function applyMenu(updated: Restaurant) {
    session.patchRestaurant({ menu: updated.menu });
  }

  function markBusy(ids: string[], busy: boolean) {
    setBusyIds((prev) => {
      const next = new Set(prev);
      ids.forEach((id) => (busy ? next.add(id) : next.delete(id)));
      return next;
    });
  }

  /** Optimistic local patch so a mid-service toggle feels instant. */
  function patchLocal(id: string, patch: Partial<MenuItemExt>) {
    session.patchRestaurant({
      menu: items.map((item) => (item.id === id ? { ...item, ...patch } : item)) as MenuItem[],
    });
  }

  async function updateItem(item: MenuItemExt, body: Record<string, unknown>, optimistic?: Partial<MenuItemExt>) {
    if (!restaurantId) return false;
    const snapshot = items;
    if (optimistic) patchLocal(item.id, optimistic);
    markBusy([item.id], true);
    try {
      const updated = await api.put<Restaurant>(
        `/catalog/restaurants/${restaurantId}/menu/${item.id}`,
        body,
      );
      applyMenu(updated);
      return true;
    } catch (error) {
      session.patchRestaurant({ menu: snapshot as MenuItem[] });
      toast.error(`“${item.name}” did not save`, {
        description: error instanceof Error ? error.message : undefined,
      });
      return false;
    } finally {
      markBusy([item.id], false);
    }
  }

  async function toggleAvailability(item: MenuItemExt) {
    const next = !item.is_available;
    const ok = await updateItem(item, { is_available: next }, { is_available: next });
    if (ok) {
      toast.success(next ? `“${item.name}” is back on` : `“${item.name}” is sold out`, {
        description: next
          ? "Customers can order it again."
          : "It stays on your menu, greyed out, until you switch it back.",
        onUndo: () => void updateItem(item, { is_available: !next }, { is_available: !next }),
      });
    }
  }

  async function bulkSetAvailability(available: boolean) {
    const targets = items.filter((item) => selected.has(item.id) && item.is_available !== available);
    if (!restaurantId || !targets.length) return;
    markBusy(targets.map((t) => t.id), true);
    session.patchRestaurant({
      menu: items.map((item) =>
        selected.has(item.id) ? { ...item, is_available: available } : item,
      ) as MenuItem[],
    });
    let last: Restaurant | null = null;
    let failures = 0;
    for (const item of targets) {
      try {
        last = await api.put<Restaurant>(
          `/catalog/restaurants/${restaurantId}/menu/${item.id}`,
          { is_available: available },
        );
      } catch {
        failures += 1;
      }
    }
    if (last) applyMenu(last);
    markBusy(targets.map((t) => t.id), false);
    setSelected(new Set());
    if (failures) {
      toast.error(`${failures} of ${targets.length} did not save`, {
        description: "Check your connection and try those items again.",
      });
      void session.refresh();
    } else {
      toast.success(
        available
          ? `${pluralise(targets.length, "dish")} back on the menu`
          : `${pluralise(targets.length, "dish")} marked sold out`,
        {
          description: available
            ? "Customers can order them again."
            : "They stay listed but cannot be ordered.",
        },
      );
    }
  }

  async function bulkMove(category: string) {
    const targets = moveTarget ?? [];
    if (!restaurantId || !targets.length || !category.trim()) return;
    setMoveTarget(null);
    markBusy(targets.map((t) => t.id), true);
    let last: Restaurant | null = null;
    let failures = 0;
    for (const item of targets) {
      try {
        last = await api.put<Restaurant>(`/catalog/restaurants/${restaurantId}/menu/${item.id}`, {
          category: category.trim(),
        });
      } catch {
        failures += 1;
      }
    }
    if (last) applyMenu(last);
    markBusy(targets.map((t) => t.id), false);
    setSelected(new Set());
    if (failures) {
      toast.error(`${failures} of ${targets.length} did not move`);
      void session.refresh();
    } else {
      toast.success(`Moved ${pluralise(targets.length, "dish")} to ${category.trim()}`);
    }
  }

  async function duplicate(item: MenuItemExt) {
    if (!restaurantId) return;
    markBusy([item.id], true);
    try {
      const updated = await api.post<Restaurant>(`/catalog/restaurants/${restaurantId}/menu`, {
        name: `${item.name} (copy)`,
        description: item.description ?? null,
        price_usd: item.price_usd,
        category: item.category,
        image_url: item.image_url ?? null,
        images: item.images ?? [],
        ...(canPrepTime ? { prep_time_minutes: item.prep_time_minutes ?? null } : {}),
        ...(canModifiers ? { modifier_groups: item.modifier_groups ?? [] } : {}),
      });
      applyMenu(updated);
      const copy = (updated.menu as MenuItemExt[]).find((entry) => entry.name === `${item.name} (copy)`);
      toast.success("Copied", {
        description: `“${item.name} (copy)” was added and is available straight away.`,
        action: copy ? { label: "Edit it", onClick: () => setEditing(copy) } : undefined,
      });
    } catch (error) {
      toast.error("Could not copy that dish", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      markBusy([item.id], false);
    }
  }

  async function removeItems(targets: MenuItemExt[]) {
    if (!restaurantId || !targets.length) return;
    setDeleteTarget(null);
    setBulkDelete(false);
    markBusy(targets.map((t) => t.id), true);
    let last: Restaurant | null = null;
    let failures = 0;
    for (const item of targets) {
      try {
        last = await api.delete<Restaurant>(`/catalog/restaurants/${restaurantId}/menu/${item.id}`);
      } catch {
        failures += 1;
      }
    }
    if (last) applyMenu(last);
    markBusy(targets.map((t) => t.id), false);
    setSelected(new Set());
    if (failures) {
      toast.error(`${failures} of ${targets.length} could not be deleted`);
      void session.refresh();
    } else {
      toast.success(`Deleted ${pluralise(targets.length, "dish")}`);
    }
  }

  async function renameCategoryTo(from: string, to: string) {
    const targets = items.filter((item) => (item.category || "Uncategorised") === from);
    setRenameCategory(null);
    if (!restaurantId || !to.trim() || to.trim() === from || !targets.length) return;
    markBusy(targets.map((t) => t.id), true);
    let last: Restaurant | null = null;
    let failures = 0;
    for (const item of targets) {
      try {
        last = await api.put<Restaurant>(`/catalog/restaurants/${restaurantId}/menu/${item.id}`, {
          category: to.trim(),
        });
      } catch {
        failures += 1;
      }
    }
    if (last) applyMenu(last);
    markBusy(targets.map((t) => t.id), false);
    if (categoryFilter === from) setCategoryFilter(to.trim());
    if (failures) {
      toast.error(`${failures} dishes kept the old category`);
      void session.refresh();
    } else {
      toast.success(`“${from}” is now “${to.trim()}”`, {
        description: `${pluralise(targets.length, "dish")} moved with it.`,
      });
    }
  }

  async function reorder(item: MenuItemExt, direction: -1 | 1, within: MenuItemExt[]) {
    if (!canOrder || !restaurantId) return;
    const index = within.findIndex((entry) => entry.id === item.id);
    const swapWith = within[index + direction];
    if (!swapWith) return;
    const a = item.sort_order ?? index;
    const b = swapWith.sort_order ?? index + direction;
    markBusy([item.id, swapWith.id], true);
    try {
      await api.put<Restaurant>(`/catalog/restaurants/${restaurantId}/menu/${item.id}`, { sort_order: b });
      const updated = await api.put<Restaurant>(
        `/catalog/restaurants/${restaurantId}/menu/${swapWith.id}`,
        { sort_order: a },
      );
      applyMenu(updated);
    } catch (error) {
      toast.error("Could not reorder", {
        description: error instanceof Error ? error.message : undefined,
      });
      void session.refresh();
    } finally {
      markBusy([item.id, swapWith.id], false);
    }
  }

  /* --- Render ------------------------------------------------------- */

  if (session.isLoading) {
    return (
      <PageContainer>
        <div className="space-y-4">
          <MenuRowSkeleton />
          <MenuRowSkeleton />
          <MenuRowSkeleton />
        </div>
      </PageContainer>
    );
  }

  if (session.error && !restaurant) {
    return (
      <PageContainer>
        <ErrorState
          error={session.error}
          title="We could not load your menu"
          onRetry={() => void session.refresh()}
        />
      </PageContainer>
    );
  }

  if (!restaurantId) {
    return (
      <PageContainer>
        <CreateRestaurant
          onCreated={(created) => {
            session.refresh().catch(() => undefined);
            toast.success("Your storefront is live", {
              description: `“${created.name}” is on Zvingo. Add your first dish next.`,
            });
          }}
        />
      </PageContainer>
    );
  }

  const soldOut = items.filter((item) => !item.is_available).length;
  const selectedItems = items.filter((item) => selected.has(item.id));

  return (
    <PageContainer>
      <PageSection
        title="Menu"
        description={`${restaurant?.name ?? "Your restaurant"} · what customers can order right now.`}
        actions={
          <Button leftIcon={<Plus className="h-4 w-4" />} onClick={() => setCreating(true)}>
            Add a dish
          </Button>
        }
      >
        <div className="grid gap-3 sm:grid-cols-3">
          <StatCard label="Dishes on the menu" value={items.length} icon={UtensilsCrossed} />
          <StatCard
            label="Sold out"
            value={soldOut}
            icon={AlertTriangle}
            lowerIsBetter
            hint={soldOut ? "Customers cannot order these" : "Everything is orderable"}
          />
          <StatCard label="Categories" value={categories.length} icon={FolderInput} />
        </div>
      </PageSection>

      <PageSection>
        <Card flush className="overflow-hidden">
          <div className="flex flex-wrap items-center gap-3 border-b border-divider p-3">
            <Input
              aria-label="Search your menu"
              leftIcon={<Search className="h-4 w-4" />}
              inputSize="sm"
              placeholder="Search dishes"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              containerClassName="min-w-[200px] flex-1"
              rightSlot={
                search ? (
                  <button
                    type="button"
                    onClick={() => setSearch("")}
                    aria-label="Clear search"
                    className="zv-touch flex h-6 w-6 items-center justify-center rounded-full text-text-tertiary hover:text-text-primary"
                  >
                    <X className="h-4 w-4" aria-hidden="true" />
                  </button>
                ) : undefined
              }
            />
            <Select
              aria-label="Filter by availability"
              selectSize="sm"
              value={availabilityFilter}
              onChange={(e) => setAvailabilityFilter(e.target.value as typeof availabilityFilter)}
              options={[
                { value: "all", label: "All dishes" },
                { value: "available", label: "Available only" },
                { value: "sold_out", label: "Sold out only" },
              ]}
              containerClassName="w-44"
            />
          </div>

          <div className="zv-scroll-x flex gap-2 border-b border-divider p-3">
            {["All", ...categories].map((entry) => (
              <button
                key={entry}
                type="button"
                onClick={() => setCategoryFilter(entry)}
                aria-pressed={categoryFilter === entry}
                className={
                  categoryFilter === entry
                    ? "zv-touch h-9 shrink-0 rounded-full bg-action px-4 type-caption font-bold text-neutral-0"
                    : "zv-touch h-9 shrink-0 rounded-full bg-neutral-100 px-4 type-caption font-bold text-neutral-700 hover:bg-neutral-200"
                }
              >
                {entry}
                {entry !== "All" && (
                  <span className="ml-1.5 tabular-figures opacity-70">
                    {items.filter((item) => (item.category || "Uncategorised") === entry).length}
                  </span>
                )}
              </button>
            ))}
          </div>

          {selectedItems.length > 0 && (
            <div className="flex flex-wrap items-center gap-2 border-b border-divider bg-brand-green-surface p-3">
              <p className="type-body-strong text-brand-green-dark">
                {pluralise(selectedItems.length, "dish")} selected
              </p>
              <div className="ml-auto flex flex-wrap items-center gap-2">
                <Button variant="secondary" size="md" onClick={() => void bulkSetAvailability(false)}>
                  Mark sold out
                </Button>
                <Button variant="secondary" size="md" onClick={() => void bulkSetAvailability(true)}>
                  Mark available
                </Button>
                <Button variant="secondary" size="md" onClick={() => setMoveTarget(selectedItems)}>
                  Move to…
                </Button>
                <Button variant="destructive" size="md" onClick={() => setBulkDelete(true)}>
                  Delete
                </Button>
                <Button variant="tertiary" size="md" onClick={() => setSelected(new Set())}>
                  Clear
                </Button>
              </div>
            </div>
          )}

          {!items.length ? (
            <EmptyState
              icon={UtensilsCrossed}
              title="Your menu is empty"
              description="Add your best-selling dish first — a photo, a price and a line of description is all it takes."
              action={
                <Button leftIcon={<Plus className="h-4 w-4" />} onClick={() => setCreating(true)}>
                  Add your first dish
                </Button>
              }
            />
          ) : !filtered.length ? (
            <EmptyState
              icon={Search}
              title="Nothing matches those filters"
              description="Try a different search, category or availability filter."
              action={
                <Button
                  variant="secondary"
                  onClick={() => {
                    setSearch("");
                    setCategoryFilter("All");
                    setAvailabilityFilter("all");
                  }}
                >
                  Clear filters
                </Button>
              }
            />
          ) : (
            <div>
              {grouped.map(([category, list]) => (
                <section key={category}>
                  <header className="flex flex-wrap items-center gap-2 bg-neutral-50 px-3 py-2">
                    <Checkbox
                      aria-label={`Select every dish in ${category}`}
                      checked={list.every((item) => selected.has(item.id))}
                      indeterminate={
                        list.some((item) => selected.has(item.id)) &&
                        !list.every((item) => selected.has(item.id))
                      }
                      onChange={(e) => {
                        const next = new Set(selected);
                        list.forEach((item) => (e.target.checked ? next.add(item.id) : next.delete(item.id)));
                        setSelected(next);
                      }}
                      containerClassName="min-h-0"
                    />
                    <h3 className="type-overline text-text-secondary">{category}</h3>
                    <span className="type-caption tabular-figures text-text-tertiary">
                      {pluralise(list.length, "dish", "dishes")}
                    </span>
                    <div className="ml-auto">
                      <DropdownMenu
                        label={`${category} actions`}
                        trigger={
                          <IconButton
                            label={`Actions for ${category}`}
                            tone="tertiary"
                            icon={<SlidersHorizontal className="h-4 w-4" />}
                          />
                        }
                        items={[
                          {
                            id: "rename",
                            label: "Rename category",
                            icon: <Pencil className="h-4 w-4" />,
                            onSelect: () => setRenameCategory(category),
                          },
                          {
                            id: "sold-out",
                            label: "Mark everything sold out",
                            icon: <AlertTriangle className="h-4 w-4" />,
                            onSelect: () => {
                              setSelected(new Set(list.map((item) => item.id)));
                              void bulkSetAvailability(false);
                            },
                          },
                          {
                            id: "available",
                            label: "Mark everything available",
                            icon: <UtensilsCrossed className="h-4 w-4" />,
                            onSelect: () => {
                              setSelected(new Set(list.map((item) => item.id)));
                              void bulkSetAvailability(true);
                            },
                          },
                          {
                            id: "move",
                            label: "Move all to another category",
                            icon: <FolderInput className="h-4 w-4" />,
                            separatorBefore: true,
                            onSelect: () => setMoveTarget(list),
                          },
                        ]}
                      />
                    </div>
                  </header>

                  <ul className="zv-stagger divide-y divide-divider">
                    {list.map((item, index) => (
                      <ItemRow
                        key={item.id}
                        item={item}
                        index={index}
                        total={list.length}
                        canOrder={canOrder}
                        busy={busyIds.has(item.id)}
                        selected={selected.has(item.id)}
                        onSelect={(checked) => {
                          const next = new Set(selected);
                          if (checked) next.add(item.id);
                          else next.delete(item.id);
                          setSelected(next);
                        }}
                        onToggle={() => void toggleAvailability(item)}
                        onEdit={() => setEditing(item)}
                        onDuplicate={() => void duplicate(item)}
                        onDelete={() => setDeleteTarget(item)}
                        onMove={(direction) => void reorder(item, direction, list)}
                        onRename={(name) => void updateItem(item, { name }, { name })}
                        onReprice={(price) =>
                          void updateItem(item, { price_usd: price }, { price_usd: price })
                        }
                      />
                    ))}
                  </ul>
                </section>
              ))}
            </div>
          )}
        </Card>

        {!canOrder && items.length > 1 && (
          <p className="mt-2 flex items-start gap-2 type-caption text-text-secondary">
            <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            Dishes appear in the order you added them. Zvingo cannot store a custom menu order yet, so the reorder
            controls stay off rather than pretending to work.
          </p>
        )}
      </PageSection>

      <ItemEditor
        open={creating || editing !== null}
        item={editing}
        restaurantId={restaurantId}
        categories={categories}
        canPrepTime={canPrepTime}
        canModifiers={canModifiers}
        onClose={() => {
          setCreating(false);
          setEditing(null);
        }}
        onSaved={(updated, wasNew) => {
          applyMenu(updated);
          setCreating(false);
          setEditing(null);
          toast.success(wasNew ? "Dish added" : "Dish updated", {
            description: wasNew
              ? "It is on your menu and orderable straight away."
              : "Customers see the change immediately.",
          });
        }}
      />

      <ConfirmDialog
        open={deleteTarget !== null}
        tone="destructive"
        title={deleteTarget ? `Delete “${deleteTarget.name}”?` : "Delete this dish?"}
        consequence={
          deleteTarget
            ? `It disappears from the Zvingo app immediately and its photos and description are gone for good. If you have just run out, mark it sold out instead — that keeps the dish and puts it back in one tap.`
            : ""
        }
        confirmLabel="Delete dish"
        cancelLabel="Keep it"
        onCancel={() => setDeleteTarget(null)}
        onConfirm={async () => {
          if (deleteTarget) await removeItems([deleteTarget]);
        }}
      />

      <ConfirmDialog
        open={bulkDelete}
        tone="destructive"
        title={`Delete ${pluralise(selectedItems.length, "dish", "dishes")}?`}
        consequence={`${selectedItems
          .slice(0, 3)
          .map((item) => `“${item.name}”`)
          .join(", ")}${selectedItems.length > 3 ? ` and ${selectedItems.length - 3} more` : ""} will be removed from the Zvingo app for good, along with their photos. Marking them sold out is reversible; this is not.`}
        confirmLabel={`Delete ${selectedItems.length}`}
        cancelLabel="Keep them"
        onCancel={() => setBulkDelete(false)}
        onConfirm={async () => {
          await removeItems(selectedItems);
        }}
      />

      <RenameCategoryDialog
        open={renameCategory !== null}
        category={renameCategory ?? ""}
        count={items.filter((item) => (item.category || "Uncategorised") === renameCategory).length}
        onCancel={() => setRenameCategory(null)}
        onConfirm={(next) => void renameCategoryTo(renameCategory ?? "", next)}
      />

      <MoveCategoryDialog
        open={moveTarget !== null}
        count={moveTarget?.length ?? 0}
        categories={categories}
        onCancel={() => setMoveTarget(null)}
        onConfirm={(category) => void bulkMove(category)}
      />
    </PageContainer>
  );
}

/* -------------------------------------------------------------------------- */
/* Item row                                                                   */
/* -------------------------------------------------------------------------- */

function ItemRow({
  item,
  index,
  total,
  canOrder,
  busy,
  selected,
  onSelect,
  onToggle,
  onEdit,
  onDuplicate,
  onDelete,
  onMove,
  onRename,
  onReprice,
}: {
  item: MenuItemExt;
  index: number;
  total: number;
  canOrder: boolean;
  busy: boolean;
  selected: boolean;
  onSelect: (checked: boolean) => void;
  onToggle: () => void;
  onEdit: () => void;
  onDuplicate: () => void;
  onDelete: () => void;
  onMove: (direction: -1 | 1) => void;
  onRename: (name: string) => void;
  onReprice: (price: number) => void;
}) {
  const groups = item.modifier_groups?.length ?? 0;

  return (
    <li className={selected ? "flex items-start gap-3 bg-brand-green-surface/40 p-3" : "flex items-start gap-3 p-3"}>
      <Checkbox
        aria-label={`Select ${item.name}`}
        checked={selected}
        onChange={(e) => onSelect(e.target.checked)}
        containerClassName="min-h-0 pt-1"
      />

      {canOrder && (
        <div className="flex shrink-0 flex-col">
          <IconButton
            label={`Move ${item.name} up`}
            tone="tertiary"
            disabled={index === 0 || busy}
            icon={<ArrowUp className="h-4 w-4" />}
            onClick={() => onMove(-1)}
            className="h-8 w-8"
          />
          <IconButton
            label={`Move ${item.name} down`}
            tone="tertiary"
            disabled={index === total - 1 || busy}
            icon={<ArrowDown className="h-4 w-4" />}
            onClick={() => onMove(1)}
            className="h-8 w-8"
          />
        </div>
      )}
      <SafeImage
        src={item.image_url || item.images?.[0]}
        alt={item.name}
        ratio="1/1"
        containerClassName={
          item.is_available ? "h-16 w-16 shrink-0 rounded-md" : "h-16 w-16 shrink-0 rounded-md opacity-50"
        }
      />

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <InlineText
            value={item.name}
            label={`Rename ${item.name}`}
            className="type-h3 text-text-primary"
            onCommit={onRename}
          />
          {!item.is_available && <Badge tone="warning">Sold out</Badge>}
          {groups > 0 && <Badge tone="neutral">{pluralise(groups, "option group")}</Badge>}
          {item.prep_time_minutes != null && (
            <Badge tone="neutral" icon={<Timer className="h-3.5 w-3.5" aria-hidden="true" />}>
              {item.prep_time_minutes} min
            </Badge>
          )}
        </div>
        <p className="type-caption mt-1 line-clamp-2 text-text-secondary">
          {item.description || "No description — customers order more when there is one."}
        </p>
      </div>

      <div className="flex shrink-0 items-center gap-2">
        <InlinePrice value={item.price_usd} label={`Change the price of ${item.name}`} onCommit={onReprice} />
        <Switch
          checked={item.is_available}
          onCheckedChange={onToggle}
          busy={busy}
          size="sm"
          aria-label={`${item.name} is ${item.is_available ? "available" : "sold out"}`}
        />
        <DropdownMenu
          label={`${item.name} actions`}
          trigger={
            <IconButton label={`Actions for ${item.name}`} tone="tertiary" icon={<ChevronDown className="h-4 w-4" />} />
          }
          items={[
            { id: "edit", label: "Edit dish", icon: <Pencil className="h-4 w-4" />, onSelect: onEdit },
            { id: "duplicate", label: "Duplicate", icon: <Copy className="h-4 w-4" />, onSelect: onDuplicate },
            {
              id: "delete",
              label: "Delete",
              icon: <Trash2 className="h-4 w-4" />,
              destructive: true,
              separatorBefore: true,
              onSelect: onDelete,
            },
          ]}
        />
      </div>
    </li>
  );
}

/** Click-to-edit text that commits on blur or Enter and reverts on Escape. */
function InlineText({
  value,
  label,
  className,
  onCommit,
}: {
  value: string;
  label: string;
  className?: string;
  onCommit: (next: string) => void;
}) {
  const [editing, setEditing] = React.useState(false);
  const [draft, setDraft] = React.useState(value);
  React.useEffect(() => setDraft(value), [value]);

  if (!editing) {
    return (
      <button
        type="button"
        onClick={() => setEditing(true)}
        aria-label={label}
        className={`truncate rounded-sm text-left hover:bg-neutral-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action ${className ?? ""}`}
      >
        {value}
      </button>
    );
  }

  return (
    <Input
      autoFocus
      inputSize="sm"
      aria-label={label}
      value={draft}
      containerClassName="w-56"
      onChange={(e) => setDraft(e.target.value)}
      onBlur={() => {
        setEditing(false);
        if (draft.trim() && draft !== value) onCommit(draft.trim());
        else setDraft(value);
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter") (e.target as HTMLInputElement).blur();
        if (e.key === "Escape") {
          setDraft(value);
          setEditing(false);
        }
      }}
    />
  );
}

function InlinePrice({
  value,
  label,
  onCommit,
}: {
  value: number;
  label: string;
  onCommit: (next: number) => void;
}) {
  const [editing, setEditing] = React.useState(false);
  const [draft, setDraft] = React.useState(String(value));
  React.useEffect(() => setDraft(String(value)), [value]);

  if (!editing) {
    return (
      <button
        type="button"
        onClick={() => setEditing(true)}
        aria-label={label}
        className="zv-touch rounded-sm px-1.5 py-1 type-body-strong tabular-figures text-text-primary hover:bg-neutral-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
      >
        {formatMoney(value)}
      </button>
    );
  }

  return (
    <Input
      autoFocus
      type="number"
      min="0"
      step="0.25"
      prefix="$"
      inputSize="sm"
      aria-label={label}
      value={draft}
      containerClassName="w-28"
      onChange={(e) => setDraft(e.target.value)}
      onBlur={() => {
        setEditing(false);
        const next = Number(draft);
        if (Number.isFinite(next) && next >= 0 && next !== value) onCommit(next);
        else setDraft(String(value));
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter") (e.target as HTMLInputElement).blur();
        if (e.key === "Escape") {
          setDraft(String(value));
          setEditing(false);
        }
      }}
    />
  );
}

/* -------------------------------------------------------------------------- */
/* Dialogs                                                                    */
/* -------------------------------------------------------------------------- */

function RenameCategoryDialog({
  open,
  category,
  count,
  onCancel,
  onConfirm,
}: {
  open: boolean;
  category: string;
  count: number;
  onCancel: () => void;
  onConfirm: (next: string) => void;
}) {
  const [name, setName] = React.useState(category);
  React.useEffect(() => setName(category), [category, open]);

  return (
    <Modal
      open={open}
      onClose={onCancel}
      size="sm"
      title={`Rename “${category}”`}
      description={`${pluralise(count, "dish", "dishes")} will move to the new name. Customers see it immediately.`}
      footer={
        <>
          <Button variant="secondary" onClick={onCancel}>
            Cancel
          </Button>
          <Button onClick={() => onConfirm(name)} disabled={!name.trim() || name.trim() === category}>
            Rename category
          </Button>
        </>
      }
    >
      <Input
        label="Category name"
        autoFocus
        value={name}
        onChange={(e) => setName(e.target.value)}
        maxLength={40}
      />
    </Modal>
  );
}

function MoveCategoryDialog({
  open,
  count,
  categories,
  onCancel,
  onConfirm,
}: {
  open: boolean;
  count: number;
  categories: string[];
  onCancel: () => void;
  onConfirm: (category: string) => void;
}) {
  const [choice, setChoice] = React.useState("");
  const [custom, setCustom] = React.useState("");
  React.useEffect(() => {
    if (open) {
      setChoice(categories[0] ?? "");
      setCustom("");
    }
  }, [open, categories]);

  const target = choice === "__new__" ? custom : choice;

  return (
    <Modal
      open={open}
      onClose={onCancel}
      size="sm"
      title={`Move ${pluralise(count, "dish", "dishes")}`}
      description="Pick the category they should appear under in the Zvingo app."
      footer={
        <>
          <Button variant="secondary" onClick={onCancel}>
            Cancel
          </Button>
          <Button onClick={() => onConfirm(target)} disabled={!target.trim()}>
            Move {count}
          </Button>
        </>
      }
    >
      <Select
        label="Category"
        value={choice}
        onChange={(e) => setChoice(e.target.value)}
        options={[
          ...categories.map((category) => ({ value: category, label: category })),
          { value: "__new__", label: "New category…" },
        ]}
      />
      {choice === "__new__" && (
        <Input
          label="New category name"
          autoFocus
          value={custom}
          onChange={(e) => setCustom(e.target.value)}
          maxLength={40}
          containerClassName="mt-4"
        />
      )}
    </Modal>
  );
}

/* -------------------------------------------------------------------------- */
/* Item editor                                                                */
/* -------------------------------------------------------------------------- */

interface ItemDraft {
  name: string;
  description: string;
  price: string;
  category: string;
  images: string[];
  isAvailable: boolean;
  prepTime: string;
  groups: ModifierGroup[];
}

const BLANK_DRAFT: ItemDraft = {
  name: "",
  description: "",
  price: "",
  category: "",
  images: [],
  isAvailable: true,
  prepTime: "",
  groups: [],
};

function ItemEditor({
  open,
  item,
  restaurantId,
  categories,
  canPrepTime,
  canModifiers,
  onClose,
  onSaved,
}: {
  open: boolean;
  item: MenuItemExt | null;
  restaurantId: string;
  categories: string[];
  canPrepTime: boolean;
  canModifiers: boolean;
  onClose: () => void;
  onSaved: (restaurant: Restaurant, wasNew: boolean) => void;
}) {
  const toast = useToast();
  const [draft, setDraft] = React.useState<ItemDraft>(BLANK_DRAFT);
  const [saving, setSaving] = React.useState(false);
  const [errors, setErrors] = React.useState<{ name?: string; price?: string; category?: string }>({});

  React.useEffect(() => {
    if (!open) return;
    setErrors({});
    setDraft(
      item
        ? {
            name: item.name,
            description: item.description ?? "",
            price: String(item.price_usd),
            category: item.category || "",
            images: item.images?.length ? item.images : item.image_url ? [item.image_url] : [],
            isAvailable: item.is_available,
            prepTime: item.prep_time_minutes != null ? String(item.prep_time_minutes) : "",
            groups: item.modifier_groups ?? [],
          }
        : BLANK_DRAFT,
    );
  }, [open, item]);

  const set = <K extends keyof ItemDraft>(key: K, value: ItemDraft[K]) =>
    setDraft((prev) => ({ ...prev, [key]: value }));

  async function submit() {
    const found: typeof errors = {};
    if (!draft.name.trim()) found.name = "Give the dish the name customers will read.";
    const price = Number(draft.price);
    if (!Number.isFinite(price) || price <= 0) found.price = "Enter what this dish costs, e.g. 8.50.";
    if (!draft.category.trim()) found.category = "Pick or type a section of your menu, e.g. Mains.";
    setErrors(found);
    if (Object.keys(found).length) {
      toast.error("Some details are missing", { description: Object.values(found)[0] });
      return;
    }

    const body: Record<string, unknown> = {
      name: draft.name.trim(),
      description: draft.description.trim() || null,
      price_usd: price,
      category: draft.category.trim(),
      image_url: draft.images[0] ?? null,
      images: draft.images,
      ...(canPrepTime ? { prep_time_minutes: draft.prepTime === "" ? null : Number(draft.prepTime) } : {}),
      ...(canModifiers ? { modifier_groups: draft.groups } : {}),
    };
    if (item) body.is_available = draft.isAvailable;

    setSaving(true);
    try {
      const updated = item
        ? await api.put<Restaurant>(`/catalog/restaurants/${restaurantId}/menu/${item.id}`, body)
        : await api.post<Restaurant>(`/catalog/restaurants/${restaurantId}/menu`, body);
      onSaved(updated, !item);
    } catch (error) {
      toast.error("The dish did not save", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSaving(false);
    }
  }

  const price = Number(draft.price) || 0;

  return (
    <Sheet
      open={open}
      onClose={onClose}
      width="lg"
      title={item ? `Edit “${item.name}”` : "Add a dish"}
      description="Exactly what a customer sees when they tap this dish."
      footer={
        <>
          <Button variant="secondary" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={() => void submit()} loading={saving}>
            {item ? "Save changes" : "Add to menu"}
          </Button>
        </>
      }
    >
      <div className="space-y-6">
        <section className="space-y-4">
          <Input
            label="Dish name"
            required
            autoFocus
            value={draft.name}
            error={errors.name}
            onChange={(e) => set("name", e.target.value)}
            placeholder="Grilled chicken and sadza"
            maxLength={80}
          />
          <Textarea
            label="Description"
            value={draft.description}
            onChange={(e) => set("description", e.target.value)}
            maxLength={300}
            showCount
            help="What is in it, how big it is, how hot it is. Dishes with a description sell more."
          />
          <div className="grid gap-4 sm:grid-cols-2">
            <Input
              label="Price"
              required
              type="number"
              min="0"
              step="0.25"
              prefix="$"
              value={draft.price}
              error={errors.price}
              onChange={(e) => set("price", e.target.value)}
            />
            <Input
              label="Menu section"
              required
              list="menu-categories"
              value={draft.category}
              error={errors.category}
              onChange={(e) => set("category", e.target.value)}
              placeholder="Mains"
              help="Type a new one or pick an existing section."
            />
            <datalist id="menu-categories">
              {categories.map((category) => (
                <option key={category} value={category} />
              ))}
            </datalist>
          </div>

          {item && (
            <Switch
              checked={draft.isAvailable}
              onCheckedChange={(next) => set("isAvailable", next)}
              label={draft.isAvailable ? "Available to order" : "Sold out"}
              description={
                draft.isAvailable
                  ? "Customers can add it to the basket."
                  : "It stays on the menu, greyed out, until you switch it back."
              }
            />
          )}

          {canPrepTime ? (
            <Input
              label="Prep time"
              type="number"
              min="1"
              step="1"
              value={draft.prepTime}
              onChange={(e) => set("prepTime", e.target.value)}
              placeholder="Use the restaurant default"
              rightSlot={<span className="type-caption">min</span>}
              help="How long this one dish takes, if it is slower than the rest of your menu."
            />
          ) : (
            <p className="flex items-start gap-2 rounded-md bg-neutral-50 p-3 type-caption text-text-secondary">
              <Timer className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
              <span>
                <strong className="font-semibold text-text-primary">Per-dish prep time is not stored yet.</strong>{" "}
                Zvingo uses the restaurant-wide estimate you set under Settings → Delivery and prep time.
              </span>
            </p>
          )}
        </section>

        <section>
          <h3 className="type-overline text-text-secondary">Photos</h3>
          <div className="mt-2">
            <MultiImageUpload values={draft.images} onChange={(images) => set("images", images)} />
          </div>
        </section>

        <ModifierGroupsEditor
          groups={draft.groups}
          basePrice={price}
          enabled={canModifiers}
          onChange={(groups) => set("groups", groups)}
        />
      </div>
    </Sheet>
  );
}

/* -------------------------------------------------------------------------- */
/* Option groups                                                              */
/* -------------------------------------------------------------------------- */

function ModifierGroupsEditor({
  groups,
  basePrice,
  enabled,
  onChange,
}: {
  groups: ModifierGroup[];
  basePrice: number;
  enabled: boolean;
  onChange: (groups: ModifierGroup[]) => void;
}) {
  function patch(id: string, next: Partial<ModifierGroup>) {
    onChange(groups.map((group) => (group.id === id ? { ...group, ...next } : group)));
  }

  function patchOption(groupId: string, optionId: string, next: Partial<ModifierOption>) {
    onChange(
      groups.map((group) =>
        group.id === groupId
          ? {
              ...group,
              options: group.options.map((option) =>
                option.id === optionId ? { ...option, ...next } : option,
              ),
            }
          : group,
      ),
    );
  }

  return (
    <section>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h3 className="type-overline text-text-secondary">Options and extras</h3>
          <p className="type-caption text-text-secondary">
            The questions a customer answers before this dish goes in the basket — size, sides, spice, add-ons.
          </p>
        </div>
        <Button
          variant="secondary"
          size="md"
          disabled={!enabled}
          leftIcon={<Plus className="h-4 w-4" />}
          onClick={() =>
            onChange([
              ...groups,
              {
                id: newId(),
                name: "",
                description: null,
                min_select: 1,
                max_select: 1,
                options: [
                  { id: newId(), name: "", price_delta_usd: 0, is_available: true, is_default: true },
                ],
              },
            ])
          }
        >
          Add option group
        </Button>
      </div>

      {!enabled && (
        <p className="mt-2 flex items-start gap-2 rounded-md bg-warning-surface p-3 type-caption text-warning">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
          <span>
            <strong className="font-semibold">Zvingo cannot store option groups yet.</strong> The menu-item record
            has no field for them, so anything typed here would be thrown away on save. The editor switches itself
            on the moment the backend supports it — no change needed here.
          </span>
        </p>
      )}

      {enabled && !groups.length && (
        <p className="mt-2 rounded-md bg-neutral-50 p-3 type-caption text-text-secondary">
          No options on this dish. Add a group for a choice the customer must make (“Choose a size”) or may make
          (“Add extras”).
        </p>
      )}

      <div className="mt-3 space-y-3">
        {groups.map((group, groupIndex) => {
          const required = group.min_select > 0;
          return (
            <Card key={group.id} className="space-y-3">
              <div className="flex flex-wrap items-end gap-3">
                <Input
                  label={`Group ${groupIndex + 1} name`}
                  inputSize="sm"
                  value={group.name}
                  disabled={!enabled}
                  onChange={(e) => patch(group.id, { name: e.target.value })}
                  placeholder="Choose a size"
                  containerClassName="min-w-[200px] flex-1"
                />
                <IconButton
                  label={`Remove ${group.name || `group ${groupIndex + 1}`}`}
                  tone="destructive"
                  disabled={!enabled}
                  icon={<Trash2 className="h-4 w-4" />}
                  onClick={() => onChange(groups.filter((entry) => entry.id !== group.id))}
                />
              </div>

              <div className="grid gap-3 sm:grid-cols-3">
                <Select
                  label="Customer must choose?"
                  selectSize="sm"
                  disabled={!enabled}
                  value={required ? "required" : "optional"}
                  onChange={(e) =>
                    patch(group.id, {
                      min_select: e.target.value === "required" ? Math.max(1, group.min_select || 1) : 0,
                    })
                  }
                  options={[
                    { value: "required", label: "Required" },
                    { value: "optional", label: "Optional" },
                  ]}
                />
                <Input
                  label="Choose at least"
                  type="number"
                  min="0"
                  step="1"
                  inputSize="sm"
                  disabled={!enabled}
                  value={String(group.min_select)}
                  onChange={(e) =>
                    patch(group.id, { min_select: Math.max(0, Number(e.target.value) || 0) })
                  }
                />
                <Input
                  label="Choose at most"
                  type="number"
                  min="1"
                  step="1"
                  inputSize="sm"
                  disabled={!enabled}
                  value={String(group.max_select)}
                  onChange={(e) =>
                    patch(group.id, { max_select: Math.max(1, Number(e.target.value) || 1) })
                  }
                  help={group.max_select > 1 ? "Shown as tick boxes" : "Shown as a single choice"}
                />
              </div>

              <div className="space-y-2">
                {group.options.map((option, optionIndex) => (
                  <div key={option.id} className="flex flex-wrap items-end gap-2">
                    <Input
                      label={optionIndex === 0 ? "Choice" : undefined}
                      aria-label={`Choice ${optionIndex + 1} in ${group.name || "this group"}`}
                      inputSize="sm"
                      disabled={!enabled}
                      value={option.name}
                      placeholder="Large"
                      containerClassName="min-w-[160px] flex-1"
                      onChange={(e) => patchOption(group.id, option.id, { name: e.target.value })}
                    />
                    <Input
                      label={optionIndex === 0 ? "Price change" : undefined}
                      aria-label={`Price change for choice ${optionIndex + 1}`}
                      type="number"
                      step="0.25"
                      prefix="$"
                      inputSize="sm"
                      disabled={!enabled}
                      value={String(option.price_delta_usd)}
                      containerClassName="w-32"
                      onChange={(e) =>
                        patchOption(group.id, option.id, {
                          price_delta_usd: Number(e.target.value) || 0,
                        })
                      }
                      help={
                        optionIndex === 0
                          ? `Dish becomes ${formatMoney(basePrice + option.price_delta_usd)}`
                          : undefined
                      }
                    />
                    <Switch
                      size="sm"
                      disabled={!enabled}
                      checked={option.is_available}
                      onCheckedChange={(next) => patchOption(group.id, option.id, { is_available: next })}
                      aria-label={`${option.name || `Choice ${optionIndex + 1}`} is ${option.is_available ? "available" : "sold out"}`}
                    />
                    <IconButton
                      label={`Remove choice ${optionIndex + 1}`}
                      tone="tertiary"
                      disabled={!enabled || group.options.length === 1}
                      icon={<X className="h-4 w-4" />}
                      onClick={() =>
                        patch(group.id, {
                          options: group.options.filter((entry) => entry.id !== option.id),
                        })
                      }
                    />
                  </div>
                ))}
                <Button
                  variant="tertiary"
                  size="md"
                  disabled={!enabled}
                  leftIcon={<Plus className="h-4 w-4" />}
                  onClick={() =>
                    patch(group.id, {
                      options: [
                        ...group.options,
                        { id: newId(), name: "", price_delta_usd: 0, is_available: true, is_default: false },
                      ],
                    })
                  }
                >
                  Add a choice
                </Button>
              </div>
            </Card>
          );
        })}
      </div>
    </section>
  );
}

/* -------------------------------------------------------------------------- */
/* First-run: create the storefront                                           */
/* -------------------------------------------------------------------------- */

function CreateRestaurant({ onCreated }: { onCreated: (restaurant: Restaurant) => void }) {
  const toast = useToast();
  const [name, setName] = React.useState("");
  const [description, setDescription] = React.useState("");
  const [logo, setLogo] = React.useState("");
  const [cuisines, setCuisines] = React.useState("");
  const [coords, setCoords] = React.useState<{ lat: number; lng: number } | null>(null);
  const [locating, setLocating] = React.useState(false);
  const [locateError, setLocateError] = React.useState("");
  const [saving, setSaving] = React.useState(false);

  function useMyLocation() {
    if (!navigator.geolocation) {
      setLocateError("This browser will not share its location. Type your coordinates below instead.");
      return;
    }
    setLocating(true);
    setLocateError("");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setCoords({ lat: position.coords.latitude, lng: position.coords.longitude });
        setLocating(false);
      },
      (error) => {
        setLocating(false);
        setLocateError(
          error.code === error.PERMISSION_DENIED
            ? "Your browser blocked location access. Allow it in the address bar, or type the coordinates below."
            : "We could not work out where you are. Type the coordinates below instead.",
        );
      },
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 60_000 },
    );
  }

  async function create() {
    if (!name.trim() || !coords) return;
    setSaving(true);
    try {
      const created = await api.post<Restaurant>("/catalog/restaurants", {
        name: name.trim(),
        description: description.trim() || null,
        categories: cuisines
          .split(",")
          .map((entry) => entry.trim())
          .filter(Boolean),
        lat: coords.lat,
        lng: coords.lng,
        delivery_time_min: 30,
        delivery_time_max: 45,
        delivery_fee_usd: 2,
        image_url: logo || null,
      });
      onCreated(created);
    } catch (error) {
      toast.error("We could not create your restaurant", {
        description: error instanceof Error ? error.message : undefined,
      });
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl">
      <PageSection
        title="Set up your storefront"
        description="Three things and you are on Zvingo: a name, a photo, and where drivers collect from."
      >
        <Card className="space-y-4">
          <Input
            label="Restaurant name"
            required
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Harare Social Kitchen"
            maxLength={80}
          />
          <Textarea
            label="Description"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            maxLength={280}
            showCount
            help="What you are famous for, in a sentence."
          />
          <Input
            label="Cuisine tags"
            value={cuisines}
            onChange={(e) => setCuisines(e.target.value)}
            placeholder="Grill, Sadza, Takeaway"
            help="Separate with commas. These are how customers filter for you — they cannot be changed later yet, so get them right."
          />
          <div>
            <p className="type-caption mb-2 font-semibold text-text-primary">Logo</p>
            <ImageUpload value={logo} onChange={setLogo} placeholder="Upload logo" />
          </div>

          <div className="rounded-md border border-border p-3">
            <p className="type-body-strong text-text-primary">Where do drivers collect?</p>
            <p className="type-caption mt-0.5 text-text-secondary">
              Zvingo needs a real pickup point — we will not guess one for you. Share your location from the
              restaurant, or type the coordinates. You can drag the exact pin on a map afterwards in Settings.
            </p>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <Button
                variant="secondary"
                size="md"
                onClick={useMyLocation}
                loading={locating}
                leftIcon={<LocateFixed className="h-4 w-4" />}
              >
                Use my current location
              </Button>
              {coords && (
                <Badge tone="success">
                  Pickup set to {coords.lat.toFixed(5)}, {coords.lng.toFixed(5)}
                </Badge>
              )}
            </div>
            {locateError && (
              <p role="alert" className="type-caption mt-2 text-error">
                {locateError}
              </p>
            )}
            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              <Input
                label="Latitude"
                type="number"
                step="0.000001"
                inputSize="sm"
                value={coords ? String(coords.lat) : ""}
                onChange={(e) => {
                  const lat = Number(e.target.value);
                  if (Number.isFinite(lat) && e.target.value !== "") {
                    setCoords({ lat, lng: coords?.lng ?? 0 });
                  }
                }}
              />
              <Input
                label="Longitude"
                type="number"
                step="0.000001"
                inputSize="sm"
                value={coords ? String(coords.lng) : ""}
                onChange={(e) => {
                  const lng = Number(e.target.value);
                  if (Number.isFinite(lng) && e.target.value !== "") {
                    setCoords({ lat: coords?.lat ?? 0, lng });
                  }
                }}
              />
            </div>
          </div>

          <Button
            fullWidth
            size="lg"
            onClick={() => void create()}
            loading={saving}
            disabled={!name.trim() || !coords}
          >
            Create my restaurant
          </Button>
          {(!name.trim() || !coords) && (
            <p className="type-caption text-text-secondary">
              {!name.trim()
                ? "Add a restaurant name to continue."
                : "Set your pickup location to continue — every delivery starts there."}
            </p>
          )}
        </Card>
      </PageSection>
    </div>
  );
}
