import Sidebar from '@/components/Sidebar';

export default function DashboardLayout({
    children,
}: {
    children: React.ReactNode;
}) {
    return (
        <div className="flex h-screen bg-neutral-50">
            <Sidebar />
            <div className="flex-1 flex flex-col overflow-hidden">
                <header className="bg-white border-b border-neutral-100 shadow-sm z-10">
                    <div className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
                        <h1 className="text-3xl font-bold text-neutral-800">Dashboard</h1>
                    </div>
                </header>
                <main className="flex-1 overflow-x-hidden overflow-y-auto bg-neutral-50 p-6">
                    {children}
                </main>
            </div>
        </div>
    );
}
