"use client";

import { apiJson } from "@/lib/api";
import { ChevronDown, Loader2, Store } from "lucide-react";
import { useEffect, useState } from "react";

type Merchant = { id?: string; _id?: string };
type Restaurant = { id?: string; _id?: string; is_active?: boolean };

export default function StoreStatus() {
    const [restaurantId, setRestaurantId] = useState("");
    const [isOpen, setIsOpen] = useState(false);
    const [loading, setLoading] = useState(true);
    const [updating, setUpdating] = useState(false);

    useEffect(() => {
        let active = true;

        async function loadStatus() {
            try {
                const merchant: Merchant = await apiJson("/auth/me");
                const merchantId = merchant.id || merchant._id;
                if (!merchantId) return;

                const restaurants: Restaurant[] = await apiJson(`/catalog/restaurants?merchant_id=${merchantId}`);
                const restaurant = restaurants?.[0];
                if (active && restaurant) {
                    setRestaurantId(restaurant.id || restaurant._id || "");
                    setIsOpen(Boolean(restaurant.is_active));
                }
            } catch {
                // The dashboard pages surface their own API errors; keep this
                // compact control neutral if status cannot be loaded.
            } finally {
                if (active) setLoading(false);
            }
        }

        loadStatus();
        return () => { active = false; };
    }, []);

    async function toggleStatus() {
        if (!restaurantId || updating) return;
        const next = !isOpen;
        setIsOpen(next);
        setUpdating(true);
        try {
            await apiJson(`/catalog/restaurants/${restaurantId}`, {
                method: "PUT",
                body: JSON.stringify({ is_active: next }),
            });
        } catch {
            setIsOpen(!next);
        } finally {
            setUpdating(false);
        }
    }

    if (loading) {
        return (
            <div className="flex h-10 items-center gap-2 rounded-full bg-neutral-100 px-4 text-sm font-bold text-neutral-500">
                <Loader2 className="h-4 w-4 animate-spin" /> Checking store
            </div>
        );
    }

    if (!restaurantId) {
        return (
            <div className="flex h-10 items-center gap-2 rounded-full bg-neutral-100 px-4 text-sm font-bold text-neutral-600">
                <Store className="h-4 w-4" /> Store setup
            </div>
        );
    }

    return (
        <button
            type="button"
            role="switch"
            aria-checked={isOpen}
            aria-label={`${isOpen ? "Pause" : "Open"} restaurant orders`}
            disabled={updating}
            onClick={toggleStatus}
            className={`flex h-10 items-center gap-2 rounded-full px-4 text-sm font-bold transition disabled:cursor-wait disabled:opacity-70 ${
                isOpen ? "bg-[#e9f8f1] text-[#076c45] hover:bg-[#dff3e9]" : "bg-neutral-100 text-neutral-700 hover:bg-neutral-200"
            }`}
        >
            <span className={`h-2 w-2 rounded-full ${isOpen ? "bg-[#0a8f5b] shadow-[0_0_0_4px_rgba(10,143,91,.13)]" : "bg-neutral-400"}`} />
            {updating ? "Updating…" : isOpen ? "Accepting orders" : "Orders paused"}
            <ChevronDown className="h-4 w-4" />
        </button>
    );
}
