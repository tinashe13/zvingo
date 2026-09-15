"use client";

import * as React from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/cn";

export interface PaginationProps {
  page: number;
  pageCount: number;
  onPageChange: (page: number) => void;
  /** Shown on the left, e.g. "Showing 21–40 of 128 orders". */
  summary?: React.ReactNode;
  className?: string;
  /** Names the nav landmark. Default "Pagination". */
  label?: string;
}

/** Build a page list with ellipses, always keeping first, last and neighbours. */
function pageItems(page: number, pageCount: number): Array<number | "gap"> {
  if (pageCount <= 7) return Array.from({ length: pageCount }, (_, i) => i + 1);
  const items: Array<number | "gap"> = [1];
  const start = Math.max(2, page - 1);
  const end = Math.min(pageCount - 1, page + 1);
  if (start > 2) items.push("gap");
  for (let i = start; i <= end; i += 1) items.push(i);
  if (end < pageCount - 1) items.push("gap");
  items.push(pageCount);
  return items;
}

/** Page navigation for long lists. Always says where you are, in words. */
export function Pagination({
  page,
  pageCount,
  onPageChange,
  summary,
  className,
  label = "Pagination",
}: PaginationProps) {
  if (pageCount <= 1 && !summary) return null;

  const go = (next: number) => {
    const clamped = Math.min(Math.max(1, next), Math.max(1, pageCount));
    if (clamped !== page) onPageChange(clamped);
  };

  const buttonBase =
    "zv-touch inline-flex h-10 min-w-10 items-center justify-center rounded-sm px-2.5 type-caption font-bold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action disabled:cursor-not-allowed disabled:text-action-disabled-fg";

  return (
    <nav
      aria-label={label}
      className={cn(
        "flex flex-wrap items-center justify-between gap-3 border-t border-divider px-4 py-3",
        className,
      )}
    >
      {summary ? (
        <p className="type-caption text-text-secondary tabular-figures">{summary}</p>
      ) : (
        <span />
      )}

      <div className="flex items-center gap-1">
        <button
          type="button"
          className={cn(buttonBase, "text-neutral-800 hover:bg-neutral-100")}
          onClick={() => go(page - 1)}
          disabled={page <= 1}
          aria-label="Previous page"
        >
          <ChevronLeft className="h-4 w-4" aria-hidden="true" />
          <span className="ml-1 max-sm:hidden">Previous</span>
        </button>

        {pageItems(page, pageCount).map((item, index) =>
          item === "gap" ? (
            <span
              key={`gap-${index}`}
              className="px-1 type-caption text-text-tertiary"
              aria-hidden="true"
            >
              …
            </span>
          ) : (
            <button
              key={item}
              type="button"
              onClick={() => go(item)}
              aria-current={item === page ? "page" : undefined}
              aria-label={`Page ${item}`}
              className={cn(
                buttonBase,
                "tabular-figures",
                item === page
                  ? "bg-action text-neutral-0"
                  : "text-neutral-800 hover:bg-neutral-100",
              )}
            >
              {item}
            </button>
          ),
        )}

        <button
          type="button"
          className={cn(buttonBase, "text-neutral-800 hover:bg-neutral-100")}
          onClick={() => go(page + 1)}
          disabled={page >= pageCount}
          aria-label="Next page"
        >
          <span className="mr-1 max-sm:hidden">Next</span>
          <ChevronRight className="h-4 w-4" aria-hidden="true" />
        </button>
      </div>
    </nav>
  );
}
