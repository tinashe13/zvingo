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

/// Step 3 — at the counter, collecting the order.
///
/// ## Handover verification: what is real here, and what is not
///
/// The backend has **no pickup PIN or collection code** — there is no field on
/// `Order`, no endpoint that takes one, and nothing that issues one to a
/// merchant (see the D1 report for the exact route this needs). A PIN box here
/// would therefore be theatre: it would accept `0000` and every other value
/// identically, and it would teach drivers that typing four digits means the
/// order was verified when nothing was verified at all.
///
/// So this screen does the check that *can* actually be made with the data
/// that exists, and says plainly that that is what it is: the order reference
/// is shown at full size for the counter staff to match against the label on
/// the bag, and the driver confirms the match before the slide unlocks. That
/// catches the failure this step really has — walking out with the wrong
/// restaurant's bag — without pretending to be cryptography.
///
/// The step is also the point of no return: after `PICKED_UP` the backend will
/// not hand the order back to dispatch (`RELEASABLE_STATES` stops here), which
/// is why confirming is a slide and why "can't collect this" is offered
/// *before* it rather than after.
class AtMerchantScreen extends ConsumerStatefulWidget {
  const AtMerchantScreen({super.key});

  @override
  ConsumerState<AtMerchantScreen> createState() => _AtMerchantScreenState();
}

class _AtMerchantScreenState extends ConsumerState<AtMerchantScreen> {
  bool _labelMatches = false;

  Future<void> _release() async {
    final delivery = ref.read(deliveryProvider);
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Hand this order back?',
      consequence:
          'Order #${delivery.activeOrderShortId ?? ''} goes back to dispatch '
          'and straight to another driver. You will not be paid for it, and '
          'declining jobs you accepted affects your acceptance rate.',
      confirmLabel: 'Hand it back',
      cancelLabel: 'Keep it',
      icon: Icons.undo_rounded,
    );
    if (!confirmed || !mounted) return;

    final released = await ref.read(deliveryProvider.notifier).releaseOrder();
    if (!mounted || !released) return;
    context.go(routeHome);
  }

  @override
  Widget build(BuildContext context) {
    final delivery = ref.watch(deliveryProvider);
    final job = delivery.activeJob;

    if (job == null) return const NoActiveDelivery();

    final orderRef = delivery.activeOrderShortId ?? job.shortId;

    return DeliveryStepScaffold(
      title: 'Collect the order',
      subtitle: job.merchantName,
      state: delivery.deliveryState,
      supporting: Text(
        'Confirming means the food is in your hands. After this the order '
        'cannot go back to dispatch.',
        textAlign: TextAlign.center,
        style: AppTextStyles.onSurface(context, AppTextStyles.caption),
      ),
      footer: DriverSlideToConfirm(
        text: 'Slide to confirm pickup',
        action: SlideAction.pickup,
        enabled: _labelMatches && !delivery.isLoading,
        isLoading: delivery.isLoading,
        disabledReason:
            'Confirm the bag label matches #$orderRef before collecting.',
        onConfirm: () async {
          await ref.read(deliveryProvider.notifier).confirmPickup();
          if (!context.mounted) return;
          context.go(routeConfirmPickup);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The single most useful thing on this screen: the reference the
          // driver holds up at the counter. Sized to be read across it.
          _OrderReferenceCard(reference: orderRef),
          Gap.lg,

          DeliveryInfoCard(
            icon: Icons.shopping_bag_outlined,
            headline: "What you're collecting",
            explanation:
                'Check the bag label against the reference above before you '
                'take it. A mismatched bag is the one mistake that cannot be '
                'fixed once you ride off.',
            children: [
              DeliveryFactRow(
                label: 'Restaurant',
                value: job.merchantName,
              ),
              if (job.itemsSummary.isNotEmpty)
                DeliveryFactRow(label: 'Items', value: job.itemsSummary),
              if (job.itemCount > 0)
                DeliveryFactRow(
                  label: 'Item count',
                  value: '${job.itemCount}',
                ),
              DeliveryFactRow(
                label: 'Your payout',
                value: formatUsdCents(job.payoutCents()),
                emphasise: true,
              ),
            ],
          ),
          Gap.lg,

          _MatchCheck(
            reference: orderRef,
            checked: _labelMatches,
            onChanged: (value) => setState(() => _labelMatches = value),
          ),
          Gap.lg,

          DriverTextButton(
            label: "Can't collect this order",
            icon: Icons.report_problem_outlined,
            expanded: true,
            onPressed: _release,
          ),
        ],
      ),
    );
  }
}

/// The order reference, at counter-reading size.
class _OrderReferenceCard extends StatelessWidget {
  final String reference;

  const _OrderReferenceCard({required this.reference});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandGreenSurface,
        borderRadius: AppSpacing.brLg,
        border: Border.all(color: AppColors.brandGreen.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            'SHOW THIS AT THE COUNTER',
            textAlign: TextAlign.center,
            style: AppTextStyles.overline.copyWith(
              color: AppColors.brandGreenDark,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            child: Text(
              '#$reference',
              style: AppTextStyles.moneyHero.copyWith(
                color: AppColors.brandGreenDark,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The human check that unlocks the slide.
///
/// It is a checkbox and not a code entry on purpose — see the class docs on
/// [AtMerchantScreen]. The wording says exactly what the driver is attesting
/// to, so nobody mistakes it for a verified handover.
class _MatchCheck extends StatelessWidget {
  final String reference;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _MatchCheck({
    required this.reference,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tint =
        checked ? AppColors.successOf(context) : AppColors.borderOf(context);

    return TapScale(
      onTap: () => onChanged(!checked),
      semanticLabel: checked
          ? 'Bag label confirmed as matching order $reference'
          : 'Confirm the bag label matches order $reference',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        decoration: BoxDecoration(
          color: checked
              ? AppColors.successSurfaceOf(context)
              : AppColors.surfaceOf(context),
          borderRadius: AppSpacing.brMd,
          border: Border.all(color: tint, width: checked ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
              checked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: checked
                  ? AppColors.successOf(context)
                  : AppColors.neutral400,
              size: 26,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'The bag label says #$reference',
                style: AppTextStyles.onSurface(
                  context,
                  AppTextStyles.bodyStrong,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
