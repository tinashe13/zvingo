import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';

import 'zv_buttons.dart';

/// The confirm sheet required before any destructive or irreversible action
/// (§5.4).
///
/// The copy must name the **consequence in plain language** — "Cancel order?
/// You'll be refunded \$12.50 within 3 days." Never "Are you sure?".
///
/// Returns `true` when the user confirms, `false` or `null` when they back
/// out. The sheet closes on scrim tap and shows a drag handle.
///
/// ```dart
/// final confirmed = await showZvConfirmSheet(
///   context,
///   title: 'Cancel this order?',
///   consequence: "You'll be refunded \$12.50 to EcoCash within 3 days. "
///       'The restaurant has already started cooking.',
///   confirmLabel: 'Cancel order',
///   cancelLabel: 'Keep order',
///   destructive: true,
/// );
/// if (confirmed == true) await ref.read(orderProvider.notifier).cancel();
/// ```
Future<bool?> showZvConfirmSheet(
  BuildContext context, {
  required String title,
  required String consequence,
  required String confirmLabel,
  String cancelLabel = 'Go back',
  bool destructive = true,
  IconData? icon,
  Future<void> Function()? onConfirm,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => ZvConfirmSheet(
      title: title,
      consequence: consequence,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
      onConfirm: onConfirm,
    ),
  );
}

/// The body of [showZvConfirmSheet]. Use the function unless you need to embed
/// the layout somewhere else.
class ZvConfirmSheet extends StatefulWidget {
  const ZvConfirmSheet({
    super.key,
    required this.title,
    required this.consequence,
    required this.confirmLabel,
    this.cancelLabel = 'Go back',
    this.destructive = true,
    this.icon,
    this.onConfirm,
  });

  /// A question naming the action, e.g. "Cancel this order?".
  final String title;

  /// What will happen, in plain language, including money and timing.
  final String consequence;

  /// Label of the confirming button. Repeat the verb — "Cancel order", never
  /// "Yes".
  final String confirmLabel;

  /// Label of the safe way out.
  final String cancelLabel;

  /// Renders the confirm button in the destructive variant.
  final bool destructive;

  /// Glyph in the tinted panel. Defaults by [destructive].
  final IconData? icon;

  /// Optional async work run while the confirm button shows its spinner. The
  /// sheet pops with `true` once it completes; if it throws, the sheet stays
  /// open so the caller can surface an error.
  final Future<void> Function()? onConfirm;

  @override
  State<ZvConfirmSheet> createState() => _ZvConfirmSheetState();
}

class _ZvConfirmSheetState extends State<ZvConfirmSheet> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (widget.onConfirm == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onConfirm!();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.destructive ? AppColors.error : AppColors.brandGreen;
    final toneSurface = widget.destructive
        ? AppColors.errorSurface
        : AppColors.brandGreenSurface;
    final glyph = widget.icon ??
        (widget.destructive
            ? Icons.warning_amber_rounded
            : Icons.help_outline_rounded);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: toneSurface,
                borderRadius: AppRadius.lgAll,
              ),
              child: Icon(glyph, size: 26, color: tone),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.title,
            style: AppTextStyles.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.consequence,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (widget.destructive)
            ZvButton.destructive(
              label: widget.confirmLabel,
              loading: _busy,
              onPressed: _confirm,
            )
          else
            ZvButton.primary(
              label: widget.confirmLabel,
              loading: _busy,
              onPressed: _confirm,
            ),
          const SizedBox(height: AppSpacing.xs),
          ZvButton.secondary(
            label: widget.cancelLabel,
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

/// A bottom sheet scaffold for the app's other sheets: drag handle (supplied
/// by the theme), a title row with a close affordance, and a scrollable body
/// that respects the keyboard inset.
///
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => ZvSheet(
///     title: 'Delivery address',
///     child: AddressPicker(...),
///   ),
/// );
/// ```
class ZvSheet extends StatelessWidget {
  const ZvSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.showClose = true,
  });

  /// Names what the sheet is for.
  final String title;

  /// Sheet body.
  final Widget child;

  /// Optional one-line explanation under the title.
  final String? subtitle;

  /// Pinned footer, normally the sheet's one primary action.
  final Widget? footer;

  /// Show the top-right close button. Scrim tap always closes too.
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xxs,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AppTextStyles.h2),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: AppTextStyles.caption),
                      ],
                    ],
                  ),
                ),
                if (showClose)
                  ZvIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
              ],
            ),
          ),
          Flexible(child: child),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: footer!,
            ),
        ],
      ),
    );
  }
}
