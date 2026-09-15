import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';

import 'zv_card.dart';
import 'zv_states.dart';
import 'zv_tap_scale.dart';

/// A large in-body page title with an optional eyebrow, subtitle and trailing
/// action. Use it on top-level tab screens, which have no app-bar title.
///
/// Non-top-level screens should use `ZvScreen`, which supplies both a title
/// and a back affordance (§5.4).
class AppPageTitle extends StatelessWidget {
  const AppPageTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.md,
    ),
  });

  /// The screen's name, in `h1`.
  final String title;

  /// One-line explanation under the title.
  final String? subtitle;

  /// Small UPPERCASE eyebrow above the title.
  final String? eyebrow;

  /// Trailing widget, e.g. a `ZvIconButton`.
  final Widget? trailing;

  /// Padding around the block.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: AppTextStyles.overline
                        .copyWith(color: AppColors.brandGreen),
                  ),
                  const SizedBox(height: AppSpacing.xxs + 2),
                ],
                Text(
                  title,
                  style: AppTextStyles.h1,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xxs + 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Legacy alias for [ZvCard]. **New code should use `ZvCard`.**
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
    this.margin = EdgeInsets.zero,
    this.color = AppColors.surface,
    this.onTap,
  });

  /// Card content.
  final Widget child;

  /// Inner padding.
  final EdgeInsets padding;

  /// Outer margin.
  final EdgeInsets margin;

  /// Surface colour.
  final Color color;

  /// Tap handler.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      padding: padding,
      margin: margin,
      color: color,
      onTap: onTap,
      child: child,
    );
  }
}

/// Legacy alias for [ZvEmptyState]. **New code should use `ZvEmptyState`**,
/// which also takes a Lottie illustration and a secondary action.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  /// Glyph in the tinted panel.
  final IconData icon;

  /// One-line title.
  final String title;

  /// One-line explanation.
  final String message;

  /// Primary action widget.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    if (action == null) {
      return ZvEmptyState(icon: icon, title: title, message: message);
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.huge,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 80,
              width: 80,
              decoration: const BoxDecoration(
                color: AppColors.brandGreenSurface,
                borderRadius: AppRadius.xlAll,
              ),
              child: Icon(icon, size: 34, color: AppColors.brandGreen),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: AppTextStyles.h2, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            action!,
          ],
        ),
      ),
    );
  }
}

/// A settings-style row: tinted icon tile, title, optional subtitle and a
/// chevron. Use it for account, help and payment-method lists.
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
    this.trailing,
  });

  /// Leading glyph.
  final IconData icon;

  /// Row title.
  final String title;

  /// Optional explanation under the title.
  final String? subtitle;

  /// Tap handler.
  final VoidCallback? onTap;

  /// Renders the row in the error tone, for sign-out / delete.
  final bool destructive;

  /// Replaces the chevron, e.g. with a switch.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.textPrimary;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color:
                  destructive ? AppColors.errorSurface : AppColors.surfaceMuted,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyles.h3.copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          trailing ??
              Icon(
                Icons.chevron_right_rounded,
                color: destructive ? AppColors.error : AppColors.textTertiary,
              ),
        ],
      ),
    );

    if (onTap == null) return row;
    return ZvTapScale(
      childHandlesTap: true,
      behavior: HitTestBehavior.deferToChild,
      semanticLabel: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}
