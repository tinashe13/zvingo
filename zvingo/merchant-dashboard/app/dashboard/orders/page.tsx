"use client";

import { API_BASE, apiFetch, apiJson } from "@/lib/api";
import { AlertCircle, BellOff, BellRing, Bike, Check, ChefHat, Clock3, PackageCheck, RefreshCw, Utensils, X } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";

type OrderState = "CREATED" | "OFFERED" | "ACCEPTED" | "ARRIVED_AT_MERCHANT" | "READY_FOR_PICKUP" | "PICKED_UP" | "CANCELLED" | string;
type Order = {
    id: string; consumer_id?: string; driver_id?: string | null; driver_name?: string | null;
    items: { name: string; quantity: number; price: number; special_instructions?: string | null }[];
    total_amount: number; state: OrderState; created_at: string; delivery_instructions?: string | null;
};
type Lane = "new" | "preparing" | "ready";
type Toast = { tone: "success" | "error" | "new"; message: string } | null;

const laneMeta: Record<Lane, { label: string; shortLabel: string; description: string; icon: typeof BellRing }> = {
    new: { label: "Needs attention", shortLabel: "New", description: "Accept or reject quickly", icon: BellRing },
    preparing: { label: "In the kitchen", shortLabel: "Preparing", description: "Orders being prepared", icon: ChefHat },
    ready: { label: "Ready for pickup", shortLabel: "Ready", description: "Waiting for a driver", icon: PackageCheck },
};

