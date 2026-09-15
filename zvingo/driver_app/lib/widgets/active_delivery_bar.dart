import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import '../models/delivery_state.dart';
import 'tap_scale.dart';

/// Persistent "you have a delivery in progress" bar (§5.4 persistent context
/// bars).
///
/// The driver app's worst possible failure is a driver who has accepted a job,
/// wandered into the Earnings tab, and cannot find their way back to it. This
/// bar sits above the bottom navigation on *every* tab whenever a delivery is
/// live, states which step they are on, and taps straight back into the flow.
///
/// It is rendered by `MainShell`, which already wires it to `deliveryProvider`.
/// Feature code does not normally construct it — but it is public so a
/// full-screen feature can render the same affordance when it hides the shell.
///
/// ```dart
/// ActiveDeliveryBar(
///   state: delivery.deliveryState,
///   orderLabel: delivery.activeOrderShortId,
///   destination: delivery.currentOffer?.merchantName,
///   onTap: () => context.go(deliveryRouteFor(delivery.deliveryState)),
/// )
/// ```
class ActiveDeliveryBar extends StatelessWidget {
  /// Current step of the delivery state machine.
  final DeliveryState state;

  /// Short order id, e.g. `#A4F2`. Optional.
  final String? orderLabel;

  /// Where the driver is heading right now — merchant or customer name.
  final String? destination;

  /// Taps back into the delivery flow. Required: a context bar that does
  /// nothing is worse than no context bar.
  final VoidCallback onTap;

  const ActiveDeliveryBar({
    super.key,
    required this.state,
    required this.onTap,
    this.orderLabel,
    this.destination,
  });

  /// A one-line, driver-facing description of [state].
  static String headlineFor(DeliveryState state) => switch (state) {
        DeliveryState.offered => 'Offer waiting',
        DeliveryState.accepted => 'Delivery accepted',
        DeliveryState.enRoutePickup => 'Heading to the store',
        DeliveryState.arrivedPickup => 'At the store',
        DeliveryState.pickedUp => 'Order collected',
        DeliveryState.enRouteDelivery => 'Heading to the customer',
        DeliveryState.arrivedDelivery => 'At the customer',
        DeliveryState.delivered => 'Wrapping up',
        DeliveryState.completed => 'Delivery complete',
      };

  /// The glyph paired with [state], so the bar never relies on colour alone.
  static IconData iconFor(DeliveryState state) => switch (state) {
        DeliveryState.offered => Icons.notifications_active_rounded,
        DeliveryState.accepted => Icons.task_alt_rounded,
        DeliveryState.enRoutePickup => Icons.storefront_rounded,
        DeliveryState.arrivedPickup => Icons.store_mall_directory_rounded,
        DeliveryState.pickedUp => Icons.shopping_bag_rounded,
        DeliveryState.enRouteDelivery => Icons.delivery_dining_rounded,
        DeliveryState.arrivedDelivery => Icons.home_rounded,
        DeliveryState.delivered => Icons.check_circle_rounded,
        DeliveryState.completed => Icons.check_circle_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? AppColors.darkAction : AppColors.action;
    final onFill = isDark ? AppColors.darkTextOnAction : AppColors.textOnDark;

    final subtitle = [
      if (orderLabel != null && orderLabel!.isNotEmpty) orderLabel!,
      if (destination != null && destination!.isNotEmpty) destination!,
    ].join(' · ');

    return Semantics(
      button: true,
      label: 'Delivery in progress: ${headlineFor(state)}',
      hint: 'Double tap to return to the delivery',
      child: TapScale(
        onTap: onTap,
        enforceMinTarget: false,
        child: Container(
          height: AppSpacing.activeDeliveryBarHeight,
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: AppSpacing.brLg,
            boxShadow: AppSpacing.shadowMdOf(context),
          ),
          child: Row(
            children: [
              _LivePulse(color: onFill, icon: iconFor(state)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headlineFor(state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyStrong.copyWith(color: onFill),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption
                            .copyWith(color: onFill.withValues(alpha: 0.72)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: onFill.withValues(alpha: 0.16),
                  borderRadius: AppSpacing.brFull,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Resume',
                      style: AppTextStyles.overline.copyWith(color: onFill),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(Icons.chevron_right_rounded, size: 18, color: onFill),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A slow breathing ring behind the step glyph — the "this is live" signal.
/// Stops entirely under reduced motion.
class _LivePulse extends StatefulWidget {
  final Color color;
  final IconData icon;

  const _LivePulse({required this.color, required this.icon});

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 26 + 14 * t,
                height: 26 + 14 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.20 * (1 - t)),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.18),
                ),
                child: Icon(widget.icon, size: 19, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}
