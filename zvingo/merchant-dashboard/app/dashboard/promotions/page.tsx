"use client";

import { useEffect, useState } from "react";
import { apiJson, apiFetch } from "@/lib/api";

interface Promotion {
    _id: string;
    promo_id: string;
    title: string;
    subtitle: string;
    description?: string;
    icon: string;
    promo_type: string;
    discount_value: number;
    min_order_usd: number;
    max_discount_usd?: number;
    starts_at: string;
    ends_at?: string;
    is_active: boolean;
    max_uses?: number;
    max_uses_per_user: number;
    current_uses: number;
    code?: string;
    created_at: string;
}

const PROMO_TYPES = [
    { value: "percentage", label: "Percentage Off" },
    { value: "flat", label: "Flat Amount Off" },
    { value: "free_delivery", label: "Free Delivery" },
    { value: "free_item", label: "Free Item" },
];

const ICON_OPTIONS = [
    { value: "local_offer", label: "Tag" },
    { value: "percent", label: "Percent" },
    { value: "delivery_dining", label: "Delivery" },
    { value: "card_giftcard", label: "Gift Card" },
];

const blankForm = {
    title: "",
    subtitle: "",
    description: "",
    icon: "local_offer",
    promo_type: "percentage",
    discount_value: 0,
    min_order_usd: 0,
    max_discount_usd: "",
    starts_at: "",
    ends_at: "",
    max_uses: "",
    max_uses_per_user: 1,
    code: "",
};