const normalizeState = (state: string) => state.replace("OrderState.", "");
const formatMoney = (value: number) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(value || 0);
const elapsedMinutes = (createdAt: string, now: number) => {
    const created = new Date(createdAt).getTime();
    return Number.isFinite(created) ? Math.max(0, Math.floor((now - created) / 60_000)) : 0;
};
const elapsedLabel = (minutes: number) => minutes < 1 ? "Just now" : minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)}h ${minutes % 60}m`;

export default function OrdersPage() {
    const [orders, setOrders] = useState<Order[]>([]);
    const [loading, setLoading] = useState(true);
    const [refreshing, setRefreshing] = useState(false);
    const [error, setError] = useState("");
    const [merchantId, setMerchantId] = useState("");
    const [actionLoading, setActionLoading] = useState<string | null>(null);
    const [confirmRejectId, setConfirmRejectId] = useState<string | null>(null);
    const [selectedLane, setSelectedLane] = useState<Lane>("new");
    const [soundEnabled, setSoundEnabled] = useState(true);
    const [connected, setConnected] = useState(false);
    const [toast, setToast] = useState<Toast>(null);
    const [now, setNow] = useState(Date.now());
    const merchantIdRef = useRef("");

    const loadOrders = useCallback(async (silent = false) => {
        if (silent) setRefreshing(true);
        else setLoading(true);
        try {
            let id = merchantIdRef.current;
            if (!id) {
                const me = await apiJson("/auth/me");
                id = me.id || me._id;
                if (!id) throw new Error("Merchant account could not be loaded");
                merchantIdRef.current = id;
                setMerchantId(id);
            }
            const data: Order[] = await apiJson(`/orders/merchant/${id}`);
            setOrders((data || []).map(order => ({ ...order, state: normalizeState(order.state) })));
            setError("");
        } catch (err) {
            setError(err instanceof Error ? err.message : "Orders could not be loaded");
        } finally {
            setLoading(false); setRefreshing(false);
        }
    }, []);

    useEffect(() => {
        loadOrders();
        const refreshTimer = window.setInterval(() => loadOrders(true), 30_000);
        const clockTimer = window.setInterval(() => setNow(Date.now()), 30_000);
        return () => { window.clearInterval(refreshTimer); window.clearInterval(clockTimer); };
    }, [loadOrders]);

    const playArrivalSound = useCallback(() => {
        if (!soundEnabled) return;
        try {
            const AudioContextClass = window.AudioContext || (window as Window & { webkitAudioContext?: typeof window.AudioContext }).webkitAudioContext;
            if (!AudioContextClass) return;
            const context = new AudioContextClass();
            [0, 0.16].forEach((offset, index) => {
                const oscillator = context.createOscillator(); const gain = context.createGain();
                oscillator.connect(gain); gain.connect(context.destination);
                oscillator.frequency.value = index === 0 ? 740 : 920; oscillator.type = "sine";
                gain.gain.setValueAtTime(0.12, context.currentTime + offset);
                gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + offset + 0.32);
                oscillator.start(context.currentTime + offset); oscillator.stop(context.currentTime + offset + 0.34);
            });
        } catch { /* Browsers can require a user gesture before audio starts. */ }
    }, [soundEnabled]);

    useEffect(() => {
        if (!merchantId) return;
        const source = new EventSource(`${API_BASE}/notification/events/${merchantId}`);
        source.onopen = () => setConnected(true);
        source.onmessage = event => {
            try {
                const data = JSON.parse(event.data);
                if (data.event === "new_order") {
                    playArrivalSound(); setSelectedLane("new");
                    setToast({ tone: "new", message: "A new order just arrived" });
                }
            } catch { /* Legacy messages still trigger a refresh. */ }
            loadOrders(true);
        };
        source.onerror = () => setConnected(false);
        return () => source.close();
    }, [merchantId, loadOrders, playArrivalSound]);

    useEffect(() => {
        if (!toast) return;
        const timer = window.setTimeout(() => setToast(null), 4_000);
        return () => window.clearTimeout(timer);
    }, [toast]);

    const updateOrderState = async (orderId: string, newState: OrderState) => {
        const previous = orders;
        setActionLoading(orderId); setConfirmRejectId(null);
        setOrders(current => current.map(order => order.id === orderId ? { ...order, state: newState } : order));
        try {
            const response = await apiFetch(`/orders/${orderId}/state`, { method: "PUT", body: JSON.stringify({ state: newState }) });
            if (!response.ok) throw new Error((await response.text()) || "Order update failed");
            setToast({ tone: "success", message: newState === "ACCEPTED" ? "Order accepted and moved to the kitchen" : newState === "READY_FOR_PICKUP" ? "Driver notified that the order is ready" : "Order rejected" });
            await loadOrders(true);
        } catch (err) {
            setOrders(previous);
            setToast({ tone: "error", message: err instanceof Error ? err.message : "Order update failed" });
        } finally { setActionLoading(null); }
    };

    const lanes = useMemo(() => ({
        new: orders.filter(order => ["CREATED", "OFFERED"].includes(order.state)),
        preparing: orders.filter(order => ["ACCEPTED", "ARRIVED_AT_MERCHANT"].includes(order.state)),
        ready: orders.filter(order => order.state === "READY_FOR_PICKUP"),
    }), [orders]);
    const activeCount = lanes.new.length + lanes.preparing.length + lanes.ready.length;
    const urgentCount = lanes.new.filter(order => elapsedMinutes(order.created_at, now) >= 5).length;

    if (loading) return <OrdersLoading />;

    return (
        <div className="flex min-h-full flex-col px-4 py-5 sm:px-6 sm:py-7 lg:px-10 lg:py-8">
            {toast && <ToastNotice toast={toast} onClose={() => setToast(null)} />}
            <header className="mb-6 flex flex-col gap-5 xl:flex-row xl:items-end xl:justify-between">
                <div>
                    <div className="mb-2 flex items-center gap-2">
                        <span className="text-xs font-black uppercase tracking-[0.16em] text-[#0a8f5b]">Live service</span>
                        <span className={`flex items-center gap-1.5 rounded-full px-2 py-1 text-[11px] font-bold ${connected ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-700"}`}>
                            <span className={`h-1.5 w-1.5 rounded-full ${connected ? "bg-emerald-500" : "bg-amber-500"}`} />{connected ? "Live" : "Reconnecting"}
                        </span>
                    </div>
                    <h1 className="text-3xl font-black tracking-[-0.045em] text-neutral-950 sm:text-4xl">Orders</h1>
                    <p className="mt-2 text-sm text-neutral-500">A focused view of what needs your team&apos;s attention right now.</p>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                    <div className="mr-2 hidden items-center gap-5 rounded-2xl border border-neutral-200 bg-white px-5 py-3 shadow-sm sm:flex">
                        <Metric value={activeCount} label="Active" /><div className="h-8 w-px bg-neutral-200" /><Metric value={urgentCount} label="Waiting 5+ min" urgent={urgentCount > 0} />
                    </div>
                    <button type="button" onClick={() => setSoundEnabled(value => !value)} className="flex h-11 items-center gap-2 rounded-xl border border-neutral-200 bg-white px-4 text-sm font-bold text-neutral-700 transition hover:bg-neutral-100" aria-label={`Turn order sounds ${soundEnabled ? "off" : "on"}`} aria-pressed={soundEnabled}>
                        {soundEnabled ? <BellRing className="h-4 w-4" /> : <BellOff className="h-4 w-4" />}<span className="max-sm:hidden">Sound {soundEnabled ? "on" : "off"}</span>
                    </button>
                    <button type="button" onClick={() => loadOrders(true)} disabled={refreshing} aria-label="Refresh live orders" className="flex h-11 items-center gap-2 rounded-xl bg-neutral-950 px-4 text-sm font-bold text-white transition hover:bg-neutral-800 disabled:opacity-60">
                        <RefreshCw className={`h-4 w-4 ${refreshing ? "animate-spin" : ""}`} /><span className="max-sm:hidden">Refresh</span>
                    </button>
                </div>
            </header>

            {error && <div className="mb-5 flex items-center justify-between gap-4 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"><span className="flex items-center gap-2"><AlertCircle className="h-4 w-4 shrink-0" />Live orders could not refresh. Showing the latest available view.</span><button type="button" onClick={() => loadOrders(true)} className="shrink-0 font-black underline">Try again</button></div>}

            <div className="mb-4 grid grid-cols-3 gap-2 lg:hidden" role="tablist" aria-label="Order lanes">
                {(Object.keys(laneMeta) as Lane[]).map(lane => {
                    const active = selectedLane === lane;
                    return <button key={lane} type="button" role="tab" aria-selected={active} onClick={() => setSelectedLane(lane)} className={`relative rounded-xl px-2 py-3 text-sm font-black transition ${active ? "bg-neutral-950 text-white" : "border border-neutral-200 bg-white text-neutral-600"}`}>{laneMeta[lane].shortLabel}<span className={`ml-1.5 rounded-full px-1.5 py-0.5 text-[10px] ${active ? "bg-white/20" : "bg-neutral-100"}`}>{lanes[lane].length}</span>{lane === "new" && urgentCount > 0 && <span className="absolute right-1.5 top-1.5 h-2 w-2 rounded-full bg-red-500" />}</button>;
                })}
            </div>

            <div className="grid flex-1 gap-5 lg:grid-cols-3">
                {(Object.keys(laneMeta) as Lane[]).map(lane => <OrderLane key={lane} lane={lane} orders={lanes[lane]} now={now} hiddenOnMobile={selectedLane !== lane} actionLoading={actionLoading} confirmRejectId={confirmRejectId} onConfirmReject={setConfirmRejectId} onUpdate={updateOrderState} />)}
            </div>
        </div>
    );
}

