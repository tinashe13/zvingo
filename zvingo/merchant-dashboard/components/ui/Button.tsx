import * as React from "react";
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";
import { Loader2 } from "lucide-react";

export function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

export interface ButtonProps
    extends React.ButtonHTMLAttributes<HTMLButtonElement> {
    variant?: "primary" | "secondary" | "outline" | "ghost" | "danger";
    size?: "sm" | "md" | "lg" | "icon";
    isLoading?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
    ({ className, variant = "primary", size = "md", isLoading, children, ...props }, ref) => {
        return (
            <button
                ref={ref}
                className={cn(
                    // Base styles
                    "inline-flex items-center justify-center rounded-xl font-bold transition-all duration-200 ease-out focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-neutral-900 focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none active:scale-[0.98]",

                    // Variants
                    variant === "primary" &&
                    "bg-neutral-900 text-white hover:bg-neutral-800 shadow-lg shadow-black/10 active:translate-y-0",
                    variant === "secondary" &&
                    "bg-neutral-100 text-neutral-900 hover:bg-neutral-200",
                    variant === "outline" &&
                    "border border-neutral-200 bg-transparent hover:bg-neutral-50 text-neutral-700",
                    variant === "ghost" &&
                    "hover:bg-neutral-100 text-neutral-600 hover:text-neutral-900",
                    variant === "danger" &&
                    "bg-red-600 text-white hover:bg-red-700 shadow-sm",

                    // Sizes
                    size === "sm" && "h-9 px-4 text-xs",
                    size === "md" && "h-11 px-6 text-sm",
                    size === "lg" && "h-14 px-8 text-base",
                    size === "icon" && "h-10 w-10",

                    className
                )}
                disabled={isLoading || props.disabled}
                {...props}
            >
                {isLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                {children}
            </button>
        );
    }
);
Button.displayName = "Button";

export { Button };
