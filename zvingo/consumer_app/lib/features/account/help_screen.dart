import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/common/widgets/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help and support'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const AppSurface(
            color: AppColors.selectedDark,
            child: Row(
              children: [
                Icon(Icons.support_agent_rounded,
                    color: AppColors.accent, size: 30),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How can we help?',
                          style: TextStyle(
                              color: AppColors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 4),
                      Text('Find quick answers about orders and payments.',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _FaqTile(
            question: 'How do I place an order?',
            answer:
                'Browse restaurants or pickup stores, add items to your cart, '
                'then head to checkout to place your order.',
          ),
          const _FaqTile(
            question: 'How do I track my order?',
            answer:
                'Open the Orders tab and tap on an active order to see live '
                'delivery tracking.',
          ),
          const _FaqTile(
            question: 'How do I contact support?',
            answer:
                'You can reach our support team from the Help section or by '
                'emailing support@zvingo.com.',
          ),
          const _FaqTile(
            question: 'How do payment methods work?',
            answer: 'You can manage saved payment methods in the Account tab '
                'under Payment Methods.',
          ),
          const SizedBox(height: 16),
          AppSurface(
            child: AppIconTile(
              icon: Icons.email_outlined,
              title: 'Contact support',
              subtitle: 'support@zvingo.com',
              onTap: () {},
            ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppSurface(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(question, style: AppTextStyles.titleSmall),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(answer,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
