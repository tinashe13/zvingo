import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/payment/payment_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final String orderId;
  final double amount;

  const PaymentScreen({super.key, required this.orderId, required this.amount});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  PaymentMethodType _selectedMethod = PaymentMethodType.ecocash;
  final _phoneController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paymentState = ref.watch(paymentProvider);

    // Navigate to order tracking when payment succeeds
    ref.listen(paymentProvider, (prev, next) {
      if (next.status == 'PAID' && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment confirmed!'),
            backgroundColor: AppColors.primary,
          ),
        );
        context.go('/order/${widget.orderId}');
      }
    });

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text('Payment', style: AppTextStyles.titleLarge),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Order Total', style: AppTextStyles.titleMedium),
                  Text(
                    '\$${widget.amount.toStringAsFixed(2)}',
                    style: AppTextStyles.titleLarge
                        .copyWith(color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            const Text('Payment Method', style: AppTextStyles.titleMedium),
            const SizedBox(height: 14),

            // EcoCash
            _PaymentMethodTile(
              icon: Icons.phone_android,
              title: 'EcoCash',
              subtitle: 'Pay with EcoCash mobile money',
              color: const Color(0xFF00A651),
              isSelected: _selectedMethod == PaymentMethodType.ecocash,
              onTap: () =>
                  setState(() => _selectedMethod = PaymentMethodType.ecocash),
            ),
            const SizedBox(height: 10),

            // OneMoney
            _PaymentMethodTile(
              icon: Icons.phone_android,
              title: 'OneMoney',
              subtitle: 'Pay with OneMoney mobile wallet',
              color: const Color(0xFF1E3A5F),
              isSelected: _selectedMethod == PaymentMethodType.onemoney,
              onTap: () =>
                  setState(() => _selectedMethod = PaymentMethodType.onemoney),
            ),
            const SizedBox(height: 10),

            // InnBucks
            _PaymentMethodTile(
              icon: Icons.phone_android,
              title: 'InnBucks',
              subtitle: 'Pay with InnBucks wallet',
              color: const Color(0xFFE5383B),
              isSelected: _selectedMethod == PaymentMethodType.innbucks,
              onTap: () =>
                  setState(() => _selectedMethod = PaymentMethodType.innbucks),
            ),

            const SizedBox(height: 24),

            // Phone number input
            const Text('Phone Number', style: AppTextStyles.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '+263 7X XXX XXXX',
                hintStyle: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textHint),
                prefixIcon: const Icon(Icons.phone, color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const Spacer(),

            // Status indicator
            if (paymentState.status == 'AWAITING_DELIVERY')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Waiting for payment confirmation...\nCheck your phone for the USSD prompt',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),

            if (paymentState.status == 'FAILED')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  paymentState.error ?? 'Payment failed. Please try again.',
                  style:
                      AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                ),
              ),

            // Pay button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_isProcessing ||
                        paymentState.status == 'AWAITING_DELIVERY')
                    ? null
                    : _handlePayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Pay \$${widget.amount.toStringAsFixed(2)}',
                        style: AppTextStyles.button.copyWith(fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePayment() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your phone number')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    await ref.read(paymentProvider.notifier).initiatePayment(
          orderId: widget.orderId,
          method: _selectedMethod,
          phone: phone,
        );

    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.titleSmall),
                  Text(subtitle, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}