function Metric({ value, label, urgent = false }: { value: number; label: string; urgent?: boolean }) {
    return <div><p className={`text-xl font-black leading-none ${urgent ? "text-red-600" : "text-neutral-950"}`}>{value}</p><p className="mt-1 text-[11px] font-bold text-neutral-400">{label}</p></div>;
}

function OrderLane({ lane, orders, now, hiddenOnMobile, actionLoading, confirmRejectId, onConfirmReject, onUpdate }: { lane: Lane; orders: Order[]; now: number; hiddenOnMobile: boolean; actionLoading: string | null; confirmRejectId: string | null; onConfirmReject: (id: string | null) => void; onUpdate: (id: string, state: OrderState) => void }) {
    const meta = laneMeta[lane]; const Icon = meta.icon;
    return (
        <section className={`${hiddenOnMobile ? "hidden lg:flex" : "flex"} min-h-[480px] flex-col overflow-hidden rounded-[26px] border border-neutral-200/80 bg-white shadow-sm`}>
            <div className="flex items-center justify-between border-b border-neutral-100 px-5 py-4">
                <div className="flex items-center gap-3"><span className={`flex h-10 w-10 items-center justify-center rounded-xl ${lane === "new" ? "bg-[#e9f8f1] text-[#08774e]" : lane === "preparing" ? "bg-amber-50 text-amber-700" : "bg-[#effbc4] text-neutral-900"}`}><Icon className="h-5 w-5" /></span><div><h2 className="text-sm font-black text-neutral-950">{meta.label}</h2><p className="text-xs text-neutral-400">{meta.description}</p></div></div>
                <span className="flex h-8 min-w-8 items-center justify-center rounded-full bg-neutral-100 px-2 text-xs font-black text-neutral-700">{orders.length}</span>
            </div>
            <div className="flex-1 space-y-3 bg-neutral-50/70 p-3 sm:p-4">
                {orders.map(order => <OrderCard key={order.id} order={order} lane={lane} minutes={elapsedMinutes(order.created_at, now)} loading={actionLoading === order.id} confirmingReject={confirmRejectId === order.id} onConfirmReject={onConfirmReject} onUpdate={onUpdate} />)}
                {orders.length === 0 && <LaneEmpty lane={lane} />}
            </div>
        </section>
    );
}

