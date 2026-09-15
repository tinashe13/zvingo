import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_motion.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';

import 'zv_animated_count.dart';
import 'zv_tap_scale.dart';

/// The persistent active-cart bar (§5.4: "an active cart shows a sticky bottom
/// bar on every browse screen").
///
/// It is presentational — the feature agent owns the cart provider and passes
/// the numbers in. It animates in and out when [visible] flips, counts the
/// total with tabular figures, and always states which restaurant the cart
/// belongs to so a user with two carts is never confused.
///
/// The shell renders this above the dock when
/// `MainShell.cartBar` is supplied; use it directly only on screens outside
/// the shell (menu, restaurant detail).
///
/// ```dart
/// ZvCartBar(
///   visible: cart.isNotEmpty,
///   itemCount: cart.itemCount,
///   total: cart.total,
///   currency: cart.currencySymbol,
///   restaurantName: cart.restaurantName,
///   onTap: () => context.push('/cart'),
/// )
/// ```
class ZvCartBar extends StatelessWidget {
  const ZvCartBar({
    super.key,
    required this.itemCount,
    required this.total,
    required this.currency,
    required this.onTap,
    this.restaurantName,
    this.visible = true,
    this.label = 'View cart',
    this.margin = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  });

  /// Number of items in the cart.
  final int itemCount;

  /// Cart total in [currency].
  final double total;

  /// Currency symbol or code — USD, ZIG and ZAR all circulate, so money is
  /// never rendered without one.
  final String currency;

  /// Opens the cart.
  final VoidCallback onTap;

  /// Which restaurant this cart belongs to.
  final String? restaurantName;

  /// Animates the bar in and out.
  final bool visible;

  /// Call-to-action text on the right.
  final String label;

  /// Margin around the bar.
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return _SlideUpReveal(
      visible: visible && itemCount > 0,
      child: Padding(
        padding: margin,
        child: ZvTapScale(
          onTap: onTap,
          semanticLabel:
              '$label, $itemCount items, total $currency${total.toStringAsFixed(2)}',
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.actionDefault,
              borderRadius: AppRadius.mdAll,
              boxShadow: AppShadows.md,
            ),
            child: Row(
              children: [
                Container(
                  height: 26,
                  constraints: const BoxConstraints(minWidth: 26),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.brandLime,
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    '$itemCount',
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: AppColors.textPrimary,
                      fontFeatures: AppTextStyles.tabularFigures,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.button
                            .copyWith(color: AppColors.textOnDark),
                      ),
                      if (restaurantName != null &&
                          restaurantName!.trim().isNotEmpty)
                        Text(
                          restaurantName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.neutral300),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                ZvAnimatedCount.money(
                  value: total,
                  currency: currency,
                  style:
                      AppTextStyles.money.copyWith(color: AppColors.textOnDark),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textOnDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The persistent in-progress-order banner (§5.4: "an in-progress order shows
/// a sticky top banner with live ETA that taps into tracking").
///
/// Presentational: the feature agent owns the order stream and passes the
/// state in. The ETA counts rather than hard-swapping (§4.3) and the progress
/// line fills as the order advances.
///
/// ```dart
/// ZvOrderBanner(
///   visible: order != null,
///   statusLabel: 'Your order is on the way',
///   etaMinutes: order?.etaMinutes,
///   progress: 0.72,
///   onTap: () => context.push('/order/${order!.id}'),
/// )
/// ```
class ZvOrderBanner extends StatelessWidget {
  const ZvOrderBanner({
    super.key,
    required this.statusLabel,
    required this.onTap,
    this.etaMinutes,
    this.etaText,
    this.progress,
    this.visible = true,
    this.icon = Icons.delivery_dining_rounded,
    this.tone = AppColors.actionDefault,
    this.margin = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.md,
      0,
    ),
  });

  /// Plain-language state, e.g. "Your order is on the way".
  final String statusLabel;

  /// Opens the tracking screen.
  final VoidCallback onTap;

  /// Live ETA in minutes. Animates when it changes.
  final int? etaMinutes;

  /// Free-text ETA, used when [etaMinutes] is null, e.g. "25–35 min".
  final String? etaText;

  /// Delivery progress 0..1. Null hides the progress line.
  final double? progress;

  /// Animates the banner in and out.
  final bool visible;

  /// Leading glyph.
  final IconData icon;

  /// Banner fill.
  final Color tone;

  /// Margin around the banner.
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final etaLabel = etaMinutes != null
        ? null
        : (etaText == null || etaText!.isEmpty ? null : etaText);

    return _SlideDownReveal(
      visible: visible,
      child: Padding(
        padding: margin,
        child: ZvTapScale(
          onTap: onTap,
          semanticLabel: '$statusLabel. Tap to track your order.',
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: tone,
              borderRadius: AppRadius.mdAll,
              boxShadow: AppShadows.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      height: 34,
                      width: 34,
                      decoration: const BoxDecoration(
                        color: AppColors.brandLime,
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Icon(icon, size: 19, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyStrong
                                .copyWith(color: AppColors.textOnDark),
                          ),
                          if (etaMinutes != null)
                            Row(
                              children: [
                                Text(
                                  'Arriving in ',
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.neutral300),
                                ),
                                ZvAnimatedCount(
                                  value: etaMinutes!.toDouble(),
                                  suffix: ' min',
                                  style: AppTextStyles.time
                                      .copyWith(color: AppColors.brandLime),
                                ),
                              ],
                            )
                          else if (etaLabel != null)
                            Text(
                              etaLabel,
                              style: AppTextStyles.time
                                  .copyWith(color: AppColors.brandLime),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Track',
                      style: AppTextStyles.button
                          .copyWith(color: AppColors.textOnDark),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textOnDark,
                    ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  ClipRRect(
                    borderRadius: AppRadius.fullAll,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: progress!.clamp(0, 1),
                        end: progress!.clamp(0, 1),
                      ),
                      duration: context.motion(AppMotion.deliberate),
                      curve: context.motionCurve(AppMotion.standard),
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 4,
                        backgroundColor: AppColors.neutral700,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.brandLime,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slides a bar up from below while fading it in.
class _SlideUpReveal extends StatelessWidget {
  const _SlideUpReveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motion(AppMotion.slow),
      switchInCurve: context.motionCurve(AppMotion.enter),
      switchOutCurve: context.motionCurve(AppMotion.exit),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: visible
          ? KeyedSubtree(key: const ValueKey('visible'), child: child)
          : const SizedBox(key: ValueKey('hidden'), width: double.infinity),
    );
  }
}

/// Slides a banner down from above while fading it in.
class _SlideDownReveal extends StatelessWidget {
  const _SlideDownReveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motion(AppMotion.slow),
      switchInCurve: context.motionCurve(AppMotion.enter),
      switchOutCurve: context.motionCurve(AppMotion.exit),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.bottomCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: visible
          ? KeyedSubtree(key: const ValueKey('visible'), child: child)
          : const SizedBox(key: ValueKey('hidden'), width: double.infinity),
    );
  }
}
