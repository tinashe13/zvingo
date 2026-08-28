import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

/// Reusable static-content screen for informational account menu items
/// (Notifications, Safety, Help, Terms, Privacy, About, etc.).
class InfoScreen extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<String> paragraphs;

  const InfoScreen({
    super.key,
    required this.title,
    this.icon,
    this.paragraphs = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (icon != null) ...[
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 36, color: AppColors.primaryHover),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: paragraphs
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        p,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
