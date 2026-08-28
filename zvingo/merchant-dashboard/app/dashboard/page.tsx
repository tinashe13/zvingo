"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { apiJson } from "@/lib/api";
import { ArrowRight, CheckCircle2, ChefHat, Clock3, DollarSign, PackageCheck, ShoppingBag, TrendingUp } from "lucide-react";

type Order = { id: string; state: string; total_amount?: number; created_at?: string; items?: { name: string; quantity: number }[] };
const terminalStates = new Set(["DELIVERED", "CANCELLED"]);

export default function DashboardPage() {
    const [orders, setOrders] = useState<Order[]>([]);
    const [userName, setUserName] = useState("Merchant");
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        async function load() {
            try {
                const me = await apiJson("/auth/me");
                setUserName(me.full_name || "Merchant");
                try { setOrders(await apiJson(`/orders/merchant/${me.id}`)); } catch { setOrders([]); }
            } catch (err) {
                console.error("Failed to load dashboard stats:", err);
            } finally { setLoading(false); }
        }
        load();
    }, []);

    const stats = useMemo(() => {
        const active = orders.filter((order) => !terminalStates.has(order.state));
        const completed = orders.filter((order) => order.state === "DELIVERED");
        const revenue = completed.reduce((sum, order) => sum + (order.total_amount || 0), 0);
        return { active: active.length, completed: completed.length, revenue };
    }, [orders]);

    if (loading) return <DashboardSkeleton />;

    return (
        <div className="mx-auto max-w-[1480px] px-6 py-8 lg:px-10 lg:py-10">
            <section className="mb-8 flex items-end justify-between gap-6 max-sm:items-start max-sm:flex-col">
                <div>
                    <p className="mb-2 text-sm font-bold text-primary">THURSDAY OVERVIEW</p>
                    <h1 className="text-4xl font-black tracking-[-0.045em] text-neutral-900 sm:text-5xl">Good evening, {firstName(userName)}.</h1>
                    <p className="mt-3 max-w-xl text-base text-neutral-500">Your restaurant is online and ready for the dinner rush.</p>
                </div>
                <Link href="/dashboard/orders" className="inline-flex h-12 items-center gap-2 rounded-xl bg-neutral-900 px-5 text-sm font-bold text-white shadow-lg shadow-black/10 hover:bg-neutral-800">View live orders <ArrowRight className="h-4 w-4" /></Link>
            </section>

            <section className="grid gap-4 md:grid-cols-3">
                <MetricCard icon={DollarSign} label="Net sales" value={`$${stats.revenue.toFixed(2)}`} detail={`${stats.completed} completed orders`} tone="lime" />
                <MetricCard icon={ShoppingBag} label="All orders" value={String(orders.length)} detail="Across your full history" tone="white" />
                <MetricCard icon={Clock3} label="In progress" value={String(stats.active)} detail={stats.active ? "Needs your attention" : "Kitchen is all clear"} tone="white" />
            </section>

            <section className="mt-6 grid gap-6 xl:grid-cols-[1.55fr_.9fr]">
                <div className="rounded-3xl border border-neutral-200/70 bg-white p-6 shadow-sm sm:p-7">
                    <div className="mb-7 flex items-center justify-between">
                        <div><h2 className="text-xl font-black tracking-[-0.025em] text-neutral-900">Today&apos;s sales</h2><p className="mt-1 text-sm text-neutral-500">Order value throughout the day</p></div>
                        <span className="inline-flex items-center gap-1.5 rounded-full bg-primary-light px-3 py-1.5 text-xs font-bold text-primary-hover"><TrendingUp className="h-3.5 w-3.5" /> Live</span>
                    </div>
                    <SalesChart orderCount={orders.length} />
                </div>

                <div className="rounded-3xl bg-neutral-900 p-6 text-white shadow-lg shadow-black/10 sm:p-7">
                    <div className="flex items-start justify-between">
                        <div><p className="text-sm font-semibold text-neutral-400">Store health</p><h2 className="mt-1 text-2xl font-black tracking-tight">Looking sharp</h2></div>
                        <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-[#d7f654] text-neutral-900"><CheckCircle2 className="h-6 w-6" /></div>
                    </div>
                    <div className="mt-8 space-y-5">
                        <HealthRow label="Menu availability" value="96%" progress="96%" />
                        <HealthRow label="Order acceptance" value="100%" progress="100%" />
                        <HealthRow label="Prep time" value="18 min" progress="72%" />
                    </div>
                    <Link href="/dashboard/settings" className="mt-8 flex h-11 items-center justify-center rounded-xl bg-white/10 text-sm font-bold hover:bg-white/15">Review store settings</Link>
                </div>
            </section>

            <section className="mt-6 rounded-3xl border border-neutral-200/70 bg-white shadow-sm">
                <div className="flex items-center justify-between border-b border-neutral-100 px-6 py-5 sm:px-7">
                    <div><h2 className="text-xl font-black tracking-[-0.025em] text-neutral-900">Recent orders</h2><p className="mt-1 text-sm text-neutral-500">The latest activity from your live order feed</p></div>
                    <Link href="/dashboard/orders" className="text-sm font-bold text-neutral-900 hover:text-primary">See all</Link>
                </div>
                {orders.length ? <div className="divide-y divide-neutral-100">{orders.slice(0, 4).map((order) => <OrderRow key={order.id} order={order} />)}</div> : (
                    <div className="flex flex-col items-center px-6 py-14 text-center">
                        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-neutral-100 text-neutral-500"><ChefHat className="h-7 w-7" /></div>
                        <h3 className="mt-4 font-black text-neutral-900">Ready for the first order</h3><p className="mt-1 text-sm text-neutral-500">New orders will appear here the moment they arrive.</p>
                    </div>
                )}
            </section>
        </div>
    );
}

