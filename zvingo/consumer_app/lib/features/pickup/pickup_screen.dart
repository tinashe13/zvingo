import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:flutter/material.dart';

class PickupScreen extends StatelessWidget {
  const PickupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text('Pickup', style: AppTextStyles.headlineMedium),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          color: AppColors.textHint, size: 22),
                      const SizedBox(width: 10),
                      Text('Search pickup stores',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textHint)),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            // Category filters
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _chip('All', true),
                    _chip('Food', false),
                    _chip('Groceries', false),
                    _chip('Convenience', false),
                    _chip('Pharmacy', false),
                  ],
                ),
              ),
            ),
            // Placeholder
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_walk,
                        size: 64, color: AppColors.primary.withOpacity(0.3)),
                    const SizedBox(height: 12),
                    const Text('Pickup stores near you',
                        style: AppTextStyles.titleMedium),
                    const SizedBox(height: 4),
                    const Text('Coming soon', style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {},
        backgroundColor: AppColors.background,
        selectedColor: AppColors.primarySurface,
        labelStyle: TextStyle(
          color: selected ? AppColors.primary : AppColors.textPrimary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide.none,
        ),
      ),
    );
  }
}
