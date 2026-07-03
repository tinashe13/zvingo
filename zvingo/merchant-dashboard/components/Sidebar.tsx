"use client";

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Home, ShoppingBag, Utensils, Tag, Settings } from 'lucide-react';
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
        <div className="flex flex-col w-64 bg-white border-r h-full">
            <div className="flex items-center justify-center h-16 border-b border-neutral-100">
                <span className="text-xl font-bold text-primary">Zvingo Partner</span>
            </div>
            <div className="flex flex-col flex-1 overflow-y-auto">
                <nav className="flex-1 px-2 py-4 space-y-1">
                    {navigation.map((item) => {
                        const isActive = pathname === item.href;
                        return (
                            <Link
                                key={item.name}
                                href={item.href}
                                className={clsx(
                                    isActive ? 'bg-primary-light text-primary' : 'text-neutral-600 hover:bg-neutral-50 hover:text-neutral-900',
                                    'group flex items-center px-2 py-2 text-sm font-medium rounded-xl transition-colors duration-200'
                                )}
                            >
                                <item.icon
                                    className={clsx(
                                        isActive ? 'text-primary' : 'text-neutral-400 group-hover:text-neutral-500',
                                        'mr-3 flex-shrink-0 h-6 w-6'
                                    )}
                                    aria-hidden="true"
                                />
                                {item.name}
                            </Link>
                        );
                    })}
                </nav>
            </div>
        </div>
    );
}
