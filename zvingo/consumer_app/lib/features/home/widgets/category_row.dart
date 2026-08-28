import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compact discovery filters that keep the food feed visually dominant.
class CategoryRow extends ConsumerWidget {
  const CategoryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategories = ref.watch(filtersProvider).categories;
    final categories = [
      const _Cat(Icons.restaurant, 'Restaurants'),
      const _Cat(Icons.local_grocery_store, 'Grocery'),
      const _Cat(Icons.local_convenience_store, 'Convenience'),
      const _Cat(Icons.local_bar, 'Alcohol'),
      const _Cat(Icons.local_pharmacy, 'Pharmacy'),
      const _Cat(Icons.pets, 'Pets'),
      const _Cat(Icons.card_giftcard, 'Gifts'),
    ];

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selectedCategories.contains(cat.label);
          return GestureDetector(
            onTap: () {
              ref.read(filtersProvider.notifier).toggleCategory(cat.label);
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.selectedDark
                    : AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(cat.icon,
                    color: isSelected ? AppColors.white : AppColors.textPrimary,
                    size: 15),
                const SizedBox(width: 6),
                Text(
                  cat.label,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11,
                    color: isSelected ? AppColors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _Cat {
  final IconData icon;
  final String label;
  const _Cat(this.icon, this.label);
}
