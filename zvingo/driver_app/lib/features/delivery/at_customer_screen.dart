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

/// Step 6 — at the door, handing over.
///
/// The one thing that matters here is money: if this is a cash order the
/// driver must take the right amount *before* the bag leaves their hand, and
/// the amount is therefore the largest thing on the screen. Everything else is
/// context.
class AtCustomerScreen extends ConsumerWidget {
  const AtCustomerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delivery = ref.watch(deliveryProvider);
    final job = delivery.activeJob;

    if (job == null) return const NoActiveDelivery();

    final cashCents = job.cashToCollectCents;

    return DeliveryStepScaffold(
      title: 'Hand over the order',
      subtitle: job.customerName,
      state: delivery.deliveryState,
      footer: DriverPrimaryButton(
        label: 'Handed over — finish up',
        icon: Icons.arrow_forward_rounded,
        onPressed: () {
          // A UI-only step: nothing is reported to the backend until the
          // driver confirms on the completion screen, so this is a plain
          // button rather than a slide.
          ref.read(deliveryProvider.notifier).transitionTo(
                DeliveryState.delivered,
              );
          context.go(routeCompleteDelivery);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cashCents > 0) _CashDue(cents: cashCents) else const _AlreadyPaid(),
          Gap.lg,
          DeliveryInfoCard(
            icon: Icons.doorbell_outlined,
            headline: "You're there",
            explanation:
                'Check the name, hand over the bag, then close the delivery '
                'on the next screen.',
            children: [
              DeliveryFactRow(label: 'Customer', value: job.customerName),
              if (job.customerAddress.isNotEmpty)
                DeliveryFactRow(label: 'Address', value: job.customerAddress),
              if (delivery.activeOrderShortId != null)
                DeliveryFactRow(
                  label: 'Order',
                  value: '#${delivery.activeOrderShortId}',
                ),
              DeliveryFactRow(
                label: 'Your payout',
                value: formatUsdCents(job.payoutCents()),
                emphasise: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The amount to take, at arm's-length size.
class _CashDue extends StatelessWidget {
  final int cents;

  const _CashDue({required this.cents});

  @override
  Widget build(BuildContext context) {
    final tone = AppColors.warningOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.warningSurfaceOf(context),
        borderRadius: AppSpacing.brLg,
        border: Border.all(color: tone.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        children: [
          const StatusChip(
            label: 'Cash order',
            tone: StatusTone.warning,
            icon: Icons.payments_outlined,
            emphasized: true,
          ),
          Gap.md,
          Text(
            'Collect before you hand it over',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: tone),
          ),
          Gap.sm,
          FittedBox(
            child: Text(
              formatUsdCents(cents),
              style: AppTextStyles.moneyHero.copyWith(color: tone),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prepaid orders get the opposite message, just as loudly — a driver who asks
/// a customer for money they already paid has a bad day.
class _AlreadyPaid extends StatelessWidget {
  const _AlreadyPaid();

  @override
  Widget build(BuildContext context) {
    final tone = AppColors.successOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.successSurfaceOf(context),
        borderRadius: AppSpacing.brLg,
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: tone, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Already paid',
                  style: AppTextStyles.h3.copyWith(color: tone),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Take nothing from the customer.',
                  style: AppTextStyles.body.copyWith(color: tone),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
