"use client";

import * as React from "react";
import { ArrowDown, ArrowUp, ChevronsUpDown, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/cn";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { TableRowsSkeleton } from "./Skeleton";

/* -------------------------------------------------------------------------- */
/* Primitives                                                                 */
/* -------------------------------------------------------------------------- */

export interface TableProps extends React.TableHTMLAttributes<HTMLTableElement> {
  /** Accessible name for the table. Required unless `aria-label` is given. */
  caption?: string;
  /** Height for the scroll container, enabling the sticky header. */
  maxHeight?: number | string;
  containerClassName?: string;
}

/**
 * Hairline-divided, zebra-free data table. Horizontal overflow is contained in
 * the table's own scroll container so the page body never scrolls sideways.
 */
export const Table = React.forwardRef<HTMLTableElement, TableProps>(function Table(
  { className, containerClassName, caption, maxHeight, children, ...props },
  ref,
) {
  return (
    <div
      className={cn("zv-scroll-x w-full", maxHeight !== undefined && "overflow-y-auto", containerClassName)}
      style={maxHeight !== undefined ? { maxHeight } : undefined}
    >
      <table
        ref={ref}
        className={cn("w-full border-collapse text-left type-body", className)}
        {...props}
      >
        {caption && <caption className="zv-sr-only">{caption}</caption>}
        {children}
      </table>
    </div>
  );
});

export const TableHead = React.forwardRef<
  HTMLTableSectionElement,
  React.HTMLAttributes<HTMLTableSectionElement>
>(function TableHead({ className, ...props }, ref) {
  return (
    <thead
      ref={ref}
      className={cn(
        "sticky top-0 z-10 bg-surface shadow-[inset_0_-1px_0_var(--color-divider)]",
        className,
      )}
      {...props}
    />
  );
});

export const TableBody = React.forwardRef<
  HTMLTableSectionElement,
  React.HTMLAttributes<HTMLTableSectionElement>
>(function TableBody({ className, ...props }, ref) {
  return <tbody ref={ref} className={cn("[&>tr:last-child]:border-0", className)} {...props} />;
});

export interface TableRowProps extends React.HTMLAttributes<HTMLTableRowElement> {
  /** Adds hover feedback and keyboard activation for a clickable row. */
  interactive?: boolean;
  selected?: boolean;
}

export const TableRow = React.forwardRef<HTMLTableRowElement, TableRowProps>(function TableRow(
  { className, interactive, selected, onClick, onKeyDown, ...props },
  ref,
) {
  return (
    <tr
      ref={ref}
      tabIndex={interactive ? 0 : undefined}
      aria-selected={selected || undefined}
      onClick={onClick}
      onKeyDown={(event) => {
        onKeyDown?.(event);
        if (!interactive || event.defaultPrevented) return;
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          (event.currentTarget as HTMLElement).click();
        }
      }}
      className={cn(
        "border-b border-divider transition-colors",
        interactive &&
          "cursor-pointer hover:bg-neutral-50 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-action",
        selected && "bg-neutral-50",
        className,
      )}
      {...props}
    />
  );
});

export type SortDirection = "asc" | "desc";

export interface TableHeaderCellProps extends React.ThHTMLAttributes<HTMLTableCellElement> {
  /** Makes the header a sort control. */
  sortable?: boolean;
  /** Current direction when this column is the active sort, else undefined. */
  sortDirection?: SortDirection | null;
  onSort?: () => void;
  align?: "left" | "right" | "center";
  /** Keep this column visible while the table scrolls sideways. */
  sticky?: boolean;
}

