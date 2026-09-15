import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart'
    show zvTextScale;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One browsable category. The [label] is sent verbatim as the backend's
/// `category` query parameter, so it must match `Restaurant.categories`.
class DiscoveryCategory {
  const DiscoveryCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

const List<DiscoveryCategory> kDiscoveryCategories = <DiscoveryCategory>[
  DiscoveryCategory('Pizza', Icons.local_pizza_rounded),
  DiscoveryCategory('Burgers', Icons.lunch_dining_rounded),
  DiscoveryCategory('Chicken', Icons.set_meal_rounded),
  DiscoveryCategory('Asian', Icons.ramen_dining_rounded),
  DiscoveryCategory('Healthy', Icons.eco_rounded),
  DiscoveryCategory('Coffee', Icons.local_cafe_rounded),
  DiscoveryCategory('Desserts', Icons.icecream_rounded),
  DiscoveryCategory('Grocery', Icons.local_grocery_store_rounded),
  DiscoveryCategory('Convenience', Icons.storefront_rounded),
  DiscoveryCategory('Pharmacy', Icons.local_pharmacy_rounded),
];

/// Horizontal category picker. Selecting a category narrows the whole feed —
/// tapping an active one clears it, so there is no way to get stuck.
class CategoryRow extends ConsumerWidget {
  const CategoryRow({super.key});

  /// Icon tile (56) + gap + one caption line, which grows with text scale.
  static double heightFor(BuildContext context) =>
      64 + 20 * zvTextScale(context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(filtersProvider).categories;

    return SizedBox(
      height: heightFor(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: kDiscoveryCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final category = kDiscoveryCategories[index];
          final isSelected = selected.contains(category.label);
          return ZvEntrance(
            index: index,
            child: _CategoryTile(
              category: category,
              selected: isSelected,
              onTap: () => ref
                  .read(filtersProvider.notifier)
                  .toggleCategory(category.label),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final DiscoveryCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: selected
          ? '${category.label}, selected. Tap to clear'
          : 'Show ${category.label}',
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: context.motion(AppMotion.fast),
              curve: AppMotion.standard,
              height: AppSpacing.minTapTarget + 8,
              width: AppSpacing.minTapTarget + 8,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.actionDefault
                    : AppColors.surfaceMuted,
                borderRadius: AppRadius.lgAll,
                border: Border.all(
                  color: selected ? AppColors.actionDefault : AppColors.border,
                ),
              ),
              child: Icon(
                category.icon,
                size: 24,
                color:
                    selected ? AppColors.textOnDark : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                color:
                    selected ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
