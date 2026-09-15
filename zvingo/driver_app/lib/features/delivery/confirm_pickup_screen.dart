import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../core/router.dart';
import '../../models/delivery_state.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/widgets.dart';
import 'delivery_step_scaffold.dart';

/// Step 4 — collected, about to set off for the customer.
///
/// A deliberate pause between two very different halves of the job. The driver
/// has the food and is about to ride; this is the last calm moment to read the
/// drop-off address, and the only place before the door where they learn
/// whether they have to collect money.
///
/// **On the missing PIN:** this screen used to be described as verifying a
/// pickup PIN. It never did, and nothing server-side could have: there is no
/// pickup code anywhere in the backend. The verification that *can* be made
/// happens one step earlier, at the counter (see [AtMerchantScreen]); this
/// screen carries no input that pretends to check anything.
class ConfirmPickupScreen extends ConsumerWidget {
  const ConfirmPickupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delivery = ref.watch(deliveryProvider);
    final job = delivery.activeJob;

    if (job == null) return const NoActiveDelivery();

    final cashCents = job.cashToCollectCents;

    return DeliveryStepScaffold(
      title: 'Ride to ${job.customerName}',
      subtitle: delivery.activeOrderShortId == null
          ? null
          : '#${delivery.activeOrderShortId}',
      state: delivery.deliveryState,
      footer: DriverSlideToConfirm(
        text: 'Slide to start delivery',
        action: SlideAction.deliver,
        onConfirm: () {
          ref
              .read(deliveryProvider.notifier)
              .transitionTo(DeliveryState.enRouteDelivery);
          context.go(routeNavigateToCustomer);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeliveryInfoCard(
            icon: Icons.check_circle_outline_rounded,
            iconColor: AppColors.successOf(context),
            headline: 'Order collected',
            explanation: 'The restaurant is done. Everything from here is '
                'about getting it to the customer while it is still hot.',
            children: [
              DeliveryFactRow(
                label: 'Deliver to',
                value: job.customerName,
              ),
              if (job.customerAddress.isNotEmpty)
                DeliveryFactRow(
                  label: 'Address',
                  value: job.customerAddress,
                ),
              if (job.estimatedDistanceKm > 0)
                DeliveryFactRow(
                  label: 'Distance',
                  value: '${job.estimatedDistanceKm.toStringAsFixed(1)} km',
                ),
              DeliveryFactRow(
                label: 'Your payout',
                value: formatUsdCents(job.payoutCents()),
                emphasise: true,
              ),
            ],
          ),
          Gap.lg,
          // Being surprised by "that's cash" at the door is how drivers end up
          // out of pocket. Say it here, while there is still time to think.
          _PaymentBrief(
            methodLabel: job.paymentMethod.displayName,
            cashToCollectCents: cashCents,
          ),
        ],
      ),
    );
  }
}

/// How this order is paid, and what — if anything — the driver has to collect.
class _PaymentBrief extends StatelessWidget {
  final String methodLabel;
  final int cashToCollectCents;

  const _PaymentBrief({
    required this.methodLabel,
    required this.cashToCollectCents,
  });

  @override
  Widget build(BuildContext context) {
    final isCash = cashToCollectCents > 0;
    final tone = isCash ? AppColors.warningOf(context) : AppColors.successOf(context);
    final background = isCash
        ? AppColors.warningSurfaceOf(context)
        : AppColors.successSurfaceOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppSpacing.brLg,
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCash ? Icons.payments_outlined : Icons.verified_outlined,
            color: tone,
            size: 28,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCash ? 'Collect cash at the door' : 'Already paid',
                  style: AppTextStyles.h3.copyWith(color: tone),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  isCash
                      ? 'Take ${formatUsdCents(cashToCollectCents)} from the '
                          'customer before you hand the order over.'
                      : 'Paid by $methodLabel. Take nothing at the door.',
                  style: AppTextStyles.body.copyWith(color: tone),
                ),
                if (isCash) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    formatUsdCents(cashToCollectCents),
                    style: AppTextStyles.moneyLarge.copyWith(color: tone),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
