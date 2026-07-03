import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/delivery_step_indicator.dart';

/// AtCustomerScreen — arrival at customer, complete delivery button.
/// Port of AtCustomerScreen.kt.
class AtCustomerScreen extends ConsumerWidget {
  const AtCustomerScreen({super.key});

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
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on,
                          size: 40, color: AppColors.primary),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'You have arrived!',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hand the order to the customer',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    context.go('/delivery/complete');
                  },
                  child: const Text(
                    'Complete Delivery',
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
}
