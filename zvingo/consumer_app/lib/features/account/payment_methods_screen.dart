import 'package:consumer_app/common/widgets/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment methods'),
      ),
      body: AppEmptyState(
        icon: Icons.credit_card_rounded,
        title: 'No saved payment methods',
        message:
            'Add a card or mobile wallet during checkout to pay faster next time.',
        action: ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add payment method'),
        ),
      ),
    );
  }
}
