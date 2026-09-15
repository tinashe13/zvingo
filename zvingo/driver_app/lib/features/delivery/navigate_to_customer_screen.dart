import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../core/router.dart';
import '../../models/delivery_state.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/widgets.dart';
import 'delivery_step_scaffold.dart';

/// Step 5 — riding to the customer with the food.
class NavigateToCustomerScreen extends ConsumerWidget {
  const NavigateToCustomerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delivery = ref.watch(deliveryProvider);
    final job = delivery.activeJob;

    if (job == null) return const NoActiveDelivery();

    return DeliveryStepScaffold(
      title: 'Ride to ${job.customerName}',
      subtitle: delivery.activeOrderShortId == null
          ? null
          : '#${delivery.activeOrderShortId}',
      state: delivery.deliveryState,
      fillBody: true,
      footer: DriverSlideToConfirm(
        text: "Slide when you've arrived",
        action: SlideAction.arrive,
        onConfirm: () {
          ref
              .read(deliveryProvider.notifier)
              .transitionTo(DeliveryState.arrivedDelivery);
          context.go(routeAtCustomer);
        },
      ),
      child: Column(
        children: [
          Expanded(
            child: job.hasDeliveryCoords
                ? NavigationMap(
                    destination: LatLng(job.deliveryLat, job.deliveryLng),
                    destinationLabel: job.customerName,
                    secondaryLocation: job.hasPickupCoords
                        ? LatLng(job.pickupLat, job.pickupLng)
                        : null,
                    secondaryLabel: job.merchantName,
                  )
                : _NoDropoffCoordinates(address: job.customerAddress),
          ),
          _DropoffBrief(
            customerName: job.customerName,
            customerAddress: job.customerAddress,
            cashToCollectCents: job.cashToCollectCents,
          ),
        ],
      ),
    );
  }
}

/// Who to find, where, and whether money changes hands.
class _DropoffBrief extends StatelessWidget {
  final String customerName;
  final String customerAddress;
  final int cashToCollectCents;

  const _DropoffBrief({
    required this.customerName,
    required this.customerAddress,
    required this.cashToCollectCents,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.person_pin_circle_rounded,
            color: AppColors.errorOf(context),
            size: 26,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customerName,
                  style: AppTextStyles.onSurface(context, AppTextStyles.h3),
                ),
                if (customerAddress.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    customerAddress,
                    style:
                        AppTextStyles.onSurface(context, AppTextStyles.caption),
                  ),
                ],
                if (cashToCollectCents > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  StatusChip(
                    label:
                        'Collect ${formatUsdCents(cashToCollectCents)} cash',
                    tone: StatusTone.warning,
                    icon: Icons.payments_outlined,
                    preserveCase: true,
                    emphasized: true,
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

/// Shown when the job has no usable drop-off point. Navigating to (0, 0) would
/// point a driver at the Atlantic, so the address is shown instead.
class _NoDropoffCoordinates extends StatelessWidget {
  final String address;

  const _NoDropoffCoordinates({required this.address});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceMutedOf(context),
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.screenPaddingOf(context)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wrong_location_outlined,
                size: 56,
                color: AppColors.warningOf(context),
              ),
              Gap.md,
              Text(
                'No map pin for this address',
                textAlign: TextAlign.center,
                style: AppTextStyles.onSurface(context, AppTextStyles.h3),
              ),
              Gap.sm,
              Text(
                address.isEmpty
                    ? 'Call support before you set off — there is no drop-off '
                        'address on this order.'
                    : 'Deliver to: $address',
                textAlign: TextAlign.center,
                style: AppTextStyles.onSurface(context, AppTextStyles.body),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
