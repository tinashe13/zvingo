import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../core/router.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/widgets.dart';
import 'delivery_step_scaffold.dart';

/// Step 7 — closing out the delivery.
///
/// ## What was removed here, and why
///
/// This screen used to collect a four-digit "Customer PIN" and a "Cash
/// collected" amount, and pass both to `completeDelivery(pin:,
/// cashCollectedCents:)` — which ignored both arguments entirely. Nothing
/// validated the PIN, because there is nothing in the backend to validate it
/// against: `Order` has no PIN field, no endpoint accepts one, and no PIN is
/// ever issued to a customer. `POST /finance/earnings/record` takes only an
/// order id and a driver id, so the cash figure had nowhere to go either.
///
/// Two boxes that accept any value and discard it are worse than no boxes:
/// they teach a driver that the handover was verified and the cash was
/// reconciled when neither happened, and they are exactly what a dispute would
/// be argued over later. Both are gone. What is left is true:
///
/// * the payout the driver actually earned, from the accepted offer;
/// * the cash they were due to take, if it was a cash order — stated as a
///   reminder, not captured as data the system does not store;
/// * a slide that calls `POST /dispatch/complete`, which is the real,
///   audited `DELIVERED` transition.
///
/// The D1 report specifies the exact endpoint and payload needed to make
/// handover verification and cash reconciliation real.
class CompleteDeliveryScreen extends ConsumerWidget {
  const CompleteDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delivery = ref.watch(deliveryProvider);
    final job = delivery.activeJob;

    if (job == null) return const NoActiveDelivery();

    final payoutCents = delivery.earningsCents ?? job.payoutCents();
    final cashCents = job.cashToCollectCents;

    return DeliveryStepScaffold(
      title: 'Finish the delivery',
      subtitle: delivery.activeOrderShortId == null
          ? null
          : '#${delivery.activeOrderShortId}',
      state: delivery.deliveryState,
      supporting: Text(
        'This marks the order delivered for the customer and the restaurant, '
        'and books your earnings.',
        textAlign: TextAlign.center,
        style: AppTextStyles.onSurface(context, AppTextStyles.caption),
      ),
      footer: DriverSlideToConfirm(
        text: 'Slide to complete delivery',
        action: SlideAction.deliver,
        enabled: !delivery.isLoading,
        isLoading: delivery.isLoading,
        confirmedLabel: 'Delivered',
        onConfirm: () async {
          final done = await ref.read(deliveryProvider.notifier).completeDelivery();
          if (!context.mounted) return;
          // Only leave when the backend actually accepted it. A failure keeps
          // the driver here with a plain-language reason and the slide ready to
          // try again — losing a completed delivery off the screen would mean
          // losing the payment for it.
          if (done) {
            DriverSnack.show(
              context,
              'Delivered. ${formatUsdCents(payoutCents)} added to today.',
              icon: Icons.check_circle_outline_rounded,
            );
            context.go(routeHome);
          }
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PayoutCard(cents: payoutCents),
          Gap.lg,
          DeliveryInfoCard(
            icon: Icons.receipt_long_outlined,
            headline: 'Before you close this',
            explanation: cashCents > 0
                ? 'Make sure you took the cash and the customer has their '
                    'order. Completing this is final.'
                : 'Make sure the customer has their order. Completing this is '
                    'final.',
            children: [
              DeliveryFactRow(label: 'Customer', value: job.customerName),
              DeliveryFactRow(
                label: 'Payment',
                value: job.paymentMethod.displayName,
              ),
              if (cashCents > 0)
                DeliveryFactRow(
                  label: 'Cash you collected',
                  value: formatUsdCents(cashCents),
                  emphasise: true,
                ),
              DeliveryFactRow(
                label: 'Delivery fee',
                value: formatUsdCents(job.deliveryFeeCents),
              ),
              if (job.tipCents > 0)
                DeliveryFactRow(
                  label: 'Tip',
                  value: formatUsdCents(job.tipCents),
                  emphasise: true,
                ),
            ],
          ),
          Gap.lg,
          // The one place a driver can get truly stuck: the food is handed
          // over but the order will not close (it was cancelled underneath
          // them, or support already completed it). `POST /dispatch/reset` is
          // state-aware server-side — an order they collected is completed
          // through the state machine, one they never collected is released —
          // so this is a safe last resort rather than a data-loss button.
          DriverTextButton(
            label: "This delivery is stuck",
            icon: Icons.support_agent_outlined,
            expanded: true,
            onPressed: () => _unstick(context, ref, delivery.activeOrderShortId),
          ),
        ],
      ),
    );
  }

  Future<void> _unstick(
    BuildContext context,
    WidgetRef ref,
    String? shortId,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Clear this delivery?',
      consequence:
          'Use this only if order #${shortId ?? ''} will not complete. If you '
          'already handed the food over it will be recorded as delivered and '
          'you will be paid; if you never collected it, it goes back to '
          'dispatch and you will not be paid for it.',
      confirmLabel: 'Clear it',
      cancelLabel: 'Try again instead',
      icon: Icons.cleaning_services_outlined,
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(deliveryProvider.notifier).resetToIdle();
    if (!context.mounted) return;
    context.go(routeHome);
  }
}

/// What the driver earned. The largest thing on the screen, by design.
class _PayoutCard extends StatelessWidget {
  final int cents;

  const _PayoutCard({required this.cents});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        // §1.2 made `AppColors.primary` near-black. A payout celebration is
        // semantically positive, so it takes the brand green ramp rather than
        // the action colour.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandGreen, AppColors.brandGreenDark],
        ),
        borderRadius: AppSpacing.brLg,
        boxShadow: AppSpacing.shadowMdOf(context),
      ),
      child: Column(
        children: [
          Text(
            'YOU EARNED',
            style: AppTextStyles.overline.copyWith(color: AppColors.textOnDark),
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            child: AnimatedCount.currency(
              cents: cents,
              style: AppTextStyles.moneyHero.copyWith(
                color: AppColors.textOnDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
