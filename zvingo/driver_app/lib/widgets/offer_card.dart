import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import 'driver_buttons.dart';
import 'slide_to_confirm.dart';
import 'status_chip.dart';

/// The delivery-offer panel — the highest-stakes component in the driver app.
///
/// A driver decides on an offer in roughly three seconds, often at a kerbside
/// with the engine running. The visual hierarchy is therefore fixed and
/// deliberate, largest to smallest:
///
/// 1. **Payout.** 48pt, black, tabular. The biggest thing on the screen.
/// 2. **Distance.** How far this job actually is.
/// 3. **Pickup → dropoff.** Where from, where to.
/// 4. **The countdown.** A full-width bar that drains left to right and moves
///    through `success` → `warning` → `error` as the offer expires, so the
///    pressure is legible peripherally without the driver reading a number.
///
/// Accepting is a slide, not a tap, by default: accepting is irreversible and
/// a pocket brush costs the driver a job they cannot do plus their acceptance
/// rate. Pass `acceptWithSlide: false` for a plain button where that trade-off
/// is not worth it.
///
/// ```dart
/// OfferCard(
///   merchantName: offer.merchantName,
///   merchantAddress: offer.merchantAddress,
///   customerAddress: offer.customerAddress,
///   deliveryFeeCents: offer.deliveryFeeCents,
///   tipCents: offer.tipCents,
///   estimatedDistanceKm: offer.estimatedDistanceKm,
///   estimatedTimeMinutes: offer.estimatedTimeMinutes,
///   remainingSeconds: remaining,
///   totalSeconds: offer.timeoutSeconds,
///   paymentMethod: offer.paymentMethod.displayName,
///   onAccept: _accept,
///   onDecline: _decline,
/// )
/// ```
class OfferCard extends StatelessWidget {
  /// Store the driver collects from.
  final String merchantName;

  /// Street address of the store.
  final String merchantAddress;

  /// Customer's display name.
  final String customerName;

  /// Street address of the drop-off.
  final String customerAddress;

  /// Gross delivery fee in cents. The driver's share is derived from it.
  final int deliveryFeeCents;

  /// Customer tip in cents, paid to the driver in full.
  final int tipCents;

  /// Order subtotal in cents, shown as context only.
  final int orderSubtotalCents;

  /// One-line summary of the basket, e.g. "2x Chicken burger, 1x Fanta".
  final String itemsSummary;

  /// Total route distance in kilometres.
  final double estimatedDistanceKm;

  /// Distance from the driver's current position to the store, in kilometres.
  /// Zero hides the row.
  final double pickupDistanceKm;

  /// Estimated total minutes for the job.
  final int estimatedTimeMinutes;

  /// Seconds left before the offer expires.
  final int remainingSeconds;

  /// Seconds the offer started with. Drives the countdown bar's scale.
  final int totalSeconds;

  /// Display name of the payment method, e.g. "Cash" or "EcoCash".
  final String paymentMethod;

  /// Share of [deliveryFeeCents] paid to the driver. Defaults to 0.85.
  final double driverFeeShare;

  /// Accept handler.
  final VoidCallback onAccept;

  /// Decline handler.
  final VoidCallback onDecline;

  /// Blocks input and shows a spinner while the accept request is in flight.
  final bool isSubmitting;

  /// Use slide-to-accept rather than a tap. On by default.
  final bool acceptWithSlide;

  const OfferCard({
    super.key,
    required this.merchantName,
    required this.merchantAddress,
    this.customerName = 'Customer',
    required this.customerAddress,
    required this.deliveryFeeCents,
    this.tipCents = 0,
    this.orderSubtotalCents = 0,
    this.itemsSummary = '',
    required this.estimatedDistanceKm,
    this.pickupDistanceKm = 0,
    required this.estimatedTimeMinutes,
    required this.remainingSeconds,
    this.totalSeconds = 45,
    required this.paymentMethod,
    this.driverFeeShare = 0.85,
    required this.onAccept,
    required this.onDecline,
    this.isSubmitting = false,
    this.acceptWithSlide = true,
  });

  /// Driver take-home for this offer in cents: their share of the delivery fee
  /// plus the whole tip.
  int get payoutCents => (deliveryFeeCents * driverFeeShare).round() + tipCents;

  /// Fraction of the offer window still remaining, 0..1.
  double get _timeFraction =>
      totalSeconds <= 0 ? 0 : (remainingSeconds / totalSeconds).clamp(0.0, 1.0);

  /// The countdown's tone. Green while there is room, amber under a third,
  /// red under 15% — paired with the shrinking bar so it is never colour alone.
  StatusTone get _timeTone {
    final f = _timeFraction;
    if (f <= 0.15) return StatusTone.error;
    if (f <= 0.35) return StatusTone.warning;
    return StatusTone.success;
  }

