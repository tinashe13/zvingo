import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import 'driver_buttons.dart';

/// App bar for every screen that is not a top-level tab.
///
/// §5.4 is blunt about this: a non-top-level screen needs a back affordance in
/// the top-left *and* a title naming where you are. Swipe-back alone does not
/// count — it is invisible, and it does not exist on Android.
///
/// `showBack` defaults to "whatever go_router says is possible", and when
/// nothing is poppable it falls back to [fallbackRoute] so the driver is never
/// stranded on a screen with no way out (for example after a deep link, or
/// after the delivery flow rewrote the stack).
///
/// ```dart
/// Scaffold(
///   appBar: DriverAppBar(
///     title: 'Earnings history',
///     subtitle: 'Last 30 days',
///     actions: [DriverIconButton(icon: Icons.tune, tooltip: 'Filter', onPressed: _filter)],
///   ),
///   body: ...,
/// )
/// ```
class DriverAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Where the driver is. Always present.
  final String title;

  /// Optional second line of context, e.g. a date range or an order id.
  final String? subtitle;

  /// Trailing affordances. Keep to two at most.
  final List<Widget> actions;

  /// Forces the back button on or off. Null resolves automatically.
  final bool? showBack;

  /// Where "back" goes when there is nothing on the navigation stack to pop.
  final String fallbackRoute;

  /// Optional widget pinned under the title, e.g. a
  /// [ConnectionStatusBanner] or a step indicator.
  final PreferredSizeWidget? bottom;

  const DriverAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack,
    this.fallbackRoute = '/',
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        (subtitle == null ? 60 : 72) + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = showBack ?? context.canPop();

    return AppBar(
      toolbarHeight: subtitle == null ? 60 : 72,
      automaticallyImplyLeading: false,
      titleSpacing: canPop ? 0 : AppSpacing.lg,
      leading: canPop
          ? Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Center(
                child: DriverIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(fallbackRoute);
                    }
                  },
                ),
              ),
            )
          : null,
      leadingWidth: canPop ? 64 : 0,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.h2.copyWith(
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.textSecondary,
              ),
            ),
        ],
      ),
      actions: [
        ...actions,
        const SizedBox(width: AppSpacing.sm),
      ],
      bottom: bottom,
    );
  }
}
