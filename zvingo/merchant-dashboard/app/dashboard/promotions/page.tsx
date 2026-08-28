"use client";

import { useEffect, useMemo, useState } from "react";
import { CalendarDays, Copy, Gift, Megaphone, Pencil, Plus, Tag, Trash2, Truck } from "lucide-react";
import { apiFetch, apiJson } from "@/lib/api";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";
import { EmptyState, Field, LoadingState, Modal, PageHeader, PageShell, Panel, StatusBadge, Toggle } from "@/components/merchant/Page";

interface Promotion { _id: string; promo_id: string; title: string; subtitle: string; description?: string; icon: string; promo_type: string; discount_value: number; min_order_usd: number; max_discount_usd?: number; starts_at: string; ends_at?: string; is_active: boolean; max_uses?: number; max_uses_per_user: number; current_uses: number; code?: string; created_at: string }
type PromoForm = { title: string; subtitle: string; description: string; icon: string; promo_type: string; discount_value: number; min_order_usd: number; max_discount_usd: string; starts_at: string; ends_at: string; max_uses: string; max_uses_per_user: number; code: string };

const PROMO_TYPES = [{ value: "percentage", label: "Percentage off" }, { value: "flat", label: "Flat amount off" }, { value: "free_delivery", label: "Free delivery" }, { value: "free_item", label: "Free item" }];
const ICON_OPTIONS = [{ value: "local_offer", label: "Tag" }, { value: "percent", label: "Percent" }, { value: "delivery_dining", label: "Delivery" }, { value: "card_giftcard", label: "Gift" }];
const blankForm: PromoForm = { title: "", subtitle: "", description: "", icon: "local_offer", promo_type: "percentage", discount_value: 0, min_order_usd: 0, max_discount_usd: "", starts_at: "", ends_at: "", max_uses: "", max_uses_per_user: 1, code: "" };

