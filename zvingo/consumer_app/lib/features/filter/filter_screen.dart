import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Full-screen filter page — Article Experience 2
class FilterScreen extends ConsumerWidget {
  const FilterScreen({super.key});

  static const _dietaryOptions = [
    'Vegetarian',
    'Vegan',
    'Gluten-Free',
    'Halal',
    'Kosher',
    'Dairy-Free',
    'Nut-Free',
  ];

  static const _categoryOptions = [
    'Restaurants',
    'Grocery',
    'Convenience',
    'Alcohol',
    'Pharmacy',
    'Pizza',
    'Burgers',
    'Asian',
    'Mexican',
    'Healthy',
    'Coffee',
    'Desserts',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(filtersProvider);
    final notifier = ref.read(filtersProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text('Filters', style: AppTextStyles.titleLarge),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              notifier.reset();
            },
            child: Text(
              'Reset',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Sort By ────────────────────────────────────
          const Text('Sort By', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SortOption.values.map((option) {
              final isSelected = filters.sortBy == option;
              return _FilterChip(
                label: option.label,
                isSelected: isSelected,
                onTap: () => notifier.setSortBy(option),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── Dietary Needs ──────────────────────────────
          const Text('Dietary Needs', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _dietaryOptions.map((need) {
              final isSelected = filters.dietaryNeeds.contains(need);
              return _FilterChip(
                label: need,
                isSelected: isSelected,
                onTap: () => notifier.toggleDietaryNeed(need),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── Categories ─────────────────────────────────
          const Text('Categories', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categoryOptions.map((cat) {
              final isSelected = filters.categories.contains(cat);
              return _FilterChip(
                label: cat,
                isSelected: isSelected,
                onTap: () => notifier.toggleCategory(cat),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── Delivery Options ───────────────────────────
          const Text('Delivery', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Free Delivery Only', style: AppTextStyles.bodyMedium),
            value: filters.freeDeliveryOnly,
            onChanged: (val) => notifier.setFreeDeliveryOnly(val),
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // ── Minimum Rating ─────────────────────────────
          const Text('Minimum Rating', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [4.5, 4.0, 3.5, 3.0].map((rating) {
              final isSelected = filters.minRating == rating;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: '$rating+  ★',
                  isSelected: isSelected,
                  onTap: () => notifier.setMinRating(
                    isSelected ? null : rating,
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 40),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                filters.hasActiveFilters
                    ? 'Apply ${filters.activeCount} Filter${filters.activeCount > 1 ? 's' : ''}'
                    : 'Show Results',
                style: AppTextStyles.button,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
