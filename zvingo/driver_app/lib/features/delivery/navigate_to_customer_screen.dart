import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../widgets/navigation_map.dart';
import '../../core/app_colors.dart';
import '../../models/delivery_state.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/delivery_step_indicator.dart';
import '../../widgets/slide_to_confirm.dart';

/// NavigateToCustomerScreen — port of NavigateToCustomerScreen.kt.
class NavigateToCustomerScreen extends ConsumerWidget {
  const NavigateToCustomerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delivery = ref.watch(deliveryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child:
                  DeliveryStepIndicator(currentState: delivery.deliveryState),
            ),
            // Map View
            Expanded(
              child: NavigationMap(
                destination: LatLng(
                  delivery.currentOffer?.deliveryLat ?? -17.8248,
                  delivery.currentOffer?.deliveryLng ?? 31.0530,
                ),
                destinationLabel:
                    delivery.currentOffer?.customerName ?? 'Customer',
                secondaryLocation: LatLng(
                  delivery.currentOffer?.pickupLat ?? -17.8216,
                  delivery.currentOffer?.pickupLng ?? 31.0492,
                ),
                secondaryLabel:
                    delivery.currentOffer?.merchantName ?? 'Merchant',
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_pin_circle,
                          color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Deliver to Customer',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Order #${delivery.activeOrderShortId ?? ''}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SlideToConfirm(
                    text: 'Slide to confirm arrival',
                    onConfirm: () {
                      ref
                          .read(deliveryProvider.notifier)
                          .transitionTo(DeliveryState.arrivedDelivery);
                      context.go('/delivery/at-customer');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