export default function PromotionsPage() {
    const [promos, setPromos] = useState<Promotion[]>([]);
    const [loading, setLoading] = useState(true);
    const [showForm, setShowForm] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState<PromoForm>(blankForm);
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState("");

    useEffect(() => { loadPromos(); }, []);
    async function loadPromos() { try { setPromos(await apiJson("/catalog/promotions/merchant")); } catch (err) { console.error("Failed to load promotions:", err); } finally { setLoading(false); } }
    function openCreate() { setForm({ ...blankForm }); setEditingId(null); setShowForm(true); setError(""); }
    function openEdit(promo: Promotion) { setForm({ title: promo.title, subtitle: promo.subtitle, description: promo.description || "", icon: promo.icon, promo_type: promo.promo_type, discount_value: promo.discount_value, min_order_usd: promo.min_order_usd, max_discount_usd: promo.max_discount_usd?.toString() || "", starts_at: promo.starts_at ? promo.starts_at.slice(0, 16) : "", ends_at: promo.ends_at ? promo.ends_at.slice(0, 16) : "", max_uses: promo.max_uses?.toString() || "", max_uses_per_user: promo.max_uses_per_user, code: promo.code || "" }); setEditingId(promo._id); setShowForm(true); setError(""); }

    async function handleSubmit(event: React.FormEvent) {
        event.preventDefault();
        if (!form.title.trim() || !form.subtitle.trim()) { setError("Title and subtitle are required"); return; }
        setSaving(true); setError("");
        const body = { title: form.title.trim(), subtitle: form.subtitle.trim(), description: form.description.trim() || null, icon: form.icon, promo_type: form.promo_type, discount_value: Number(form.discount_value) || 0, min_order_usd: Number(form.min_order_usd) || 0, max_discount_usd: form.max_discount_usd ? Number(form.max_discount_usd) : null, starts_at: form.starts_at ? new Date(form.starts_at).toISOString() : null, ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null, max_uses: form.max_uses ? Number(form.max_uses) : null, max_uses_per_user: Number(form.max_uses_per_user) || 1, code: form.code.trim() || null };
        try { await apiJson(editingId ? `/catalog/promotions/${editingId}` : "/catalog/promotions", { method: editingId ? "PUT" : "POST", body: JSON.stringify(body) }); setShowForm(false); setEditingId(null); await loadPromos(); }
        catch (err) { setError(err instanceof Error ? err.message : "Failed to save promotion"); }
        finally { setSaving(false); }
    }

    async function toggleActive(promo: Promotion) { try { await apiJson(`/catalog/promotions/${promo._id}/toggle`, { method: "PATCH" }); setPromos(promos.map((entry) => entry._id === promo._id ? { ...entry, is_active: !entry.is_active } : entry)); } catch (err) { console.error("Failed to toggle promotion:", err); } }
    async function deletePromo(promo: Promotion) { if (!confirm(`Delete "${promo.title}"? This cannot be undone.`)) return; try { const response = await apiFetch(`/catalog/promotions/${promo._id}`, { method: "DELETE" }); if (!response.ok) throw new Error(`Delete failed: ${response.status}`); setPromos(promos.filter((entry) => entry._id !== promo._id)); } catch (err) { console.error("Failed to delete promotion:", err); } }

    const active = promos.filter((promo) => promo.is_active).length;
    const redemptions = useMemo(() => promos.reduce((sum, promo) => sum + promo.current_uses, 0), [promos]);
    if (loading) return <LoadingState />;

    return (
        <PageShell>
            <PageHeader eyebrow="GROWTH" title="Promotions" description="Launch targeted offers that appear directly in the consumer app and track redemption in real time." actions={<Button onClick={openCreate}><Plus className="mr-2 h-4 w-4" />New promotion</Button>} />
            <div className="mb-6 grid gap-4 sm:grid-cols-3"><PromoMetric label="Total campaigns" value={String(promos.length)} icon={Megaphone} /><PromoMetric label="Running now" value={String(active)} icon={CalendarDays} /><PromoMetric label="Redemptions" value={String(redemptions)} icon={Gift} featured /></div>
            <Panel title="Campaigns" description="Pause, edit, or review every customer offer from one place.">
                {promos.length ? <div className="grid gap-5 p-5 md:grid-cols-2 xl:grid-cols-3 sm:p-6">{promos.map((promo) => <PromotionCard key={promo._id} promo={promo} onToggle={() => toggleActive(promo)} onEdit={() => openEdit(promo)} onDelete={() => deletePromo(promo)} />)}</div> : <EmptyState icon={Tag} title="Create your first campaign" description="Use a percentage, fixed discount, free delivery, or free item to bring customers back." action={<Button onClick={openCreate}><Plus className="mr-2 h-4 w-4" />Create promotion</Button>} />}
            </Panel>

            {showForm && <Modal title={editingId ? "Edit promotion" : "New promotion"} description="This offer will be published to eligible customers in the consumer app." onClose={() => setShowForm(false)} wide footer={<><Button variant="secondary" onClick={() => setShowForm(false)}>Cancel</Button><Button type="submit" form="promotion-form" isLoading={saving}>{editingId ? "Save changes" : "Publish promotion"}</Button></>}>
                <form id="promotion-form" onSubmit={handleSubmit} className="grid gap-5 sm:grid-cols-2">
                    {error && <div role="alert" className="rounded-xl bg-red-50 px-4 py-3 text-sm font-semibold text-red-700 sm:col-span-2">{error}</div>}
                    <Field label="Campaign title" required><Input value={form.title} onChange={(event) => setForm({ ...form, title: event.target.value })} placeholder="e.g. 20% off dinner" /></Field>
                    <Field label="Customer subtitle" required><Input value={form.subtitle} onChange={(event) => setForm({ ...form, subtitle: event.target.value })} placeholder="On all orders this week" /></Field>
                    <Field label="Offer type"><select className="h-12 w-full rounded-xl border border-transparent bg-neutral-100 px-4 text-sm font-semibold outline-none focus:border-neutral-900" value={form.promo_type} onChange={(event) => setForm({ ...form, promo_type: event.target.value })}>{PROMO_TYPES.map((type) => <option key={type.value} value={type.value}>{type.label}</option>)}</select></Field>
                    <Field label={form.promo_type === "percentage" ? "Discount (%)" : "Discount (USD)"}><Input type="number" min="0" step="0.01" disabled={["free_delivery", "free_item"].includes(form.promo_type)} value={form.discount_value} onChange={(event) => setForm({ ...form, discount_value: Number(event.target.value) })} /></Field>
                    <Field label="Minimum order (USD)"><Input type="number" min="0" step="0.01" value={form.min_order_usd} onChange={(event) => setForm({ ...form, min_order_usd: Number(event.target.value) })} /></Field>
                    <Field label="Maximum discount (USD)" hint="Optional cap for percentage campaigns."><Input type="number" min="0" step="0.01" value={form.max_discount_usd} onChange={(event) => setForm({ ...form, max_discount_usd: event.target.value })} /></Field>
                    <Field label="Starts"><Input type="datetime-local" value={form.starts_at} onChange={(event) => setForm({ ...form, starts_at: event.target.value })} /></Field>
                    <Field label="Ends"><Input type="datetime-local" value={form.ends_at} onChange={(event) => setForm({ ...form, ends_at: event.target.value })} /></Field>
                    <Field label="Promo code"><Input value={form.code} onChange={(event) => setForm({ ...form, code: event.target.value.toUpperCase() })} placeholder="DINNER20" /></Field>
                    <Field label="Visual icon"><select className="h-12 w-full rounded-xl border border-transparent bg-neutral-100 px-4 text-sm font-semibold outline-none focus:border-neutral-900" value={form.icon} onChange={(event) => setForm({ ...form, icon: event.target.value })}>{ICON_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></Field>
                    <Field label="Total redemption limit"><Input type="number" min="1" value={form.max_uses} onChange={(event) => setForm({ ...form, max_uses: event.target.value })} placeholder="Unlimited" /></Field>
                    <Field label="Uses per customer"><Input type="number" min="1" value={form.max_uses_per_user} onChange={(event) => setForm({ ...form, max_uses_per_user: Number(event.target.value) })} /></Field>
                    <Field label="Terms and conditions" className="sm:col-span-2"><textarea className="min-h-24 w-full rounded-xl border border-transparent bg-neutral-100 px-4 py-3 text-sm outline-none focus:border-neutral-900 focus:ring-2 focus:ring-neutral-900/10" value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })} placeholder="Optional details customers should know" /></Field>
                </form>
            </Modal>}
        </PageShell>
    );
}

