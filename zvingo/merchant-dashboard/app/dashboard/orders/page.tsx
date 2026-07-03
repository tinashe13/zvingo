"use client";

import { useState, useEffect, useCallback } from 'react';
import { apiJson, apiFetch, API_BASE } from '@/lib/api';

type Order = {
    id: string;
    consumer_id: string;
    items: { name: string; quantity: number; price: number }[];
    total_amount: number;
    state: string;
    created_at: string;
};

export default function OrdersPage() {
    const [orders, setOrders] = useState<Order[]>([]);
    const [loading, setLoading] = useState(true);
    const [merchantId, setMerchantId] = useState('');
    const [actionLoading, setActionLoading] = useState<string | null>(null);

    const loadOrders = useCallback(async () => {
        try {
            const me = await apiJson('/auth/me');
            setMerchantId(me.id);
            const data = await apiJson(`/orders/merchant/${me.id}`);
            setOrders(data);
        } catch (err) {
            console.error('Failed to load orders:', err);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        loadOrders();
    }, [loadOrders]);

    // SSE for real-time order notifications
    useEffect(() => {
        if (!merchantId) return;

        const eventSource = new EventSource(`${API_BASE}/notification/events/${merchantId}`);

        eventSource.onmessage = (event) => {
            const data = JSON.parse(event.data);
            if (data.event === 'new_order') {
                // Play alert sound
                try {
                    const AudioContext = window.AudioContext || (window as any).webkitAudioContext;
                    if (AudioContext) {
                        const ctx = new AudioContext();
                        const osc = ctx.createOscillator();
                        const gain = ctx.createGain();
                        osc.connect(gain);
                        gain.connect(ctx.destination);
                        osc.frequency.value = 880;
                        osc.type = 'square';
                        osc.start();
                        gain.gain.exponentialRampToValueAtTime(0.00001, ctx.currentTime + 1);
                        osc.stop(ctx.currentTime + 1);
                    }
                } catch { }
                // Reload orders
                loadOrders();
            }
        };

        eventSource.onerror = () => {
            console.error('SSE Error');
            eventSource.close();
        };

        return () => eventSource.close();
    }, [merchantId, loadOrders]);

    const updateOrderState = async (orderId: string, newState: string) => {
        setActionLoading(orderId);
        try {
            await apiFetch(`/orders/${orderId}/state`, {
                method: 'PUT',
                body: JSON.stringify({ state: newState }),
                headers: { 'Content-Type': 'application/json' },
            });
            await loadOrders();
        } catch (err) {
            console.error('Failed to update order:', err);
            alert('Failed to update order state');
        } finally {
            setActionLoading(null);
        }
    };

    const newOrders = orders.filter(o => o.state === 'CREATED');
    // In Progress now includes Accepted and Arrived at Merchant
    const inProgressOrders = orders.filter(o => ['ACCEPTED', 'ARRIVED_AT_MERCHANT', 'OFFERED'].includes(o.state) && o.state !== 'CREATED');
    // Ready for Pickup includes explicitly marked ready or waiting for pickup
    const readyOrders = orders.filter(o => ['READY_FOR_PICKUP'].includes(o.state));

    if (loading) {
        return (
            <div className="flex justify-center items-center h-full">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-emerald-500"></div>
            </div>
        );
    }

    return (
        <div className="h-full bg-slate-50 p-6 overflow-hidden flex flex-col font-sans text-slate-800">
            <header className="mb-8 flex items-center justify-between">
                <div>
                    <h2 className="text-3xl font-bold text-slate-800 tracking-tight">Orders</h2>
                    <p className="text-slate-500 text-sm mt-1">Manage your incoming orders in real-time</p>
                </div>
                {/* Status indicators or other header items could go here */}
            </header>

            <div className="flex-1 flex gap-6 overflow-x-auto pb-4">
                {/* Column: New Orders */}
                <OrderStatusColumn
                    title="New Orders"
                    count={newOrders.length}
                    colorClass="text-emerald-700 bg-emerald-50 border-emerald-200"
                    badgeColor="bg-emerald-200 text-emerald-800"
                >
                    {newOrders.map(order => (
                        <OrderCard key={order.id} order={order} variant="new">
                            <div className="mt-4 flex gap-3">
                                <ActionButton
                                    onClick={() => updateOrderState(order.id, 'ACCEPTED')}
                                    loading={actionLoading === order.id}
                                    variant="primary"
                                >
                                    Accept
                                </ActionButton>
                                <ActionButton
                                    onClick={() => updateOrderState(order.id, 'CANCELLED')}
                                    loading={actionLoading === order.id}
                                    variant="secondary"
                                >
                                    Reject
                                </ActionButton>
                            </div>
                        </OrderCard>
                    ))}
                    {newOrders.length === 0 && <EmptyState message="No new orders" />}
                </OrderStatusColumn>

                {/* Column: In Progress */}
                <OrderStatusColumn
                    title="In Kitchen"
                    count={inProgressOrders.length}
                    colorClass="text-blue-700 bg-blue-50 border-blue-200"
                    badgeColor="bg-blue-200 text-blue-800"
                >
                    {inProgressOrders.map(order => (
                        <OrderCard key={order.id} order={order} variant="default">
                            <div className="mt-4">
                                <ActionButton
                                    onClick={() => updateOrderState(order.id, 'READY_FOR_PICKUP')}
                                    loading={actionLoading === order.id}
                                    variant="primary"
                                >
                                    Mark Ready
                                </ActionButton>
                            </div>
                        </OrderCard>
                    ))}
                    {inProgressOrders.length === 0 && <EmptyState message="Kitchen is clear" />}
                </OrderStatusColumn>

                {/* Column: Ready */}
                <OrderStatusColumn
                    title="Ready for Pickup"
                    count={readyOrders.length}
                    colorClass="text-orange-700 bg-orange-50 border-orange-200"
                    badgeColor="bg-orange-200 text-orange-800"
                >
                    {readyOrders.map(order => (
                        <OrderCard key={order.id} order={order} variant="ready">
                            <div className="mt-4">
                                <ActionButton
                                    onClick={() => updateOrderState(order.id, 'PICKED_UP')}
                                    loading={actionLoading === order.id}
                                    variant="outline"
                                >
                                    Hand to Driver
                                </ActionButton>
                            </div>
                        </OrderCard>
                    ))}
                    {readyOrders.length === 0 && <EmptyState message="No orders waiting" />}
                </OrderStatusColumn>
            </div>
        </div>
    );
}

// -- Subcomponents --

function OrderStatusColumn({ title, count, children, colorClass, badgeColor }: any) {
    return (
        <div className="flex-1 min-w-[320px] flex flex-col h-full rounded-2xl bg-white border border-slate-100 shadow-sm overflow-hidden">
            <div className={`p-4 border-b border-slate-100 flex justify-between items-center ${colorClass.split(' ')[1]} bg-opacity-20`}>
                <h3 className={`font-bold text-base ${colorClass.split(' ')[0]}`}>{title}</h3>
                <span className={`px-2.5 py-0.5 rounded-full text-xs font-bold ${badgeColor}`}>
                    {count}
                </span>
            </div>
            <div className="p-4 space-y-4 overflow-y-auto flex-1 bg-slate-50/50">
                {children}
            </div>
        </div>
    );
}

function OrderCard({ order, children, variant }: { order: Order, children: React.ReactNode, variant: 'new' | 'default' | 'ready' }) {
    const isNew = variant === 'new';

    return (
        <div className={`bg-white rounded-2xl p-5 shadow-sm border transition-all duration-200 hover:shadow-md ${isNew ? 'border-emerald-100 ring-1 ring-emerald-50' : 'border-slate-100'}`}>
            <div className="flex justify-between items-start mb-3">
                <div>
                    <span className="font-bold text-slate-800 text-lg">#{order.id.slice(-4)}</span>
                    <div className="text-xs text-slate-400 font-medium mt-0.5">
                        {new Date(order.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                    </div>
                </div>
                <div className="text-right">
                    <span className="font-bold text-slate-700 block">${order.total_amount.toFixed(2)}</span>
                    <span className="text-xs text-slate-400 font-medium">{order.items.length} items</span>
                </div>
            </div>

            <div className="space-y-1 my-3">
                {order.items.map((item, idx) => (
                    <div key={idx} className="text-slate-600 text-sm flex justify-between">
                        <span className="truncate flex-1"><span className="font-semibold text-slate-800">{item.quantity}x</span> {item.name}</span>
                    </div>
                ))}
            </div>

            {children}
        </div>
    );
}

function ActionButton({ onClick, loading, children, variant }: any) {
    const baseStyle = "w-full py-2.5 rounded-full font-semibold text-sm transition-all duration-200 flex justify-center items-center disabled:opacity-70 disabled:cursor-not-allowed transform active:scale-[0.98]";

    const variants = {
        primary: "bg-emerald-500 hover:bg-emerald-600 text-white shadow-emerald-500/20 shadow-lg hover:shadow-emerald-500/30",
        secondary: "bg-slate-100 hover:bg-slate-200 text-slate-600",
        outline: "bg-white border-2 border-emerald-500 text-emerald-600 hover:bg-emerald-50",
    };

    return (
        <button
            onClick={onClick}
            disabled={loading}
            className={`${baseStyle} ${variants[variant as keyof typeof variants]}`}
        >
            {loading ? <div className="w-4 h-4 border-2 border-current border-t-transparent rounded-full animate-spin" /> : children}
        </button>
    );
}

function EmptyState({ message }: { message: string }) {
    return (
        <div className="h-full flex flex-col items-center justify-center text-slate-400 py-12">
            <svg className="w-12 h-12 mb-3 opacity-20" fill="currentColor" viewBox="0 0 24 24">
                <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V5h14v14zm-7-2h2v-2h-2v2zm0-4h2V7h-2v6z" />
            </svg>
            <p className="text-sm font-medium">{message}</p>
        </div>
    );
}