  Color _timeColor(BuildContext context) => switch (_timeTone) {
        StatusTone.error => AppColors.errorOf(context),
        StatusTone.warning => AppColors.warningOf(context),
        _ => AppColors.successOf(context),
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final muted =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final timeColor = _timeColor(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppSpacing.brSheetTop,
        boxShadow: AppSpacing.shadowLgOf(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 4. The countdown, physically at the top edge so it is read
          //       peripherally rather than deliberately.
          _CountdownBar(
            fraction: _timeFraction,
            color: timeColor,
            trackColor: AppColors.surfaceMutedOf(context),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: seconds left + decline ───────────────────────
                Row(
                  children: [
                    StatusChip(
                      label: '${remainingSeconds}s left',
                      tone: _timeTone,
                      icon: Icons.timer_outlined,
                      preserveCase: true,
                      emphasized: _timeTone == StatusTone.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusChip(
                      label: paymentMethod,
                      tone: paymentMethod.toLowerCase() == 'cash'
                          ? StatusTone.warning
                          : StatusTone.info,
                      icon: paymentMethod.toLowerCase() == 'cash'
                          ? Icons.payments_outlined
                          : Icons.phone_iphone_rounded,
                      preserveCase: true,
                    ),
                    const Spacer(),
                    DriverIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Decline offer',
                      onPressed: isSubmitting ? null : onDecline,
                      size: 40,
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── 1. Payout — the largest thing on the screen ──────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _money(payoutCents),
                              maxLines: 1,
                              style: AppTextStyles.moneyHero
                                  .copyWith(color: onSurface),
                            ),
                          ),
                          Text(
                            tipCents > 0
                                ? 'You earn · includes ${_money(tipCents)} tip'
                                : 'You earn',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                    if (orderSubtotalCents > 0) ...[
                      const SizedBox(width: AppSpacing.md),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _money(orderSubtotalCents),
                            style:
                                AppTextStyles.money.copyWith(color: muted),
                          ),
                          Text(
                            'basket',
                            style: AppTextStyles.overline
                                .copyWith(color: muted),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── 2. Distance and time ─────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        icon: Icons.route_rounded,
                        value: '${estimatedDistanceKm.toStringAsFixed(1)} km',
                        label: 'Total trip',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _Metric(
                        icon: Icons.schedule_rounded,
                        value: '$estimatedTimeMinutes min',
                        label: 'Estimated',
                      ),
                    ),
                    if (pickupDistanceKm > 0) ...[
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _Metric(
                          icon: Icons.near_me_rounded,
                          value: '${pickupDistanceKm.toStringAsFixed(1)} km',
                          label: 'To store',
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── 3. Pickup → dropoff ──────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMutedOf(context),
                    borderRadius: AppSpacing.brLg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RouteRow(
                        isPickup: true,
                        name: merchantName,
                        address: merchantAddress,
                        detail: itemsSummary,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: SizedBox(
                          height: AppSpacing.lg,
                          child: VerticalDivider(
                            width: 2,
                            thickness: 2,
                            color: AppColors.borderOf(context),
                          ),
                        ),
                      ),
                      _RouteRow(
                        isPickup: false,
                        name: customerName,
                        address: customerAddress,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Accept ───────────────────────────────────────────────
                if (acceptWithSlide)
                  DriverSlideToConfirm(
                    text: 'Slide to accept',
                    action: SlideAction.proceed,
                    isLoading: isSubmitting,
                    enabled: remainingSeconds > 0,
                    disabledReason: remainingSeconds > 0
                        ? null
                        : 'This offer expired. The next one will appear here.',
                    confirmedLabel: 'Accepted',
                    onConfirm: onAccept,
                  )
                else
                  DriverPrimaryButton(
                    label: 'Accept delivery',
                    icon: Icons.check_rounded,
                    isLoading: isSubmitting,
                    onPressed: remainingSeconds > 0 ? onAccept : null,
                    disabledReason: remainingSeconds > 0
                        ? null
                        : 'This offer expired. The next one will appear here.',
                  ),

                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: DriverTextButton(
                    label: 'No thanks',
                    onPressed: isSubmitting ? null : onDecline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
}

/// Full-width bar that drains as the offer expires. Animated so the motion
/// itself carries the urgency; the colour is a second, redundant signal.
class _CountdownBar extends StatelessWidget {
  final double fraction;
  final Color color;
  final Color trackColor;

  const _CountdownBar({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: trackColor)),
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: fraction, end: fraction),
                duration: AppMotion.durationOf(context, AppMotion.base),
                curve: Curves.linear,
                builder: (context, value, _) => FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: AnimatedContainer(
                    duration: AppMotion.durationOf(context, AppMotion.fast),
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One glanceable number with its label beneath, used for distance and time.
class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Metric({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: muted),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: AppTextStyles.metric.copyWith(
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// A pickup or dropoff line: coloured node, name, address, optional detail.
class _RouteRow extends StatelessWidget {
  final bool isPickup;
  final String name;
  final String address;
  final String detail;

  const _RouteRow({
    required this.isPickup,
    required this.name,
    required this.address,
    this.detail = '',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final node = isPickup
        ? AppColors.warningOf(context)
        : AppColors.successOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            isPickup ? Icons.storefront_rounded : Icons.flag_rounded,
            size: 18,
            color: node,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyStrong.copyWith(
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
              if (address.isNotEmpty)
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(color: muted),
                ),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(color: muted),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
