import Sidebar from '@/components/Sidebar';
import StoreStatus from '@/components/merchant/StoreStatus';
import { Bell, ChevronDown } from 'lucide-react';

export default function DashboardLayout({
    children,
}: {
    children: React.ReactNode;
}) {
    return (
        <div className="flex h-screen bg-neutral-50 max-md:flex-col">
            <Sidebar />
            <div className="flex-1 flex flex-col overflow-hidden">
                <header className="h-20 shrink-0 bg-white border-b border-neutral-200/70 z-10 max-md:h-16">
                    <div className="h-full flex items-center justify-between px-6 lg:px-10">
                        <StoreStatus />
                        <div className="flex items-center gap-3">
                            <button aria-label="Notifications" className="relative flex h-10 w-10 items-center justify-center rounded-full bg-neutral-100 text-neutral-700 hover:bg-neutral-200">
                                <Bell className="h-[18px] w-[18px]" />
                                <span className="absolute right-2 top-2 h-2 w-2 rounded-full border-2 border-white bg-primary" />
                            </button>
                            <button className="flex items-center gap-2 rounded-full border border-neutral-200 py-1.5 pl-1.5 pr-3 text-sm font-bold text-neutral-800 hover:bg-neutral-50">
                                <span className="flex h-8 w-8 items-center justify-center rounded-full bg-neutral-900 text-xs text-white">ZP</span>
                                <span className="max-sm:hidden">My restaurant</span>
                                <ChevronDown className="h-4 w-4 text-neutral-400" />
                            </button>
                    </div>
                    </div>
                </header>
                <main className="flex-1 overflow-x-hidden overflow-y-auto bg-neutral-50">
                    {children}
                </main>
            </div>
        </div>
    );
}
