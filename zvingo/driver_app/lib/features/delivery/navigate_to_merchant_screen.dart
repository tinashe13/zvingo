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

/// Step 2 — riding to the restaurant.
///
/// The map fills the screen because the only thing the driver needs here is
/// the road. The panel underneath carries the two facts they will be asked at
/// the counter (which restaurant, which order) and the single action.
class NavigateToMerchantScreen extends ConsumerWidget {
  const NavigateToMerchantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delivery = ref.watch(deliveryProvider);
    final job = delivery.activeJob;

    if (job == null) return const NoActiveDelivery();

    final orderLabel =
        delivery.activeOrderShortId == null ? null : '#${delivery.activeOrderShortId}';

    return DeliveryStepScaffold(
      title: 'Ride to ${job.merchantName}',
      subtitle: orderLabel,
      state: delivery.deliveryState,
      fillBody: true,
      footer: DriverSlideToConfirm(
        text: "Slide when you're at the store",
        action: SlideAction.arrive,
        onConfirm: () {
          ref
              .read(deliveryProvider.notifier)
              .transitionTo(DeliveryState.arrivedPickup);
          context.go(routeAtMerchant);
        },
      ),
      child: Column(
        children: [
          Expanded(
            child: job.hasPickupCoords
                ? NavigationMap(
                    destination: LatLng(job.pickupLat, job.pickupLng),
                    destinationLabel: job.merchantName,
                    secondaryLocation: job.hasDeliveryCoords
                        ? LatLng(job.deliveryLat, job.deliveryLng)
                        : null,
                    secondaryLabel: job.customerName,
                  )
                // Never fall back to a hardcoded city-centre point: sending a
                // driver to the wrong place costs them the delivery. Say what
                // is missing and give them the address to navigate by.
                : _NoPickupCoordinates(address: job.merchantAddress),
          ),
          _PickupBrief(
            merchantName: job.merchantName,
            merchantAddress: job.merchantAddress,
            itemsSummary: job.itemsSummary,
          ),
        ],
      ),
    );
  }
}

/// The counter brief: the name to ask for and the address to find.
class _PickupBrief extends StatelessWidget {
  final String merchantName;
  final String merchantAddress;
  final String itemsSummary;

  const _PickupBrief({
    required this.merchantName,
    required this.merchantAddress,
    required this.itemsSummary,
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
          const Icon(
            Icons.storefront_rounded,
            color: AppColors.brandGreen,
            size: 26,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchantName,
                  style: AppTextStyles.onSurface(context, AppTextStyles.h3),
                ),
                if (merchantAddress.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    merchantAddress,
                    style:
                        AppTextStyles.onSurface(context, AppTextStyles.caption),
                  ),
                ],
                if (itemsSummary.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  StatusChip(
                    label: itemsSummary,
                    tone: StatusTone.neutral,
                    icon: Icons.shopping_bag_outlined,
                    preserveCase: true,
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

/// Shown when the job arrived without a usable pickup point.
class _NoPickupCoordinates extends StatelessWidget {
  final String address;

  const _NoPickupCoordinates({required this.address});

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
                'No map pin for this store',
                textAlign: TextAlign.center,
                style: AppTextStyles.onSurface(context, AppTextStyles.h3),
              ),
              Gap.sm,
              Text(
                address.isEmpty
                    ? 'Call support for directions before you set off.'
                    : 'Navigate to: $address',
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