export const TableHeaderCell = React.forwardRef<HTMLTableCellElement, TableHeaderCellProps>(
  function TableHeaderCell(
    { className, sortable, sortDirection, onSort, align = "left", sticky, children, ...props },
    ref,
  ) {
    const ariaSort = !sortable
      ? undefined
      : sortDirection === "asc"
        ? "ascending"
        : sortDirection === "desc"
          ? "descending"
          : "none";

    const SortIcon: LucideIcon =
      sortDirection === "asc" ? ArrowUp : sortDirection === "desc" ? ArrowDown : ChevronsUpDown;

    return (
      <th
        ref={ref}
        scope="col"
        aria-sort={ariaSort}
        className={cn(
          "whitespace-nowrap px-4 py-3 type-overline text-text-secondary",
          align === "right" && "text-right",
          align === "center" && "text-center",
          sticky && "sticky left-0 z-20 bg-surface",
          className,
        )}
        {...props}
      >
        {sortable ? (
          <button
            type="button"
            onClick={onSort}
            className={cn(
              "inline-flex items-center gap-1.5 rounded-xs type-overline text-text-secondary transition-colors hover:text-neutral-900",
              "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action",
              sortDirection && "text-neutral-900",
              align === "right" && "flex-row-reverse",
            )}
          >
            {children}
            <SortIcon className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
          </button>
        ) : (
          children
        )}
      </th>
    );
  },
);

export interface TableCellProps extends React.TdHTMLAttributes<HTMLTableCellElement> {
  align?: "left" | "right" | "center";
  /** Money, counts and times — keeps digits from jittering. */
  numeric?: boolean;
  sticky?: boolean;
}

export const TableCell = React.forwardRef<HTMLTableCellElement, TableCellProps>(function TableCell(
  { className, align = "left", numeric, sticky, ...props },
  ref,
) {
  return (
    <td
      ref={ref}
      className={cn(
        "px-4 py-3.5 align-middle type-body text-neutral-800",
        align === "right" && "text-right",
        align === "center" && "text-center",
        numeric && "tabular-figures font-semibold text-neutral-900",
        sticky && "sticky left-0 z-10 bg-surface",
        className,
      )}
      {...props}
    />
  );
});

/** Full-width message row — use for empty, error and "no results" states. */
export function TableMessageRow({
  colSpan,
  children,
}: {
  colSpan: number;
  children: React.ReactNode;
}) {
  return (
    <tr>
      <td colSpan={colSpan} className="p-0">
        {children}
      </td>
    </tr>
  );
}

/* -------------------------------------------------------------------------- */
/* Sorting helper                                                             */
/* -------------------------------------------------------------------------- */

export interface SortState<K extends string> {
  key: K | null;
  direction: SortDirection;
}

/**
 * Click-to-sort state machine: first click sorts ascending, second descending,
 * third clears back to the natural order.
 */
export function useTableSort<K extends string>(initial?: SortState<K>) {
  const [sort, setSort] = React.useState<SortState<K>>(initial ?? { key: null, direction: "asc" });

  const toggle = React.useCallback((key: K) => {
    setSort((current) => {
      if (current.key !== key) return { key, direction: "asc" };
      if (current.direction === "asc") return { key, direction: "desc" };
      return { key: null, direction: "asc" };
    });
  }, []);

  const directionFor = React.useCallback(
    (key: K): SortDirection | null => (sort.key === key ? sort.direction : null),
    [sort],
  );

  return { sort, setSort, toggle, directionFor };
}

/** Stable sort by a derived comparable value. Nullish values sort last. */
export function sortRows<T>(
  rows: T[],
  accessor: ((row: T) => string | number | null | undefined) | null,
  direction: SortDirection,
): T[] {
  if (!accessor) return rows;
  const factor = direction === "asc" ? 1 : -1;
  return [...rows].sort((a, b) => {
    const left = accessor(a);
    const right = accessor(b);
    if (left === right) return 0;
    if (left === null || left === undefined) return 1;
    if (right === null || right === undefined) return -1;
    if (typeof left === "number" && typeof right === "number") return (left - right) * factor;
    return String(left).localeCompare(String(right), "en") * factor;
  });
}

/* -------------------------------------------------------------------------- */
/* DataTable — the fast path for a list screen                                */
/* -------------------------------------------------------------------------- */

