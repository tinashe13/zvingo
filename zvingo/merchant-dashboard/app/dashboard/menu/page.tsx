"use client";

import { useEffect, useMemo, useState } from "react";
import { ImageIcon, MoreHorizontal, PackageOpen, Pencil, Plus, Search, Trash2, UtensilsCrossed } from "lucide-react";
import { apiJson } from "@/lib/api";
import ImageUpload from "@/components/ImageUpload";
import MultiImageUpload from "@/components/MultiImageUpload";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";
import { EmptyState, Field, LoadingState, Modal, PageHeader, PageShell, Panel, StatusBadge, Toggle } from "@/components/merchant/Page";

const DEFAULT_RESTAURANT_LAT = Number(process.env.NEXT_PUBLIC_DEFAULT_RESTAURANT_LAT || "-17.82");
const DEFAULT_RESTAURANT_LNG = Number(process.env.NEXT_PUBLIC_DEFAULT_RESTAURANT_LNG || "31.05");

type MenuItem = { id: string; name: string; price_usd: number; is_available: boolean; category: string; description?: string; image_url?: string; images?: string[] };
type Restaurant = { id?: string; _id?: string; name: string; menu?: MenuItem[] };
type ItemDraft = { name: string; price: string; category: string; description: string; images: string[] };
const emptyDraft: ItemDraft = { name: "", price: "", category: "", description: "", images: [] };