function PromoMetric({ label, value, icon: Icon, featured = false }: { label: string; value: string; icon: typeof Megaphone; featured?: boolean }) { return <div className={`flex items-center justify-between rounded-2xl border p-5 shadow-sm ${featured ? "border-[#d7f654] bg-[#d7f654]" : "border-neutral-200/70 bg-white"}`}><div><p className="text-xs font-bold text-neutral-600">{label}</p><p className="mt-2 text-3xl font-black tracking-tight text-neutral-900">{value}</p></div><span className={`flex h-11 w-11 items-center justify-center rounded-2xl ${featured ? "bg-neutral-900 text-white" : "bg-neutral-100 text-neutral-700"}`}><Icon className="h-5 w-5" /></span></div>; }

function PromotionCard({ promo, onToggle, onEdit, onDelete }: { promo: Promotion; onToggle: () => void; onEdit: () => void; onDelete: () => void }) {
    const Icon = promo.promo_type === "free_delivery" ? Truck : promo.promo_type === "free_item" ? Gift : Tag;
    return <article className="overflow-hidden rounded-2xl border border-neutral-200/70 bg-white"><div className={`relative min-h-40 p-5 ${promo.promo_type === "percentage" ? "bg-[#d7f654]" : promo.promo_type === "flat" ? "bg-neutral-900 text-white" : "bg-primary-light"}`}><div className="flex items-start justify-between"><span className={`flex h-10 w-10 items-center justify-center rounded-xl ${promo.promo_type === "flat" ? "bg-white/10" : "bg-white/70"}`}><Icon className="h-5 w-5" /></span><StatusBadge active={promo.is_active} /></div><p className="mt-6 text-3xl font-black tracking-[-0.04em]">{discountDisplay(promo)}</p><p className={`mt-1 text-sm font-semibold ${promo.promo_type === "flat" ? "text-neutral-300" : "text-neutral-600"}`}>{promo.subtitle}</p></div><div className="p-5"><div className="flex items-start justify-between gap-3"><div><h3 className="font-black text-neutral-900">{promo.title}</h3><p className="mt-1 text-xs text-neutral-500">{formatDate(promo.starts_at)} – {formatDate(promo.ends_at)}</p></div>{promo.code && <button onClick={() => navigator.clipboard.writeText(promo.code || "")} className="inline-flex items-center gap-1.5 rounded-lg bg-neutral-100 px-2.5 py-1.5 text-xs font-black text-neutral-700" aria-label={`Copy code ${promo.code}`}><Copy className="h-3.5 w-3.5" />{promo.code}</button>}</div><div className="mt-4 flex items-center justify-between rounded-xl bg-neutral-50 p-3 text-xs"><span className="text-neutral-500">Redemptions</span><span className="font-black text-neutral-900">{promo.current_uses} / {promo.max_uses ?? "∞"}</span></div><div className="mt-4 flex items-center justify-between border-t border-neutral-100 pt-4"><Toggle checked={promo.is_active} onChange={onToggle} /><div className="flex gap-1"><button onClick={onEdit} aria-label={`Edit ${promo.title}`} className="flex h-9 w-9 items-center justify-center rounded-full text-neutral-500 hover:bg-neutral-100 hover:text-neutral-900"><Pencil className="h-4 w-4" /></button><button onClick={onDelete} aria-label={`Delete ${promo.title}`} className="flex h-9 w-9 items-center justify-center rounded-full text-neutral-400 hover:bg-red-50 hover:text-red-600"><Trash2 className="h-4 w-4" /></button></div></div></div></article>;
}

function discountDisplay(promo: Promotion) { if (promo.promo_type === "percentage") return `${promo.discount_value}% off`; if (promo.promo_type === "flat") return `$${promo.discount_value.toFixed(2)} off`; if (promo.promo_type === "free_delivery") return "Free delivery"; if (promo.promo_type === "free_item") return "Free item"; return String(promo.discount_value); }
function formatDate(value?: string) { return value ? new Date(value).toLocaleDateString("en-ZW", { month: "short", day: "numeric", year: "numeric" }) : "Ongoing"; }
