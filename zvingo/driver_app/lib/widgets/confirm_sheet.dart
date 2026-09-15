import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import 'driver_buttons.dart';

/// Confirmation sheet for destructive or irreversible actions (§5.4).
///
/// The rule the design system sets is specific: the copy must name the
/// *consequence* in plain language — "Cancel this delivery? You'll lose the
/// $4.25 payout and it may affect your acceptance rate." — never a bare
/// "Are you sure?".
///
/// The API enforces that by requiring both a [title] and a [consequence]. Call
/// [ConfirmSheet.show] and await the `bool`.
///
/// ```dart
/// final confirmed = await ConfirmSheet.show(
///   context,
///   title: 'Go offline?',
///   consequence: "You'll stop receiving offers until you go back online.",
///   confirmLabel: 'Go offline',
/// );
/// if (confirmed) ref.read(homeProvider.notifier).goOffline();
/// ```
class ConfirmSheet extends StatelessWidget {
  /// The question, phrased as the action ("Cancel this delivery?").
  final String title;

  /// What happens if the driver confirms. Concrete, with the real numbers in
  /// it wherever possible.
  final String consequence;

  /// Label of the confirming action.
  final String confirmLabel;

  /// Label of the way out. Defaults to "Never mind".
  final String cancelLabel;

  /// Renders the confirm button in error red. On by default because this
  /// sheet exists for destructive actions.
  final bool destructive;

  /// Optional glyph above the title.
  final IconData icon;

  const ConfirmSheet({
    super.key,
    required this.title,
    required this.consequence,
    required this.confirmLabel,
    this.cancelLabel = 'Never mind',
    this.destructive = true,
    this.icon = Icons.warning_amber_rounded,
  });

  /// Presents the sheet and resolves to true when the driver confirms.
  ///
  /// Dismissing by scrim tap, drag or back resolves to false, so callers can
  /// `await` this directly in an `if`.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String consequence,
    required String confirmLabel,
    String cancelLabel = 'Never mind',
    bool destructive = true,
    IconData icon = Icons.warning_amber_rounded,
  }) async {
    HapticFeedback.mediumImpact();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // Scrim tap closes (§5.4).
      isDismissible: true,
      enableDrag: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: AppSpacing.brSheetTop,
      ),
      builder: (context) => ConfirmSheet(
        title: title,
        consequence: consequence,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        icon: icon,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = destructive
        ? AppColors.errorOf(context)
        : AppColors.warningOf(context);
    final toneSurface = destructive
        ? AppColors.errorSurfaceOf(context)
        : AppColors.warningSurfaceOf(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: toneSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: tone),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.h2.copyWith(
                color:
                    isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              consequence,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            if (destructive)
              DriverDestructiveButton(
                label: confirmLabel,
                onPressed: () => Navigator.of(context).pop(true),
              )
            else
              DriverPrimaryButton(
                label: confirmLabel,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            const SizedBox(height: AppSpacing.md),
            DriverSecondaryButton(
              label: cancelLabel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

/// A snackbar with the design-system's shape, plus an optional **Undo**.
///
/// §5.5 asks for a snackbar confirmation with Undo on every reversible
/// mutation. This wraps the boilerplate so feature code is one line.
///
/// ```dart
/// DriverSnack.show(context, 'Offer declined', onUndo: _restoreOffer);
/// ```
class DriverSnack {
  DriverSnack._();

  /// Shows a confirmation snackbar. Pass [onUndo] when the action is
  /// reversible; the snackbar then stays up for 6 seconds instead of 3.
  static void show(
    BuildContext context,
    String message, {
    VoidCallback? onUndo,
    String undoLabel = 'Undo',
    IconData? icon,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: AppColors.accent),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        duration: Duration(seconds: onUndo == null ? 3 : 6),
        action: onUndo == null
            ? null
            : SnackBarAction(
                label: undoLabel,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onUndo();
                },
              ),
      ),
    );
  }

  /// Shows an error snackbar with plain-language copy and an optional retry.
  static void error(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.error,
        content: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: AppColors.textOnDark,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textOnDark),
              ),
            ),
          ],
        ),
        duration: AppMotion.deliberate * 8,
        action: onRetry == null
            ? null
            : SnackBarAction(
                label: 'Retry',
                textColor: AppColors.textOnDark,
                onPressed: onRetry,
              ),
      ),
    );
  }
}