export default function MenuPage() {
    const [items, setItems] = useState<MenuItem[]>([]);
    const [loading, setLoading] = useState(true);
    const [restaurant, setRestaurant] = useState<Restaurant | null>(null);
    const [draft, setDraft] = useState<ItemDraft>(emptyDraft);
    const [editingItem, setEditingItem] = useState<MenuItem | null>(null);
    const [showAddForm, setShowAddForm] = useState(false);
    const [search, setSearch] = useState("");
    const [category, setCategory] = useState("All");
    const [restName, setRestName] = useState("");
    const [restDesc, setRestDesc] = useState("");
    const [restImageUrl, setRestImageUrl] = useState("");
    const [saving, setSaving] = useState(false);

    useEffect(() => {
        async function init() {
            try {
                const me = await apiJson("/auth/me");
                const restaurants = await apiJson(`/catalog/restaurants?merchant_id=${me.id}`);
                if (restaurants.length) {
                    setRestaurant(restaurants[0]);
                    setItems(restaurants[0].menu || []);
                }
            } catch (err) { console.error("Failed to load menu:", err); }
            finally { setLoading(false); }
        }
        init();
    }, []);

    const restaurantId = restaurant?._id || restaurant?.id;
    const categories = useMemo(() => ["All", ...Array.from(new Set(items.map((item) => item.category))).sort()], [items]);
    const filteredItems = useMemo(() => items.filter((item) => {
        const matchesCategory = category === "All" || item.category === category;
        const query = search.trim().toLowerCase();
        return matchesCategory && (!query || item.name.toLowerCase().includes(query) || item.description?.toLowerCase().includes(query));
    }), [items, search, category]);

    async function createRestaurant() {
        if (!restName.trim()) return;
        setSaving(true);
        try {
            const created = await apiJson("/catalog/restaurants", { method: "POST", body: JSON.stringify({ name: restName, description: restDesc, lat: DEFAULT_RESTAURANT_LAT, lng: DEFAULT_RESTAURANT_LNG, categories: ["General"], delivery_time_min: 30, delivery_time_max: 45, delivery_fee_usd: 2, image_url: restImageUrl }) });
            setRestaurant(created);
            setItems(created.menu || []);
        } catch (err) { console.error("Failed to create restaurant:", err); alert("Failed to create restaurant"); }
        finally { setSaving(false); }
    }

    async function toggleAvailability(item: MenuItem) {
        if (!restaurantId) return;
        const previous = items;
        setItems(items.map((entry) => entry.id === item.id ? { ...entry, is_available: !item.is_available } : entry));
        try { await apiJson(`/catalog/restaurants/${restaurantId}/menu/${item.id}`, { method: "PUT", body: JSON.stringify({ is_available: !item.is_available }) }); }
        catch (err) { console.error("Failed to update availability:", err); setItems(previous); alert("Failed to update item availability"); }
    }

    async function saveNewItem() {
        if (!draft.name || !draft.price || !draft.category || !restaurantId) return;
        setSaving(true);
        try {
            const updated = await apiJson(`/catalog/restaurants/${restaurantId}/menu`, { method: "POST", body: JSON.stringify({ name: draft.name, price_usd: Number(draft.price), category: draft.category, description: draft.description, image_url: draft.images[0] || null, images: draft.images }) });
            setItems(updated.menu || []); setDraft(emptyDraft); setShowAddForm(false);
        } catch (err) { console.error("Failed to add item:", err); alert("Failed to add item"); }
        finally { setSaving(false); }
    }

    function openEdit(item: MenuItem) {
        setEditingItem(item);
        setDraft({ name: item.name, price: String(item.price_usd), category: item.category, description: item.description || "", images: item.images || (item.image_url ? [item.image_url] : []) });
    }

    async function saveEditedItem() {
        if (!editingItem || !restaurantId) return;
        setSaving(true);
        try {
            const updated = await apiJson(`/catalog/restaurants/${restaurantId}/menu/${editingItem.id}`, { method: "PUT", body: JSON.stringify({ name: draft.name, price_usd: Number(draft.price), category: draft.category, description: draft.description, image_url: draft.images[0] || null, images: draft.images }) });
            setItems(updated.menu || []); setEditingItem(null); setDraft(emptyDraft);
        } catch (err) { console.error("Failed to update item:", err); alert("Failed to update item"); }
        finally { setSaving(false); }
    }

    async function deleteItem(item: MenuItem) {
        if (!restaurantId || !confirm(`Delete "${item.name}" from the menu?`)) return;
        const previous = items; setItems(items.filter((entry) => entry.id !== item.id));
        try { await apiJson(`/catalog/restaurants/${restaurantId}/menu/${item.id}`, { method: "DELETE" }); }
        catch (err) { console.error("Failed to delete item:", err); setItems(previous); alert("Failed to delete item"); }
    }

    if (loading) return <LoadingState />;

    if (!restaurant) {
        return <PageShell className="max-w-3xl"><PageHeader eyebrow="GET STARTED" title="Build your storefront" description="Add the restaurant details customers will see before you publish your first menu." />
            <Panel title="Restaurant profile" description="You can fine-tune delivery settings later."><div className="space-y-5 p-6 sm:p-7"><Field label="Restaurant name" required><Input value={restName} onChange={(event) => setRestName(event.target.value)} placeholder="e.g. Harare Social Kitchen" /></Field><Field label="Description"><textarea className="min-h-28 w-full rounded-xl border border-transparent bg-neutral-100 px-4 py-3 text-sm outline-none focus:border-neutral-900 focus:ring-2 focus:ring-neutral-900/10" value={restDesc} onChange={(event) => setRestDesc(event.target.value)} placeholder="Tell customers what makes your food special" /></Field><Field label="Restaurant logo"><ImageUpload value={restImageUrl} onChange={setRestImageUrl} placeholder="Upload logo" /></Field><Button className="w-full sm:w-auto" onClick={createRestaurant} isLoading={saving}>Create restaurant</Button></div></Panel>
        </PageShell>;
    }

    return (
        <PageShell>
            <PageHeader eyebrow="CATALOG" title="Menu" description={`${restaurant.name} · ${items.length} items · ${items.filter((item) => item.is_available).length} available`} actions={<Button onClick={() => { setDraft(emptyDraft); setShowAddForm(true); }}><Plus className="mr-2 h-4 w-4" />Add item</Button>} />

            <div className="mb-6 grid gap-4 sm:grid-cols-3">
                <Summary label="Menu items" value={String(items.length)} icon={UtensilsCrossed} />
                <Summary label="Available now" value={String(items.filter((item) => item.is_available).length)} icon={PackageOpen} />
                <Summary label="Categories" value={String(Math.max(0, categories.length - 1))} icon={MoreHorizontal} />
            </div>

            <Panel>
                <div className="flex flex-wrap items-center gap-3 border-b border-neutral-100 p-4 sm:px-6">
                    <div className="relative min-w-[220px] flex-1"><Search className="absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-neutral-400" /><Input className="pl-11" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search your menu" /></div>
                    <div className="flex max-w-full gap-2 overflow-x-auto py-1">{categories.map((entry) => <button key={entry} onClick={() => setCategory(entry)} className={`h-10 shrink-0 rounded-full px-4 text-xs font-bold ${category === entry ? "bg-neutral-900 text-white" : "bg-neutral-100 text-neutral-600 hover:bg-neutral-200"}`}>{entry}</button>)}</div>
                </div>

                {filteredItems.length ? <div className="grid gap-px bg-neutral-100 md:grid-cols-2 xl:grid-cols-3">{filteredItems.map((item) => <MenuCard key={item.id} item={item} onToggle={() => toggleAvailability(item)} onEdit={() => openEdit(item)} onDelete={() => deleteItem(item)} />)}</div> : <EmptyState icon={Search} title={items.length ? "No matching dishes" : "Your menu is ready for its first dish"} description={items.length ? "Try another search or category." : "Add an item with a photo, description, price, and availability."} action={!items.length ? <Button onClick={() => setShowAddForm(true)}><Plus className="mr-2 h-4 w-4" />Add first item</Button> : undefined} />}
            </Panel>

            {showAddForm && <ItemModal title="Add menu item" description="Create the customer-facing listing for this dish." draft={draft} setDraft={setDraft} onClose={() => setShowAddForm(false)} onSave={saveNewItem} saving={saving} saveLabel="Add to menu" />}
            {editingItem && <ItemModal title={`Edit ${editingItem.name}`} description="Changes appear in the consumer app immediately." draft={draft} setDraft={setDraft} onClose={() => { setEditingItem(null); setDraft(emptyDraft); }} onSave={saveEditedItem} saving={saving} saveLabel="Save changes" />}
        </PageShell>
    );
}

