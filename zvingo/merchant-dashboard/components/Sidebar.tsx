"use client";

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Home, ShoppingBag, Utensils, Tag, Settings, ArrowUpRight, Zap } from 'lucide-react';
import clsx from 'clsx';

const navigation = [
    { name: 'Dashboard', href: '/dashboard', icon: Home },
    { name: 'Orders', href: '/dashboard/orders', icon: ShoppingBag },
    { name: 'Menu', href: '/dashboard/menu', icon: Utensils },
    { name: 'Promotions', href: '/dashboard/promotions', icon: Tag },
    { name: 'Settings', href: '/dashboard/settings', icon: Settings },
];

export default function Sidebar() {
    const pathname = usePathname();

    return (
        <aside className="flex shrink-0 flex-col w-[252px] bg-[#111311] text-white h-full max-lg:w-[84px] max-md:h-auto max-md:w-full max-md:border-b max-md:border-white/10">
            <div className="flex items-center h-24 px-7 max-lg:justify-center max-lg:px-3 max-md:h-16 max-md:justify-start max-md:px-5">
                <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-[#d7f654] text-[#111311]">
                    <Zap className="h-5 w-5" fill="currentColor" />
                </div>
                <span className="ml-3 text-[19px] font-black tracking-[-0.04em] max-lg:hidden">zvingo<span className="text-[#d7f654]">partner</span></span>
            </div>
            <div className="flex flex-col flex-1 overflow-y-auto max-md:overflow-visible">
                <nav className="flex-1 px-4 py-3 space-y-1.5 max-md:flex max-md:gap-1 max-md:overflow-x-auto max-md:px-3 max-md:py-2 max-md:space-y-0 max-md:[scrollbar-width:none] max-md:[&::-webkit-scrollbar]:hidden">
                    {navigation.map((item) => {
                        const isActive = pathname === item.href;
                        return (
                            <Link
                                key={item.name}
                                href={item.href}
                                className={clsx(
                                    isActive ? 'bg-white text-neutral-900' : 'text-neutral-400 hover:bg-white/8 hover:text-white',
                                    'group flex items-center min-h-12 px-4 text-sm font-semibold rounded-xl max-lg:justify-center max-lg:px-2 max-md:min-w-max max-md:min-h-10 max-md:px-3'
                                )}
                            >
                                <item.icon
                                    className={clsx(
                                        isActive ? 'text-primary' : 'text-neutral-500 group-hover:text-white',
                                        'mr-3 flex-shrink-0 h-5 w-5 max-lg:mr-0 max-md:mr-2'
                                    )}
                                    aria-hidden="true"
                                />
                                <span className="max-lg:hidden max-md:inline">{item.name}</span>
                            </Link>
                        );
                    })}
                </nav>
                <div className="m-4 rounded-2xl bg-white/7 p-4 max-lg:hidden max-md:hidden">
                    <div className="mb-3 flex h-9 w-9 items-center justify-center rounded-xl bg-[#d7f654] text-neutral-900">
                        <ArrowUpRight className="h-5 w-5" />
                    </div>
                    <p className="text-sm font-bold">Grow your orders</p>
                    <p className="mt-1 text-xs leading-5 text-neutral-400">Create a promotion that brings regulars back.</p>
                    <Link href="/dashboard/promotions" className="mt-4 inline-flex text-xs font-bold text-[#d7f654]">Create offer</Link>
                </div>
            </div>
        </aside>
    );
}
