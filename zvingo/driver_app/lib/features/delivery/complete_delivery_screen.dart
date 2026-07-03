import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/delivery_step_indicator.dart';
import '../../widgets/slide_to_confirm.dart';

/// CompleteDeliveryScreen — PIN + cash input + payout summary.
/// Port of CompleteDeliveryScreen.kt.
class CompleteDeliveryScreen extends ConsumerStatefulWidget {
  const CompleteDeliveryScreen({super.key});

  @override
  ConsumerState<CompleteDeliveryScreen> createState() =>
      _CompleteDeliveryScreenState();
}

class _CompleteDeliveryScreenState
    extends ConsumerState<CompleteDeliveryScreen> {
  final _pinController = TextEditingController();
  final _cashController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    _cashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delivery = ref.watch(deliveryProvider);
    final earningsCents = delivery.earningsCents ?? 0;
    final dollars = earningsCents ~/ 100;
    final cents = (earningsCents % 100).toString().padLeft(2, '0');

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Earnings card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryHover],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Your Earnings',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '\$$dollars.$cents',
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // PIN input
                    TextField(
                      controller: _pinController,
                      decoration: const InputDecoration(
                        labelText: 'Customer PIN',
                        prefixIcon: Icon(Icons.pin),
                        hintText: 'Enter 4-digit PIN',
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),

                    // Cash collected input
                    TextField(
                      controller: _cashController,
                      decoration: const InputDecoration(
                        labelText: 'Cash Collected (optional)',
                        prefixIcon: Icon(Icons.attach_money),
                        hintText: '0.00',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
              ),
            ),

            // Slide to complete
            Padding(
              padding: const EdgeInsets.all(20),
              child: SlideToConfirm(
                text: 'Slide to complete',
                onConfirm: () {
                  final pin = _pinController.text.trim();
                  final cashText = _cashController.text.trim();
                  final cashCents = cashText.isNotEmpty
                      ? (double.tryParse(cashText) ?? 0) * 100
                      : 0;

                  ref.read(deliveryProvider.notifier).completeDelivery(
                        pin: pin,
                        cashCollectedCents: cashCents.toInt(),
                      );
                  context.go('/');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
