"use client";

import * as React from "react";
import { ImageOff, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/cn";

export interface SafeImageProps {
  src?: string | null;
  /** Always required — an empty alt is only correct for pure decoration. */
  alt: string;
  className?: string;
  /** Wrapper class, e.g. sizing and radius. */
  containerClassName?: string;
  /** Icon shown when there is no image or the URL fails. */
  fallbackIcon?: LucideIcon;
  /** Short line under the fallback icon. */
  fallbackLabel?: string;
  /** CSS aspect-ratio, e.g. "16/9" for restaurants or "1/1" for menu items. */
  ratio?: string;
  loading?: "lazy" | "eager";
}

/**
 * DESIGN_SYSTEM §5.2 — images show a shimmer placeholder while they load and
 * a branded fallback if they fail. A broken-image icon is never acceptable.
 *
 * Uses a plain `<img>` on purpose: merchant uploads are served from whatever
 * host `NEXT_PUBLIC_API_BASE_URL` points at, which is a runtime value, while
 * `next/image` needs its remote hosts allow-listed at build time.
 */
export function SafeImage({
  src,
  alt,
  className,
  containerClassName,
  fallbackIcon: FallbackIcon = ImageOff,
  fallbackLabel,
  ratio,
  loading = "lazy",
}: SafeImageProps) {
  const [status, setStatus] = React.useState<"loading" | "loaded" | "error">(
    src ? "loading" : "error",
  );

  React.useEffect(() => {
    setStatus(src ? "loading" : "error");
  }, [src]);

  return (
    <div
      className={cn("relative overflow-hidden bg-neutral-100", containerClassName)}
      style={ratio ? { aspectRatio: ratio } : undefined}
    >
      {status === "loading" && <span className="zv-shimmer absolute inset-0" aria-hidden="true" />}

      {status === "error" ? (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-1.5 bg-neutral-100 text-text-tertiary">
          <FallbackIcon className="h-5 w-5" aria-hidden="true" />
          {fallbackLabel && <span className="type-caption px-2 text-center">{fallbackLabel}</span>}
          <span className="zv-sr-only">{alt}</span>
        </div>
      ) : (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={src ?? undefined}
          alt={alt}
          loading={loading}
          decoding="async"
          onLoad={() => setStatus("loaded")}
          onError={() => setStatus("error")}
          className={cn(
            "h-full w-full object-cover transition-opacity",
            status === "loaded" ? "opacity-100" : "opacity-0",
            className,
          )}
        />
      )}
    </div>
  );
}