export interface DataTableColumn<T> {
  key: string;
  header: React.ReactNode;
  /** Cell renderer. */
  cell: (row: T, index: number) => React.ReactNode;
  /** Return a comparable value to make the column sortable. */
  sortBy?: (row: T) => string | number | null | undefined;
  align?: "left" | "right" | "center";
  numeric?: boolean;
  /** Hide below this breakpoint to keep narrow tablets readable. */
  hideBelow?: "sm" | "md" | "lg";
  width?: string;
  sticky?: boolean;
}

export interface DataTableProps<T> {
  columns: Array<DataTableColumn<T>>;
  rows: T[] | undefined;
  rowKey: (row: T, index: number) => string;
  /** Accessible name for the table. */
  caption: string;
  loading?: boolean;
  error?: unknown;
  onRetry?: () => void;
  /** Rendered when there are no rows and nothing failed. */
  empty?: React.ReactNode;
  onRowClick?: (row: T) => void;
  selectedKey?: string | null;
  maxHeight?: number | string;
  className?: string;
  containerClassName?: string;
  /** Rows to show while loading. Default 5. */
  skeletonRows?: number;
}

const HIDE_BELOW: Record<"sm" | "md" | "lg", string> = {
  sm: "hidden sm:table-cell",
  md: "hidden md:table-cell",
  lg: "hidden lg:table-cell",
};

/**
 * A table with sorting, a sticky header, layout-matched loading skeletons and
 * first-class empty/error states — the four things every list screen needs.
 */
export function DataTable<T>({
  columns,
  rows,
  rowKey,
  caption,
  loading,
  error,
  onRetry,
  empty,
  onRowClick,
  selectedKey,
  maxHeight,
  className,
  containerClassName,
  skeletonRows = 5,
}: DataTableProps<T>) {
  const { sort, toggle, directionFor } = useTableSort<string>();

  const sorted = React.useMemo(() => {
    if (!rows) return [];
    const column = columns.find((c) => c.key === sort.key);
    return sortRows(rows, column?.sortBy ?? null, sort.direction);
  }, [rows, columns, sort]);

  const showSkeleton = loading && !rows?.length;
  const showError = Boolean(error) && !showSkeleton;
  const showEmpty = !showSkeleton && !showError && sorted.length === 0;

  return (
    <Table caption={caption} maxHeight={maxHeight} className={className} containerClassName={containerClassName}>
      <TableHead>
        <tr>
          {columns.map((column) => (
            <TableHeaderCell
              key={column.key}
              align={column.align}
              sticky={column.sticky}
              sortable={Boolean(column.sortBy)}
              sortDirection={directionFor(column.key)}
              onSort={() => toggle(column.key)}
              style={column.width ? { width: column.width } : undefined}
              className={column.hideBelow ? HIDE_BELOW[column.hideBelow] : undefined}
            >
              {column.header}
            </TableHeaderCell>
          ))}
        </tr>
      </TableHead>

      <TableBody>
        {showSkeleton && <TableRowsSkeleton rows={skeletonRows} columns={columns.length} />}

        {showError && (
          <TableMessageRow colSpan={columns.length}>
            <ErrorState error={error} onRetry={onRetry} size="sm" />
          </TableMessageRow>
        )}

        {showEmpty && (
          <TableMessageRow colSpan={columns.length}>
            {empty ?? (
              <EmptyState
                size="sm"
                title="Nothing here yet"
                description="When there is something to show, it will appear in this list."
              />
            )}
          </TableMessageRow>
        )}

        {!showSkeleton &&
          !showError &&
          sorted.map((row, index) => {
            const key = rowKey(row, index);
            return (
              <TableRow
                key={key}
                interactive={Boolean(onRowClick)}
                selected={selectedKey === key}
                onClick={onRowClick ? () => onRowClick(row) : undefined}
              >
                {columns.map((column) => (
                  <TableCell
                    key={column.key}
                    align={column.align}
                    numeric={column.numeric}
                    sticky={column.sticky}
                    className={column.hideBelow ? HIDE_BELOW[column.hideBelow] : undefined}
                  >
                    {column.cell(row, index)}
                  </TableCell>
                ))}
              </TableRow>
            );
          })}
      </TableBody>
    </Table>
  );
}
