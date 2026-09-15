import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';

import 'zv_buttons.dart';

/// The empty state every empty list must use (§5.5: illustration/icon +
/// one-line title + one-line explanation + a primary action). "Never a dead
/// end" — the action must actually move the user forward.
///
/// ```dart
/// ZvEmptyState(
///   icon: Icons.shopping_bag_outlined,
///   title: 'Your cart is empty',
///   message: 'Add something from a restaurant near you and it shows up here.',
///   actionLabel: 'Browse restaurants',
///   onAction: () => context.go('/home'),
/// )
/// ```
class ZvEmptyState extends StatelessWidget {
  const ZvEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.lottieAsset,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.xxl,
      vertical: AppSpacing.huge,
    ),
  });

  /// One line. Name the situation, e.g. "No orders yet".
  final String title;

  /// One line. Explain why it is empty and what to do about it.
  final String message;

  /// Glyph shown in a tinted rounded panel. Ignored when [lottieAsset] is set.
  final IconData? icon;

  /// Lottie illustration, e.g. `assets/animations/empty_cart.json`.
  final String? lottieAsset;

  /// Label of the one primary action. Omit only if there is truly nothing
  /// the user can do — which almost never happens.
  final String? actionLabel;

  /// Primary action handler.
  final VoidCallback? onAction;

  /// Optional lower-emphasis second action.
  final String? secondaryActionLabel;

  /// Second action handler.
  final VoidCallback? onSecondaryAction;

  /// Padding around the block.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lottieAsset != null)
              SizedBox(
                height: 168,
                child: Lottie.asset(
                  lottieAsset!,
                  repeat: true,
                  errorBuilder: (context, _, __) =>
                      _IconPanel(icon: icon ?? Icons.inbox_rounded),
                ),
              )
            else
              _IconPanel(icon: icon ?? Icons.inbox_rounded),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: AppTextStyles.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              ZvButton.primary(
                label: actionLabel!,
                onPressed: onAction,
                fullWidth: false,
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ZvButton.tertiary(
                label: secondaryActionLabel!,
                onPressed: onSecondaryAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IconPanel extends StatelessWidget {
  const _IconPanel({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      width: 80,
      decoration: const BoxDecoration(
        color: AppColors.brandGreenSurface,
        borderRadius: AppRadius.xlAll,
      ),
      child: Icon(icon, size: 34, color: AppColors.brandGreen),
    );
  }
}

/// The error state every failed load must use (§5.5: what happened in plain
/// language, plus **Retry**).
///
/// It **never** shows a raw exception or an HTTP status. Pass the caught
/// object as [error] and the widget derives friendly copy via
/// [ZvErrorState.messageFor]; pass [message] to override.
///
/// ```dart
/// restaurants.when(
///   error: (e, _) => ZvErrorState(
///     error: e,
///     onRetry: () => ref.invalidate(restaurantsProvider),
///   ),
///   ...
/// )
/// ```
class ZvErrorState extends StatelessWidget {
  const ZvErrorState({
    super.key,
    this.error,
    this.title,
    this.message,
    required this.onRetry,
    this.retryLabel = 'Try again',
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.xxl,
      vertical: AppSpacing.xxl,
    ),
  });

  /// The caught object. Used only to choose plain-language copy — it is never
  /// rendered.
  final Object? error;

  /// Overrides the derived title.
  final String? title;

  /// Overrides the derived explanation.
  final String? message;

  /// Retry handler. Required — an error with no way out is a dead end.
  final VoidCallback onRetry;

  /// Label on the retry button.
  final String retryLabel;

  /// Optional escape hatch, e.g. "Contact support".
  final String? secondaryActionLabel;

  /// Second action handler.
  final VoidCallback? onSecondaryAction;

  /// Inline variant for an error inside a card or a rail.
  final bool compact;

  /// Padding around the block.
  final EdgeInsets padding;

  /// Maps any thrown object onto a title + explanation a customer can act on.
  /// Nothing here leaks a stack trace, a status code or a Dio message.
  static ({String title, String message}) messageFor(Object? error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return (
            title: 'That took too long',
            message:
                'The connection timed out. Check your signal and try again.',
          );
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return (
            title: 'No connection',
            message:
                "We couldn't reach Zvingo. Check your internet and try again.",
          );
        case DioExceptionType.badCertificate:
          return (
            title: 'Connection not secure',
            message:
                'We could not verify the connection. Try again on a trusted '
                    'network.',
          );
        case DioExceptionType.cancel:
          return (
            title: 'Request cancelled',
            message: 'That request stopped before it finished. Try again.',
          );
        case DioExceptionType.badResponse:
          final status = error.response?.statusCode ?? 0;
          if (status == 401 || status == 403) {
            return (
              title: 'Please sign in again',
              message: 'Your session expired. Sign in to pick up where you '
                  'left off.',
            );
          }
          if (status == 404) {
            return (
              title: 'Not found',
              message: "This isn't available any more. It may have been "
                  'removed.',
            );
          }
          if (status == 429) {
            return (
              title: 'Too many attempts',
              message: 'Give it a moment, then try again.',
            );
          }
          if (status >= 500) {
            return (
              title: 'Zvingo is having a moment',
              message: 'Something broke on our side. We are on it — try again '
                  'shortly.',
            );
          }
          return (
            title: "That didn't work",
            message: 'We could not complete that request. Try again.',
          );
      }
    }
    return (
      title: 'Something went wrong',
      message: 'We could not load this. Check your connection and try again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final derived = messageFor(error);
    final resolvedTitle = title ?? derived.title;
    final resolvedMessage = message ?? derived.message;

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.errorSurface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.error.withValues(alpha: 0.24)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: AppColors.error,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(resolvedTitle, style: AppTextStyles.bodyStrong),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(resolvedMessage, style: AppTextStyles.caption),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            ZvButton.tertiary(label: retryLabel, onPressed: onRetry),
          ],
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 80,
              width: 80,
              decoration: const BoxDecoration(
                color: AppColors.errorSurface,
                borderRadius: AppRadius.xlAll,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 34,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              resolvedTitle,
              style: AppTextStyles.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              resolvedMessage,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ZvButton.primary(
              label: retryLabel,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
              fullWidth: false,
            ),
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ZvButton.tertiary(
                label: secondaryActionLabel!,
                onPressed: onSecondaryAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A persistent, non-blocking offline banner (§5.5). Cached content stays
/// readable behind it.
///
/// ```dart
/// if (!online) const ZvOfflineBanner(),
/// ```
class ZvOfflineBanner extends StatelessWidget {
  const ZvOfflineBanner({
    super.key,
    this.message = "You're offline. Showing your last saved view.",
    this.onRetry,
  });

  /// Plain-language explanation of what still works.
  final String message;

  /// Optional retry handler.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warningSurface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  message,
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.warning),
                ),
              ),
              if (onRetry != null)
                ZvButton.tertiary(label: 'Retry', onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}
