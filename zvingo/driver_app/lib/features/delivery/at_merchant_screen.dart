import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../models/delivery_state.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/delivery_step_indicator.dart';

/// AtMerchantScreen — merchant info + confirm pickup.
/// Port of AtMerchantScreen.kt.
class AtMerchantScreen extends ConsumerWidget {
  const AtMerchantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delivery = ref.watch(deliveryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: DeliveryStepIndicator(
                currentState: delivery.deliveryState,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.store,
                          size: 40, color: AppColors.primary),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'You have arrived',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Order #${delivery.activeOrderShortId ?? ''}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 32),

                    // Order summary card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order Summary',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          _infoRow(context, 'Status', 'Ready for pickup'),
                          const SizedBox(height: 8),
                          _infoRow(context, 'Order ID',
                              delivery.activeOrderShortId ?? ''),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Confirm pickup button
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    ref
                        .read(deliveryProvider.notifier)
                        .transitionTo(DeliveryState.pickedUp);
                    context.go('/delivery/confirm-pickup');
                  },
                  child: const Text(
                    'Confirm Pickup',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
