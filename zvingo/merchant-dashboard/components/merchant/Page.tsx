import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { X } from "lucide-react";
import { cn } from "@/components/ui/Button";

export function PageShell({ children, className }: { children: ReactNode; className?: string }) {
    return <div className={cn("mx-auto w-full max-w-[1480px] px-6 py-8 lg:px-10 lg:py-10", className)}>{children}</div>;
}

export function PageHeader({ eyebrow, title, description, actions }: { eyebrow: string; title: string; description: string; actions?: ReactNode }) {
    return (
        <header className="mb-8 flex items-end justify-between gap-6 max-sm:flex-col max-sm:items-start">
            <div>
                <p className="mb-2 text-xs font-black tracking-[0.12em] text-primary">{eyebrow}</p>
                <h1 className="text-4xl font-black tracking-[-0.045em] text-neutral-900 sm:text-5xl">{title}</h1>
                <p className="mt-3 max-w-2xl text-sm leading-6 text-neutral-500 sm:text-base">{description}</p>
            </div>
            {actions && <div className="flex shrink-0 items-center gap-3">{actions}</div>}
        </header>
    );
}

export function Panel({ title, description, action, children, className }: { title?: string; description?: string; action?: ReactNode; children: ReactNode; className?: string }) {
    return (
        <section className={cn("overflow-hidden rounded-3xl border border-neutral-200/70 bg-white shadow-sm", className)}>
            {(title || description || action) && (
                <div className="flex items-center justify-between gap-4 border-b border-neutral-100 px-6 py-5 sm:px-7">
                    <div>{title && <h2 className="text-lg font-black tracking-[-0.02em] text-neutral-900">{title}</h2>}{description && <p className="mt-1 text-sm text-neutral-500">{description}</p>}</div>
                    {action}
                </div>
            )}
            {children}
        </section>
    );
}

export function Field({ label, hint, required, children, className }: { label: string; hint?: string; required?: boolean; children: ReactNode; className?: string }) {
    return (
        <label className={cn("block", className)}>
            <span className="mb-2 block text-sm font-bold text-neutral-800">{label}{required && <span className="ml-1 text-primary">*</span>}</span>
            {children}
            {hint && <span className="mt-2 block text-xs leading-5 text-neutral-400">{hint}</span>}
        </label>
    );
}

export function Toggle({ checked, onChange, label, description }: { checked: boolean; onChange: () => void; label?: string; description?: string }) {
    return (
        <div className="flex items-center justify-between gap-4">
            {(label || description) && <div>{label && <p className="text-sm font-bold text-neutral-900">{label}</p>}{description && <p className="mt-1 text-xs text-neutral-500">{description}</p>}</div>}
            <button type="button" role="switch" aria-checked={checked} onClick={onChange} className={cn("relative h-7 w-12 shrink-0 rounded-full p-1 transition-colors", checked ? "bg-neutral-900" : "bg-neutral-200")}>
                <span className={cn("block h-5 w-5 rounded-full bg-white shadow-sm transition-transform", checked && "translate-x-5")} />
            </button>
        </div>
    );
}

export function StatusBadge({ active, activeLabel = "Active", inactiveLabel = "Paused" }: { active: boolean; activeLabel?: string; inactiveLabel?: string }) {
    return <span className={cn("inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-bold", active ? "bg-primary-light text-primary-hover" : "bg-neutral-100 text-neutral-500")}><span className={cn("h-1.5 w-1.5 rounded-full", active ? "bg-primary" : "bg-neutral-400")} />{active ? activeLabel : inactiveLabel}</span>;
}

export function EmptyState({ icon: Icon, title, description, action }: { icon: LucideIcon; title: string; description: string; action?: ReactNode }) {
    return <div className="flex flex-col items-center px-6 py-16 text-center"><span className="flex h-14 w-14 items-center justify-center rounded-2xl bg-neutral-100 text-neutral-500"><Icon className="h-7 w-7" /></span><h3 className="mt-4 font-black text-neutral-900">{title}</h3><p className="mt-1 max-w-sm text-sm leading-6 text-neutral-500">{description}</p>{action && <div className="mt-5">{action}</div>}</div>;
}

export function LoadingState() {
    return <div className="flex min-h-[420px] items-center justify-center"><div className="h-9 w-9 animate-spin rounded-full border-[3px] border-neutral-200 border-t-neutral-900" /></div>;
}

export function Modal({ title, description, onClose, children, footer, wide = false }: { title: string; description?: string; onClose: () => void; children: ReactNode; footer?: ReactNode; wide?: boolean }) {
    return (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-neutral-900/55 p-4 backdrop-blur-sm" role="dialog" aria-modal="true" aria-label={title}>
            <div className={cn("max-h-[92vh] w-full overflow-y-auto rounded-3xl bg-white shadow-2xl", wide ? "max-w-3xl" : "max-w-xl")}>
                <div className="sticky top-0 z-10 flex items-start justify-between gap-4 border-b border-neutral-100 bg-white px-6 py-5 sm:px-7">
                    <div><h2 className="text-xl font-black tracking-[-0.025em] text-neutral-900">{title}</h2>{description && <p className="mt-1 text-sm text-neutral-500">{description}</p>}</div>
                    <button type="button" onClick={onClose} aria-label="Close" className="flex h-9 w-9 items-center justify-center rounded-full bg-neutral-100 text-neutral-600 hover:bg-neutral-200"><X className="h-4 w-4" /></button>
                </div>
                <div className="p-6 sm:p-7">{children}</div>
                {footer && <div className="sticky bottom-0 flex justify-end gap-3 border-t border-neutral-100 bg-white px-6 py-4 sm:px-7">{footer}</div>}
            </div>
        </div>
    );
}