function OrderCard({ order, lane, minutes, loading, confirmingReject, onConfirmReject, onUpdate }: { order: Order; lane: Lane; minutes: number; loading: boolean; confirmingReject: boolean; onConfirmReject: (id: string | null) => void; onUpdate: (id: string, state: OrderState) => void }) {
    const urgent = lane === "new" && minutes >= 5; const late = lane === "preparing" && minutes >= 20;
    const hasSpecialInstructions = order.items.some(item => item.special_instructions);
    return (
        <article className={`overflow-hidden rounded-2xl border bg-white shadow-sm transition hover:-translate-y-0.5 hover:shadow-md ${urgent ? "border-red-300 ring-2 ring-red-100" : "border-neutral-200/80"}`}>
            <div className="p-4 sm:p-5">
                <div className="flex items-start justify-between gap-3">
                    <div className="flex items-center gap-3"><span className="flex h-11 w-11 items-center justify-center rounded-xl bg-neutral-950 text-sm font-black text-white">#{order.id.slice(-3).toUpperCase()}</span><div><p className="text-sm font-black text-neutral-950">Order #{order.id.slice(-6).toUpperCase()}</p><p className={`mt-0.5 flex items-center gap-1 text-xs font-bold ${urgent || late ? "text-red-600" : "text-neutral-400"}`}><Clock3 className="h-3.5 w-3.5" />{elapsedLabel(minutes)} ago{urgent && " · respond now"}{late && " · running late"}</p></div></div>
                    <div className="text-right"><p className="text-base font-black text-neutral-950">{formatMoney(order.total_amount)}</p><p className="text-[11px] font-bold text-neutral-400">{order.items.reduce((sum, item) => sum + item.quantity, 0)} items</p></div>
                </div>
                <div className="my-4 border-y border-neutral-100 py-3"><ul className="space-y-2">{order.items.map((item, index) => <li key={`${item.name}-${index}`} className="flex gap-3 text-sm"><span className="flex h-6 min-w-6 items-center justify-center rounded-lg bg-neutral-100 px-1.5 text-xs font-black text-neutral-800">{item.quantity}</span><div className="min-w-0 flex-1"><span className="font-bold text-neutral-800">{item.name}</span>{item.special_instructions && <p className="mt-0.5 text-xs font-medium text-amber-700">{item.special_instructions}</p>}</div></li>)}</ul></div>
                {(hasSpecialInstructions || order.delivery_instructions) && <div className="mb-4 flex gap-2 rounded-xl bg-amber-50 px-3 py-2.5 text-xs font-semibold text-amber-900"><AlertCircle className="mt-0.5 h-4 w-4 shrink-0" /><span>{hasSpecialInstructions ? "This order has special item instructions." : order.delivery_instructions}</span></div>}

                {lane === "new" && !confirmingReject && <div className="grid grid-cols-[1fr_auto] gap-2"><OrderAction loading={loading} onClick={() => onUpdate(order.id, "ACCEPTED")}><Check className="h-4 w-4" />Accept order</OrderAction><button type="button" disabled={loading} onClick={() => onConfirmReject(order.id)} className="h-12 rounded-xl border border-neutral-200 px-4 text-sm font-black text-neutral-600 transition hover:border-red-200 hover:bg-red-50 hover:text-red-700 disabled:opacity-50" aria-label={`Reject order ${order.id.slice(-6)}`}>Reject</button></div>}
                {lane === "new" && confirmingReject && <div className="rounded-xl bg-red-50 p-3"><p className="mb-2 text-xs font-bold text-red-800">Reject this order? The customer will be notified.</p><div className="grid grid-cols-2 gap-2"><button type="button" onClick={() => onConfirmReject(null)} className="h-10 rounded-lg bg-white text-xs font-black text-neutral-700">Keep order</button><button type="button" disabled={loading} onClick={() => onUpdate(order.id, "CANCELLED")} className="h-10 rounded-lg bg-red-600 text-xs font-black text-white disabled:opacity-50">Yes, reject</button></div></div>}
                {lane === "preparing" && <OrderAction loading={loading} onClick={() => onUpdate(order.id, "READY_FOR_PICKUP")}><PackageCheck className="h-4 w-4" />Mark ready for pickup</OrderAction>}
                {lane === "ready" && <div className="flex items-center gap-3 rounded-xl bg-[#effbc4] px-3 py-3 text-neutral-900"><span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-neutral-950 text-white"><Bike className="h-4 w-4" /></span><div className="min-w-0"><p className="text-xs font-black">{order.driver_name ? `${order.driver_name} has been notified` : "Waiting for a driver"}</p><p className="mt-0.5 text-[11px] font-medium text-neutral-600">Pickup updates automatically when the driver collects it.</p></div></div>}
            </div>
        </article>
    );
}

function OrderAction({ children, loading, onClick }: { children: ReactNode; loading: boolean; onClick: () => void }) {
    return <button type="button" disabled={loading} onClick={onClick} className="flex h-12 w-full items-center justify-center gap-2 rounded-xl bg-neutral-950 px-4 text-sm font-black text-white transition hover:bg-neutral-800 active:scale-[0.99] disabled:cursor-wait disabled:opacity-60">{loading ? <RefreshCw className="h-4 w-4 animate-spin" /> : children}</button>;
}

function LaneEmpty({ lane }: { lane: Lane }) {
    const copy = { new: ["You’re caught up", "New orders will appear here automatically."], preparing: ["Kitchen is clear", "Accepted orders move here for preparation."], ready: ["Nothing waiting", "Completed orders stay here until driver pickup."] }[lane];
    return <div className="flex min-h-[280px] flex-col items-center justify-center px-5 text-center"><span className="mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-white text-neutral-400 shadow-sm"><Utensils className="h-6 w-6" /></span><p className="text-sm font-black text-neutral-800">{copy[0]}</p><p className="mt-1 max-w-[220px] text-xs leading-5 text-neutral-400">{copy[1]}</p></div>;
}

function ToastNotice({ toast, onClose }: { toast: Exclude<Toast, null>; onClose: () => void }) {
    const tone = toast.tone === "error" ? "bg-red-600" : toast.tone === "new" ? "bg-[#d7f654] text-neutral-950" : "bg-neutral-950";
    return <div role="status" className={`fixed right-4 top-20 z-50 flex max-w-[calc(100vw-2rem)] items-center gap-3 rounded-2xl px-4 py-3 text-sm font-bold text-white shadow-2xl sm:right-6 ${tone}`}>{toast.tone === "new" ? <BellRing className="h-5 w-5" /> : toast.tone === "error" ? <AlertCircle className="h-5 w-5" /> : <Check className="h-5 w-5" />}<span>{toast.message}</span><button type="button" onClick={onClose} className="ml-1 rounded-full p-1 opacity-70 hover:bg-white/20 hover:opacity-100" aria-label="Dismiss notification"><X className="h-4 w-4" /></button></div>;
}

function OrdersLoading() {
    return <div className="min-h-full px-4 py-6 sm:px-6 lg:px-10 lg:py-8"><div className="mb-8 h-20 max-w-xl animate-pulse rounded-2xl bg-neutral-200/70" /><div className="grid gap-5 lg:grid-cols-3">{[0, 1, 2].map(column => <div key={column} className="min-h-[520px] animate-pulse rounded-[26px] border border-neutral-200 bg-white p-4"><div className="mb-5 h-11 rounded-xl bg-neutral-100" /><div className="h-64 rounded-2xl bg-neutral-100" /></div>)}</div></div>;
}