export default function PromotionsPage() {
    const [promos, setPromos] = useState<Promotion[]>([]);
    const [loading, setLoading] = useState(true);
    const [showForm, setShowForm] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState(blankForm);
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState("");

    useEffect(() => {
        loadPromos();
    }, []);

    async function loadPromos() {
        try {
            const data = await apiJson("/catalog/promotions/merchant");
            setPromos(data);
        } catch (err) {
            console.error("Failed to load promotions:", err);
        } finally {
            setLoading(false);
        }
    }

    function openCreate() {
        setForm({ ...blankForm });
        setEditingId(null);
        setShowForm(true);
        setError("");
    }

    function openEdit(p: Promotion) {
        setForm({
            title: p.title,
            subtitle: p.subtitle,
            description: p.description || "",
            icon: p.icon,
            promo_type: p.promo_type,
            discount_value: p.discount_value,
            min_order_usd: p.min_order_usd,
            max_discount_usd: p.max_discount_usd?.toString() || "",
            starts_at: p.starts_at ? p.starts_at.slice(0, 16) : "",
            ends_at: p.ends_at ? p.ends_at.slice(0, 16) : "",
            max_uses: p.max_uses?.toString() || "",
            max_uses_per_user: p.max_uses_per_user,
            code: p.code || "",
        });
        setEditingId(p._id);
        setShowForm(true);
        setError("");
    }

    async function handleSubmit(e: React.FormEvent) {
        e.preventDefault();
        if (!form.title.trim() || !form.subtitle.trim()) {
            setError("Title and subtitle are required");
            return;
        }
        setSaving(true);
        setError("");

        const body: any = {
            title: form.title.trim(),
            subtitle: form.subtitle.trim(),
            description: form.description.trim() || null,
            icon: form.icon,
            promo_type: form.promo_type,
            discount_value: Number(form.discount_value) || 0,
            min_order_usd: Number(form.min_order_usd) || 0,
            max_discount_usd: form.max_discount_usd ? Number(form.max_discount_usd) : null,
            starts_at: form.starts_at ? new Date(form.starts_at).toISOString() : null,
            ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null,
            max_uses: form.max_uses ? Number(form.max_uses) : null,
            max_uses_per_user: Number(form.max_uses_per_user) || 1,
            code: form.code.trim() || null,
        };

        try {
            if (editingId) {
                await apiJson(`/catalog/promotions/${editingId}`, {
                    method: "PUT",
                    body: JSON.stringify(body),
                });
            } else {
                await apiJson("/catalog/promotions", {
                    method: "POST",
                    body: JSON.stringify(body),
                });
            }
            setShowForm(false);
            setEditingId(null);
            await loadPromos();
        } catch (err: any) {
            setError(err.message || "Failed to save promotion");
        } finally {
            setSaving(false);
        }
    }

    async function toggleActive(p: Promotion) {
        try {
            await apiJson(`/catalog/promotions/${p._id}/toggle`, {
                method: "PATCH",
            });
            await loadPromos();
        } catch (err) {
            console.error("Failed to toggle promotion:", err);
        }
    }

    async function deletePromo(p: Promotion) {
        if (!confirm(`Delete "${p.title}"? This cannot be undone.`)) return;
        try {
            const res = await apiFetch(`/catalog/promotions/${p._id}`, {
                method: "DELETE",
            });
            if (!res.ok) throw new Error(`Delete failed: ${res.status}`);
            setPromos(promos.filter((pr) => pr._id !== p._id));
        } catch (err) {
            console.error("Failed to delete promotion:", err);
        }
    }

    function formatDate(dateStr?: string) {
        if (!dateStr) return "—";
        return new Date(dateStr).toLocaleDateString("en-ZW", {
            month: "short",
            day: "numeric",
            year: "numeric",
        });
    }

    function promoTypeLabel(type: string) {
        return PROMO_TYPES.find((t) => t.value === type)?.label || type;
    }

    function discountDisplay(p: Promotion) {
        switch (p.promo_type) {
            case "percentage":
                return `${p.discount_value}% off`;
            case "flat":
                return `$${p.discount_value.toFixed(2)} off`;
            case "free_delivery":
                return "Free delivery";
            case "free_item":
                return "Free item";
            default:
                return `${p.discount_value}`;
        }
    }

    if (loading) {
        return (
            <div className="flex justify-center items-center h-64">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600"></div>
            </div>
        );
    }

    return (
        <div className="p-5">
            {/* Header */}
            <div className="flex items-center justify-between mb-6">
                <div>
                    <h2 className="text-2xl font-semibold text-gray-900">Promotions</h2>
                    <p className="text-gray-500 mt-1">
                        Create deals and offers that appear in the consumer app
                    </p>
                </div>
                <button
                    onClick={openCreate}
                    className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                >
                    <svg className="h-5 w-5 mr-2 -ml-1" fill="none" viewBox="0 0 24 24" strokeWidth="1.5" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                    </svg>
                    New Promotion
                </button>
            </div>

            {/* Create / Edit Form */}
            {showForm && (
                <div className="bg-white shadow rounded-lg p-6 mb-6">
                    <h3 className="text-lg font-medium text-gray-900 mb-4">
                        {editingId ? "Edit Promotion" : "Create Promotion"}
                    </h3>
                    {error && (
                        <div className="mb-4 bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
                            {error}
                        </div>
                    )}
                    <form onSubmit={handleSubmit} className="space-y-4">
                        {/* Row 1: Title + Subtitle */}
                        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <div>
                                <label className="block text-sm font-medium text-gray-700">
                                    Title <span className="text-red-500">*</span>
                                </label>
                                <input
                                    type="text"
                                    value={form.title}
                                    onChange={(e) => setForm({ ...form, title: e.target.value })}
                                    placeholder="e.g. 20% Off"
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                    required
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700">
                                    Subtitle <span className="text-red-500">*</span>
                                </label>
                                <input
                                    type="text"
                                    value={form.subtitle}
                                    onChange={(e) => setForm({ ...form, subtitle: e.target.value })}
                                    placeholder="e.g. On all orders this week"
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                    required
                                />
                            </div>
                        </div>

                        {/* Row 2: Type + Discount + Icon */}
                        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                            <div>
                                <label className="block text-sm font-medium text-gray-700">Promo Type</label>
                                <select
                                    value={form.promo_type}
                                    onChange={(e) => setForm({ ...form, promo_type: e.target.value })}
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                >
                                    {PROMO_TYPES.map((t) => (
                                        <option key={t.value} value={t.value}>
                                            {t.label}
                                        </option>
                                    ))}
                                </select>
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700">
                                    {form.promo_type === "percentage" ? "Discount (%)" : "Discount ($)"}
                                </label>
                                <input
                                    type="number"
                                    step="0.01"
                                    min="0"
                                    value={form.discount_value}
                                    onChange={(e) => setForm({ ...form, discount_value: Number(e.target.value) })}
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                    disabled={form.promo_type === "free_delivery" || form.promo_type === "free_item"}
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700">Icon</label>
                                <select
                                    value={form.icon}
                                    onChange={(e) => setForm({ ...form, icon: e.target.value })}
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                >
                                    {ICON_OPTIONS.map((i) => (
                                        <option key={i.value} value={i.value}>
                                            {i.label}
                                        </option>
                                    ))}
                                </select>
                            </div>
                        </div>

                        {/* Row 3: Min Order + Max Discount + Promo Code */}
                        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                            <div>
                                <label className="block text-sm font-medium text-gray-700">
                                    Min. Order ($)
                                </label>
                                <input
                                    type="number"
                                    step="0.01"
                                    min="0"
                                    value={form.min_order_usd}
                                    onChange={(e) => setForm({ ...form, min_order_usd: Number(e.target.value) })}
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700">
                                    Max Discount Cap ($)
                                </label>
                                <input
                                    type="number"
                                    step="0.01"
                                    min="0"
                                    value={form.max_discount_usd}
                                    onChange={(e) => setForm({ ...form, max_discount_usd: e.target.value })}
                                    placeholder="No cap"
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700">
                                    Promo Code (optional)
                                </label>
                                <input
                                    type="text"
                                    value={form.code}
                                    onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })}
                                    placeholder="e.g. SAVE20"
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2 uppercase"
                                />
                            </div>
                        </div>

                        {/* Row 4: Dates + Usage limits */}
                        <div className="grid grid-cols-1 gap-4 sm:grid-cols-4">
                            <div>
                                <label className="block text-sm font-medium text-gray-700">Starts At</label>
                                <input
                                    type="datetime-local"
                                    value={form.starts_at}
                                    onChange={(e) => setForm({ ...form, starts_at: e.target.value })}
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700">Ends At</label>
                                <input
                                    type="datetime-local"
                                    value={form.ends_at}
                                    onChange={(e) => setForm({ ...form, ends_at: e.target.value })}
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700">
                                    Max Total Uses
                                </label>
                                <input
                                    type="number"
                                    min="1"
                                    value={form.max_uses}
                                    onChange={(e) => setForm({ ...form, max_uses: e.target.value })}
                                    placeholder="Unlimited"
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700">
                                    Per-User Limit
                                </label>
                                <input
                                    type="number"
                                    min="1"
                                    value={form.max_uses_per_user}
                                    onChange={(e) => setForm({ ...form, max_uses_per_user: Number(e.target.value) })}
                                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                                />
                            </div>
                        </div>

                        {/* Description */}
                        <div>
                            <label className="block text-sm font-medium text-gray-700">
                                Description (optional)
                            </label>
                            <textarea
                                rows={2}
                                value={form.description}
                                onChange={(e) => setForm({ ...form, description: e.target.value })}
                                placeholder="Detailed terms or conditions..."
                                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 sm:text-sm border px-3 py-2"
                            />
                        </div>

                        {/* Actions */}
                        <div className="flex justify-end space-x-3 pt-2">
                            <button
                                type="button"
                                onClick={() => { setShowForm(false); setEditingId(null); }}
                                className="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50"
                            >
                                Cancel
                            </button>
                            <button
                                type="submit"
                                disabled={saving}
                                className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-green-600 hover:bg-green-700 disabled:opacity-50"
                            >
                                {saving ? "Saving..." : editingId ? "Update Promotion" : "Create Promotion"}
                            </button>
                        </div>
                    </form>
                </div>
            )}

            {/* Promotions List */}
            {promos.length === 0 && !showForm ? (
                <div className="bg-white shadow rounded-lg p-12 text-center">
                    <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" strokeWidth="1.5" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M9.568 3H5.25A2.25 2.25 0 003 5.25v4.318c0 .597.237 1.17.659 1.591l9.581 9.581c.699.699 1.78.872 2.607.33a18.095 18.095 0 005.223-5.223c.542-.827.369-1.908-.33-2.607L11.16 3.66A2.25 2.25 0 009.568 3z" />
                        <path strokeLinecap="round" strokeLinejoin="round" d="M6 6h.008v.008H6V6z" />
                    </svg>
                    <h3 className="mt-4 text-lg font-medium text-gray-900">No promotions yet</h3>
                    <p className="mt-2 text-gray-500">
                        Create your first promotion to attract more customers
                    </p>
                    <button
                        onClick={openCreate}
                        className="mt-4 inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-green-600 hover:bg-green-700"
                    >
                        Create Promotion
                    </button>
                </div>
            ) : (
                <div className="bg-white shadow rounded-lg overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-200">
                        <thead className="bg-gray-50">
                            <tr>
                                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Promotion
                                </th>
                                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Type
                                </th>
                                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Discount
                                </th>
                                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Period
                                </th>
                                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Usage
                                </th>
                                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Status
                                </th>
                                <th scope="col" className="relative px-6 py-3">
                                    <span className="sr-only">Actions</span>
                                </th>
                            </tr>
                        </thead>
                        <tbody className="bg-white divide-y divide-gray-200">
                            {promos.map((p) => (
                                <tr key={p._id} className="hover:bg-gray-50">
                                    <td className="px-6 py-4">
                                        <div className="text-sm font-medium text-gray-900">{p.title}</div>
                                        <div className="text-sm text-gray-500">{p.subtitle}</div>
                                        {p.code && (
                                            <span className="inline-flex items-center px-2 py-0.5 mt-1 rounded text-xs font-medium bg-gray-100 text-gray-800">
                                                Code: {p.code}
                                            </span>
                                        )}
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                                        {promoTypeLabel(p.promo_type)}
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                                        {discountDisplay(p)}
                                        {p.min_order_usd > 0 && (
                                            <div className="text-xs text-gray-400">
                                                Min. ${p.min_order_usd.toFixed(2)}
                                            </div>
                                        )}
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                                        <div>{formatDate(p.starts_at)}</div>
                                        <div className="text-xs text-gray-400">
                                            to {formatDate(p.ends_at)}
                                        </div>
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                                        {p.current_uses} / {p.max_uses ?? "Unlimited"}
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap">
                                        <button
                                            onClick={() => toggleActive(p)}
                                            className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium cursor-pointer transition-colors ${
                                                p.is_active
                                                    ? "bg-green-100 text-green-800 hover:bg-green-200"
                                                    : "bg-gray-100 text-gray-800 hover:bg-gray-200"
                                            }`}
                                        >
                                            {p.is_active ? "Active" : "Paused"}
                                        </button>
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                                        <button
                                            onClick={() => openEdit(p)}
                                            className="text-green-600 hover:text-green-900 mr-3"
                                        >
                                            Edit
                                        </button>
                                        <button
                                            onClick={() => deletePromo(p)}
                                            className="text-red-600 hover:text-red-900"
                                        >
                                            Delete
                                        </button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
}
