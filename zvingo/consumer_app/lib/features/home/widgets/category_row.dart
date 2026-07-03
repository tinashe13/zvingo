import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Horizontal scrolling category row with circular icons
class CategoryRow extends ConsumerWidget {
  const CategoryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategories = ref.watch(filtersProvider).categories;
    final categories = [
      _Cat(Icons.restaurant, 'Restaurants'),
      _Cat(Icons.local_grocery_store, 'Grocery'),
      _Cat(Icons.local_convenience_store, 'Convenience'),
      _Cat(Icons.local_bar, 'Alcohol'),
      _Cat(Icons.local_pharmacy, 'Pharmacy'),
      _Cat(Icons.pets, 'Pets'),
      _Cat(Icons.card_giftcard, 'Gifts'),
    ];

    return SizedBox(
      height: 95,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selectedCategories.contains(cat.label);
          return GestureDetector(
            onTap: () {
              ref.read(filtersProvider.notifier).toggleCategory(cat.label);
            },
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.15)
                          : AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(18),
                      border: isSelected
                          ? Border.all(color: AppColors.primary, width: 2)
                          : null,
                    ),
                    child: Icon(cat.icon,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.primary.withOpacity(0.7),
                        size: 28),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cat.label,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontSize: 11,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
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
