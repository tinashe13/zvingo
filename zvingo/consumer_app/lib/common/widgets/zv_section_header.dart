import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';

import 'zv_tap_scale.dart';

/// The header above every content section: `h2` title, optional eyebrow and
/// subtitle, and an optional "See all" action on the right.
///
/// Sections are separated by 32 (`AppSpacing.sectionGap`); the header supplies
/// the top half of that rhythm through its default padding.
///
/// ```dart
/// ZvSectionHeader(
///   title: 'Fastest near you',
///   subtitle: 'Delivered in under 30 minutes',
///   actionLabel: 'See all',
///   onAction: () => context.push('/search?sort=fastest'),
/// )
/// ```
class ZvSectionHeader extends StatelessWidget {
  const ZvSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.actionLabel = 'See all',
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.sm,
    ),
  });

  /// Section title in `h2`.
  final String title;

  /// One-line explanation below the title.
  final String? subtitle;

  /// Small UPPERCASE eyebrow above the title.
  final String? eyebrow;

  /// Label of the trailing action. Ignored when [onAction] is null.
  final String actionLabel;

  /// Trailing action handler — normally "See all".
  final VoidCallback? onAction;

  /// Custom trailing widget, overrides the [actionLabel] action.
  final Widget? trailing;

  /// Padding around the header.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    Widget? action = trailing;
    if (action == null && onAction != null) {
      action = ZvTapScale(
        onTap: onAction,
        semanticLabel: '$actionLabel, $title',
        child: Container(
          height: AppSpacing.minTapTarget,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                actionLabel,
                style:
                    AppTextStyles.button.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textPrimary,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                  style: AppTextStyles.h2,
                  maxLines: 2,
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
          if (action != null) ...[const SizedBox(width: AppSpacing.xs), action],
        ],
      ),
    );
  }
}
