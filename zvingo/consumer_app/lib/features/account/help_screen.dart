import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        title: const Text('Help', style: AppTextStyles.titleLarge),
        centerTitle: true,
      ),
      body: ListView(
        children: const [
          _FaqTile(
            question: 'How do I place an order?',
            answer:
                'Browse restaurants or pickup stores, add items to your cart, '
                'then head to checkout to place your order.',
          ),
          _FaqTile(
            question: 'How do I track my order?',
            answer:
                'Open the Orders tab and tap on an active order to see live '
                'delivery tracking.',
          ),
          _FaqTile(
            question: 'How do I contact support?',
            answer:
                'You can reach our support team from the Help section or by '
                'emailing support@zvingo.com.',
          ),
          _FaqTile(
            question: 'How do payment methods work?',
            answer: 'You can manage saved payment methods in the Account tab '
                'under Payment Methods.',
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(question, style: AppTextStyles.titleSmall),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          answer,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