function firstName(name: string) { return name.trim().split(/\s+/)[0] || "Merchant"; }

function MetricCard({ icon: Icon, label, value, detail, tone }: { icon: typeof DollarSign; label: string; value: string; detail: string; tone: "lime" | "white" }) {
    const featured = tone === "lime";
    return <div className={`rounded-3xl border p-6 shadow-sm ${featured ? "border-[#d7f654] bg-[#d7f654]" : "border-neutral-200/70 bg-white"}`}><div className="flex items-start justify-between"><div><p className={`text-sm font-semibold ${featured ? "text-neutral-700" : "text-neutral-500"}`}>{label}</p><p className="mt-3 text-4xl font-black tracking-[-0.04em] text-neutral-900">{value}</p><p className={`mt-2 text-xs font-semibold ${featured ? "text-neutral-700" : "text-neutral-400"}`}>{detail}</p></div><span className={`flex h-11 w-11 items-center justify-center rounded-2xl ${featured ? "bg-neutral-900 text-white" : "bg-neutral-100 text-neutral-700"}`}><Icon className="h-5 w-5" /></span></div></div>;
}

function SalesChart({ orderCount }: { orderCount: number }) {
    const points = orderCount ? "0,118 54,108 108,112 162,82 216,92 270,48 324,60 378,32 432,46 486,18 540,34 594,12" : "0,118 54,114 108,116 162,110 216,112 270,106 324,108 378,102 432,104 486,98 540,100 594,94";
    return <div><div className="h-52 w-full overflow-hidden rounded-2xl bg-neutral-50 p-4"><svg viewBox="0 0 594 140" className="h-full w-full" preserveAspectRatio="none" aria-label="Sales trend chart"><defs><linearGradient id="salesFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#0A8F5B" stopOpacity=".25"/><stop offset="1" stopColor="#0A8F5B" stopOpacity="0"/></linearGradient></defs>{[28,62,96,130].map((y)=><line key={y} x1="0" x2="594" y1={y} y2={y} stroke="#e2e2de" strokeDasharray="4 7"/>)}<polygon points={`${points} 594,140 0,140`} fill="url(#salesFill)"/><polyline points={points} fill="none" stroke="#0A8F5B" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round"/></svg></div><div className="mt-3 flex justify-between px-1 text-[11px] font-semibold text-neutral-400"><span>9 AM</span><span>12 PM</span><span>3 PM</span><span>6 PM</span><span>Now</span></div></div>;
}

function HealthRow({ label, value, progress }: { label: string; value: string; progress: string }) { return <div><div className="mb-2 flex justify-between text-sm"><span className="text-neutral-300">{label}</span><span className="font-bold">{value}</span></div><div className="h-1.5 overflow-hidden rounded-full bg-white/10"><div className="h-full rounded-full bg-[#d7f654]" style={{width:progress}}/></div></div>; }

function OrderRow({ order }: { order: Order }) {
    const itemCount = order.items?.reduce((count, item) => count + item.quantity, 0) || 0;
    return <div className="grid grid-cols-[auto_1fr_auto] items-center gap-4 px-6 py-4 hover:bg-neutral-50 sm:px-7"><span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-neutral-100 text-neutral-700"><PackageCheck className="h-5 w-5"/></span><div className="min-w-0"><p className="truncate text-sm font-black text-neutral-900">Order #{order.id.slice(-5).toUpperCase()}</p><p className="mt-0.5 text-xs text-neutral-500">{itemCount} items · {formatState(order.state)}</p></div><div className="text-right"><p className="text-sm font-black text-neutral-900">${(order.total_amount||0).toFixed(2)}</p><p className="mt-0.5 text-xs text-neutral-400">{formatTime(order.created_at)}</p></div></div>;
}

function formatState(state: string) { return state.toLowerCase().replaceAll("_", " "); }
function formatTime(value?: string) { return value ? new Date(value).toLocaleTimeString([], {hour:"2-digit", minute:"2-digit"}) : "Just now"; }
function DashboardSkeleton() { return <div className="mx-auto max-w-[1480px] animate-pulse px-6 py-10 lg:px-10"><div className="h-12 w-2/5 rounded-xl bg-neutral-200"/><div className="mt-4 h-5 w-1/3 rounded bg-neutral-200"/><div className="mt-10 grid gap-4 md:grid-cols-3">{[1,2,3].map((i)=><div key={i} className="h-40 rounded-3xl bg-white"/>)}</div><div className="mt-6 h-80 rounded-3xl bg-white"/></div>; }
