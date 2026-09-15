import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import 'driver_buttons.dart';

/// The "nothing here yet" state (§5.5).
///
/// Never ship a blank list. An empty state owes the driver three things: a
/// glyph so the screen is not a void, one sentence saying why it is empty, and
/// a button that moves them forward. All three are required by this API — you
/// cannot construct a dead end.
///
/// ```dart
/// DriverEmptyState(
///   icon: Icons.receipt_long_outlined,
///   title: 'No deliveries yet today',
///   message: 'Go online and offers will appear here as they come in.',
///   actionLabel: 'Go online',
///   onAction: _goOnline,
/// )
/// ```
class DriverEmptyState extends StatelessWidget {
  /// The illustration glyph.
  final IconData icon;

  /// One short line naming the situation.
  final String title;

  /// One sentence explaining why, in plain language.
  final String message;

  /// Label of the action that moves the driver forward.
  final String actionLabel;

  /// The forward action. Required — an empty state with no way out is a dead
  /// end (§0.6).
  final VoidCallback onAction;

  /// Optional lower-weight escape hatch, e.g. "Refresh".
  final String? secondaryLabel;

  /// Handler for [secondaryLabel].
  final VoidCallback? onSecondary;

  const DriverEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return _StateScaffold(
      icon: icon,
      iconColor: AppColors.infoOf(context),
      iconBackground: AppColors.infoSurfaceOf(context),
      title: title,
      message: message,
      primary: DriverPrimaryButton(
        label: actionLabel,
        onPressed: onAction,
        expanded: false,
      ),
      secondary: secondaryLabel == null || onSecondary == null
          ? null
          : DriverTextButton(label: secondaryLabel!, onPressed: onSecondary),
    );
  }
}

/// The "something broke" state (§5.5).
///
/// Shows what happened in plain language plus **Retry**. Never surface a raw
/// exception, a stack trace or an HTTP status code to a driver: [technical] is
/// there so a support agent can be read the detail on request, and it renders
/// small, grey and secondary.
///
/// ```dart
/// DriverErrorState(
///   title: "Couldn't load your earnings",
///   message: 'Check your connection and try again.',
///   onRetry: () => ref.refresh(earningsProvider),
/// )
/// ```
class DriverErrorState extends StatelessWidget {
  /// One short line naming what failed, from the driver's point of view.
  final String title;

  /// One sentence of plain-language guidance.
  final String message;

  /// Retry handler. Required (§5.5).
  final VoidCallback onRetry;

  /// Label of the retry button. Defaults to "Try again".
  final String retryLabel;

  /// Optional technical detail for support. Rendered as small grey caption,
  /// never as the headline.
  final String? technical;

  /// Optional secondary escape, e.g. "Contact support".
  final String? secondaryLabel;

  /// Handler for [secondaryLabel].
  final VoidCallback? onSecondary;

  const DriverErrorState({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Try again',
    this.technical,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return _StateScaffold(
      icon: Icons.cloud_off_rounded,
      iconColor: AppColors.errorOf(context),
      iconBackground: AppColors.errorSurfaceOf(context),
      title: title,
      message: message,
      footnote: technical,
      primary: DriverPrimaryButton(
        label: retryLabel,
        icon: Icons.refresh_rounded,
        onPressed: onRetry,
        expanded: false,
      ),
      secondary: secondaryLabel == null || onSecondary == null
          ? null
          : DriverTextButton(label: secondaryLabel!, onPressed: onSecondary),
    );
  }
}

/// Shared layout behind [DriverEmptyState] and [DriverErrorState] so the two
/// cannot drift apart visually.
class _StateScaffold extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String message;
  final String? footnote;
  final Widget primary;
  final Widget? secondary;

  const _StateScaffold({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.message,
    required this.primary,
    this.footnote,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.section,
        ),
        child: StaggeredEntrance(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 44, color: iconColor),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.h2.copyWith(
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              primary,
              if (secondary != null) ...[
                const SizedBox(height: AppSpacing.sm),
                secondary!,
              ],
              if (footnote != null) ...[
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  footnote!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
