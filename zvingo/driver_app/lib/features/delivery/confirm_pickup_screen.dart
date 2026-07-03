import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../models/delivery_state.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/delivery_step_indicator.dart';
import '../../widgets/slide_to_confirm.dart';

/// ConfirmPickupScreen — confirmation after picking up.
/// Port of ConfirmPickupScreen.kt.
class ConfirmPickupScreen extends ConsumerWidget {
  const ConfirmPickupScreen({super.key});

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
                      child: const Icon(Icons.check,
                          size: 40, color: AppColors.primary),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Order Picked Up!',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Head to the customer now',
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
              child: SlideToConfirm(
                text: 'Slide to start delivery',
                onConfirm: () {
                  ref
                      .read(deliveryProvider.notifier)
                      .transitionTo(DeliveryState.enRouteDelivery);
                  context.go('/delivery/navigate-to-customer');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
