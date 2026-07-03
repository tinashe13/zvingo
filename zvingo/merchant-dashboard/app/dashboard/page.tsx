"use client";

import { useEffect, useState } from "react";
import { apiJson } from "@/lib/api";

export default function DashboardPage() {
    const [stats, setStats] = useState({
        totalOrders: 0,
        activeOrders: 0,
        revenue: 0,
        userName: 'Merchant'
    });
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        async function load() {
            try {
                // Get user profile
                const me = await apiJson('/auth/me');

                // Try to get merchant orders 
                let orders: any[] = [];
                try {
                    orders = await apiJson(`/orders/merchant/${me.id}`);
                } catch {
                    // No orders yet, that's fine
                }

                const active = orders.filter((o: any) =>
                    !['DELIVERED', 'CANCELLED'].includes(o.state)
                );
                const revenue = orders
                    .filter((o: any) => o.state === 'DELIVERED')
                    .reduce((sum: number, o: any) => sum + (o.total_amount || 0), 0);

                setStats({
                    totalOrders: orders.length,
                    activeOrders: active.length,
                    revenue,
                    userName: me.full_name || 'Merchant',
                });
            } catch (err) {
                console.error('Failed to load dashboard stats:', err);
            } finally {
                setLoading(false);
            }
        }
        load();
    }, []);

    if (loading) {
        return (
            <div className="flex justify-center items-center h-64">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600"></div>
            </div>
        );
    }

    return (
        <div className="p-5">
            <h2 className="text-2xl font-semibold text-gray-900 mb-2">
                Welcome, {stats.userName}!
            </h2>
            <p className="text-gray-500 mb-8">Here&apos;s your restaurant overview</p>

            <div className="grid grid-cols-1 gap-5 sm:grid-cols-3">
                {/* Total Orders */}
                <div className="bg-white overflow-hidden shadow rounded-lg">
                    <div className="p-5">
                        <div className="flex items-center">
                            <div className="flex-shrink-0">
                                <div className="h-10 w-10 rounded-md bg-green-100 flex items-center justify-center">
                                    <svg className="h-6 w-6 text-green-600" fill="none" viewBox="0 0 24 24" strokeWidth="1.5" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 10.5V6a3.75 3.75 0 10-7.5 0v4.5m11.356-1.993l1.263 12c.07.665-.45 1.243-1.119 1.243H4.25a1.125 1.125 0 01-1.12-1.243l1.264-12A1.125 1.125 0 015.513 7.5h12.974c.576 0 1.059.435 1.119 1.007zM8.625 10.5a.375.375 0 11-.75 0 .375.375 0 01.75 0zm7.5 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z" />
                                    </svg>
                                </div>
                            </div>
                            <div className="ml-5 w-0 flex-1">
                                <dl>
                                    <dt className="text-sm font-medium text-gray-500 truncate">Total Orders</dt>
                                    <dd className="text-2xl font-semibold text-gray-900">{stats.totalOrders}</dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Active Orders */}
                <div className="bg-white overflow-hidden shadow rounded-lg">
                    <div className="p-5">
                        <div className="flex items-center">
                            <div className="flex-shrink-0">
                                <div className="h-10 w-10 rounded-md bg-blue-100 flex items-center justify-center">
                                    <svg className="h-6 w-6 text-blue-600" fill="none" viewBox="0 0 24 24" strokeWidth="1.5" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
                                    </svg>
                                </div>
                            </div>
                            <div className="ml-5 w-0 flex-1">
                                <dl>
                                    <dt className="text-sm font-medium text-gray-500 truncate">Active Orders</dt>
                                    <dd className="text-2xl font-semibold text-gray-900">{stats.activeOrders}</dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Revenue */}
                <div className="bg-white overflow-hidden shadow rounded-lg">
                    <div className="p-5">
                        <div className="flex items-center">
                            <div className="flex-shrink-0">
                                <div className="h-10 w-10 rounded-md bg-yellow-100 flex items-center justify-center">
                                    <svg className="h-6 w-6 text-yellow-600" fill="none" viewBox="0 0 24 24" strokeWidth="1.5" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v12m-3-2.818l.879.659c1.171.879 3.07.879 4.242 0 1.172-.879 1.172-2.303 0-3.182C13.536 12.219 12.768 12 12 12c-.725 0-1.45-.22-2.003-.659-1.106-.879-1.106-2.303 0-3.182s2.9-.879 4.006 0l.415.33M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                                    </svg>
                                </div>
                            </div>
                            <div className="ml-5 w-0 flex-1">
                                <dl>
                                    <dt className="text-sm font-medium text-gray-500 truncate">Revenue</dt>
                                    <dd className="text-2xl font-semibold text-gray-900">${stats.revenue.toFixed(2)}</dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