function Summary({ label, value, icon: Icon }: { label: string; value: string; icon: typeof UtensilsCrossed }) {
    return <div className="flex items-center justify-between rounded-2xl border border-neutral-200/70 bg-white p-5 shadow-sm"><div><p className="text-xs font-bold text-neutral-500">{label}</p><p className="mt-2 text-3xl font-black tracking-tight text-neutral-900">{value}</p></div><span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-neutral-100 text-neutral-700"><Icon className="h-5 w-5" /></span></div>;
}

function MenuCard({ item, onToggle, onEdit, onDelete }: { item: MenuItem; onToggle: () => void; onEdit: () => void; onDelete: () => void }) {
    return <article className="bg-white p-5"><div className="relative aspect-[16/10] overflow-hidden rounded-2xl bg-neutral-100">{item.image_url ? <img src={item.image_url} alt={item.name} className="h-full w-full object-cover" /> : <div className="flex h-full items-center justify-center text-neutral-300"><ImageIcon className="h-10 w-10" /></div>}<div className="absolute left-3 top-3"><StatusBadge active={item.is_available} activeLabel="Available" inactiveLabel="Hidden" /></div></div><div className="mt-4 flex items-start justify-between gap-4"><div className="min-w-0"><h3 className="truncate font-black text-neutral-900">{item.name}</h3><p className="mt-1 text-xs font-semibold text-neutral-500">{item.category}</p></div><p className="shrink-0 font-black text-neutral-900">${item.price_usd.toFixed(2)}</p></div><p className="mt-3 line-clamp-2 min-h-10 text-sm leading-5 text-neutral-500">{item.description || "No description yet."}</p><div className="mt-4 flex items-center justify-between border-t border-neutral-100 pt-4"><Toggle checked={item.is_available} onChange={onToggle} /><div className="flex gap-1"><button onClick={onEdit} aria-label={`Edit ${item.name}`} className="flex h-9 w-9 items-center justify-center rounded-full text-neutral-500 hover:bg-neutral-100 hover:text-neutral-900"><Pencil className="h-4 w-4" /></button><button onClick={onDelete} aria-label={`Delete ${item.name}`} className="flex h-9 w-9 items-center justify-center rounded-full text-neutral-400 hover:bg-red-50 hover:text-red-600"><Trash2 className="h-4 w-4" /></button></div></div></article>;
}

function ItemModal({ title, description, draft, setDraft, onClose, onSave, saving, saveLabel }: { title: string; description: string; draft: ItemDraft; setDraft: (draft: ItemDraft) => void; onClose: () => void; onSave: () => void; saving: boolean; saveLabel: string }) {
    return <Modal title={title} description={description} onClose={onClose} wide footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button onClick={onSave} isLoading={saving}>{saveLabel}</Button></>}><div className="grid gap-5 sm:grid-cols-2"><Field label="Name" required><Input value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} placeholder="Dish name" /></Field><Field label="Price (USD)" required><Input type="number" min="0" step="0.01" value={draft.price} onChange={(event) => setDraft({ ...draft, price: event.target.value })} placeholder="0.00" /></Field><Field label="Category" required><Input value={draft.category} onChange={(event) => setDraft({ ...draft, category: event.target.value })} placeholder="e.g. Mains" /></Field><Field label="Description"><Input value={draft.description} onChange={(event) => setDraft({ ...draft, description: event.target.value })} placeholder="Short, appetizing description" /></Field><Field label="Item images" hint="The first image becomes the main menu image." className="sm:col-span-2"><MultiImageUpload values={draft.images} onChange={(images) => setDraft({ ...draft, images })} /></Field></div></Modal>;
}
