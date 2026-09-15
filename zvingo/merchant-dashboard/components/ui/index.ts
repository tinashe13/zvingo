/**
 * Zvingo merchant dashboard component library.
 *
 * One import site for every UI primitive:
 *   import { Button, Card, DataTable, useToast } from "@/components/ui";
 *
 * Everything here conforms to docs/DESIGN_SYSTEM.md. If a screen needs a
 * visual that is not in this barrel, add it here rather than inlining it.
 */

export { cn } from "@/lib/cn";

export { Button, IconButton, buttonClasses } from "./Button";
export type { ButtonProps, ButtonSize, ButtonVariant, IconButtonProps } from "./Button";

export { Spinner } from "./Spinner";
export type { SpinnerProps } from "./Spinner";

export {
  Card,
  CardBody,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardMedia,
  CardTitle,
} from "./Card";
export type { CardProps, CardMediaProps } from "./Card";

export { FieldShell, controlClasses } from "./Field";
export type { FieldShellProps, FieldSize } from "./Field";

export { Input } from "./Input";
export type { InputProps } from "./Input";

export { Textarea } from "./Textarea";
export type { TextareaProps } from "./Textarea";

export { Select } from "./Select";
export type { SelectProps, SelectOption } from "./Select";

export { Checkbox } from "./Checkbox";
export type { CheckboxProps } from "./Checkbox";

export { Switch } from "./Switch";
export type { SwitchProps } from "./Switch";

export { RadioGroup } from "./RadioGroup";
export type { RadioGroupProps, RadioOption } from "./RadioGroup";

export {
  DataTable,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeaderCell,
  TableMessageRow,
  TableRow,
  sortRows,
  useTableSort,
} from "./Table";
export type {
  DataTableColumn,
  DataTableProps,
  SortDirection,
  SortState,
  TableCellProps,
  TableHeaderCellProps,
  TableProps,
  TableRowProps,
} from "./Table";

export { Dialog, Modal } from "./Modal";
export type { ModalProps, ModalSize } from "./Modal";

export { ConfirmDialog, useConfirm } from "./ConfirmDialog";
export type { ConfirmDialogProps, UseConfirmResult } from "./ConfirmDialog";

export { Drawer, Sheet } from "./Sheet";
export type { SheetProps, SheetSide } from "./Sheet";

export { TabPanel, Tabs } from "./Tabs";
export type { TabItem, TabPanelProps, TabsProps } from "./Tabs";

export { Badge, OrderStatusPill, StatusPill, orderStatePresentation } from "./Badge";
export type {
  BadgeProps,
  OrderStatePresentation,
  OrderStatusPillProps,
  StatusPillProps,
  Tone,
} from "./Badge";

export { Tooltip } from "./Tooltip";
export type { TooltipPlacement, TooltipProps } from "./Tooltip";

export { DropdownMenu } from "./DropdownMenu";
export type { DropdownMenuItem, DropdownMenuProps } from "./DropdownMenu";

export { Pagination } from "./Pagination";
export type { PaginationProps } from "./Pagination";

export { ToastProvider, useToast, useOptionalToast } from "./Toast";
export type { ToastApi, ToastOptions, ToastAction, ToastTone, ToastProviderProps } from "./Toast";

export {
  MenuRowSkeleton,
  OrderCardSkeleton,
  Skeleton,
  SkeletonRegion,
  SkeletonText,
  StatCardSkeleton,
  TableRowsSkeleton,
} from "./Skeleton";
export type { SkeletonProps } from "./Skeleton";

export { EmptyState } from "./EmptyState";
export type { EmptyStateProps } from "./EmptyState";

export { ErrorState, InlineError } from "./ErrorState";
export type { ErrorStateProps } from "./ErrorState";

export { StatCard } from "./StatCard";
export type { Sparkline, StatCardProps, StatFormat } from "./StatCard";

export { NewOrderAlert, useOrderAlertSound } from "./NewOrderAlert";
export type { NewOrderAlertProps, OrderAlertSound } from "./NewOrderAlert";
