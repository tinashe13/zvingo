import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/widgets/category_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Discovery filters.
///
/// Every control writes straight to `filtersProvider`, which the feed
/// providers are keyed on — so a toggle re-ranks the feed underneath without
/// tearing the screen down. "Apply" simply closes; nothing is staged.
class FilterScreen extends ConsumerWidget {
  const FilterScreen({super.key});

  static const List<String> _dietaryOptions = <String>[
    'Vegetarian',
    'Vegan',
    'Gluten-Free',
    'Halal',
    'Kosher',
    'Dairy-Free',
    'Nut-Free',
  ];

  static const List<double> _ratingOptions = <double>[4.5, 4.0, 3.5, 3.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(filtersProvider);
    final notifier = ref.read(filtersProvider.notifier);
    final active = filters.activeCount;

    return ZvScreen(
      title: 'Filters',
      subtitle: active == 0
          ? 'Showing everything near you'
          : '$active ${active == 1 ? 'filter' : 'filters'} applied',
      backTooltip: 'Close filters',
      actions: [
        ZvButton.tertiary(
          label: 'Reset',
          onPressed: active == 0 ? null : notifier.reset,
        ),
      ],
      footer: ZvStickyFooter(
        child: ZvButton.primary(
          label: active == 0
              ? 'Show results'
              : 'Show results · $active ${active == 1 ? 'filter' : 'filters'}',
          onPressed: () => context.pop(),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: [
          if (active > 0) ...[
            _ActiveSummary(filters: filters, notifier: notifier),
            const SizedBox(height: AppSpacing.xl),
          ],

          // ── Availability ────────────────────────────────────────────
          const _GroupTitle('Availability'),
          _SwitchRow(
            title: 'Open now',
            subtitle: 'Hide anything that cannot take an order right now',
            icon: Icons.schedule_rounded,
            value: filters.openNow,
            onChanged: notifier.setOpenNow,
          ),
          _SwitchRow(
            title: 'Has an offer',
            subtitle: 'Only restaurants running a promotion',
            icon: Icons.local_offer_rounded,
            value: filters.offersOnly,
            onChanged: notifier.setOffersOnly,
          ),
          _SwitchRow(
            title: 'Free delivery',
            subtitle: 'No delivery fee on this order',
            icon: Icons.pedal_bike_rounded,
            value: filters.freeDeliveryOnly,
            onChanged: notifier.setFreeDeliveryOnly,
          ),

          const _GroupTitle('Sort by'),
          _ChipWrap(
            children: [
              for (final option in SortOption.values)
                _FilterChip(
                  label: option.label,
                  selected: filters.sortBy == option,
                  onTap: () => notifier.setSortBy(option),
                ),
            ],
          ),

          const _GroupTitle('Delivery time'),
          _ChipWrap(
            children: [
              for (final window in DeliveryWindow.values)
                _FilterChip(
                  label: window.label,
                  selected: filters.maxDeliveryMinutes == window.maxMinutes,
                  onTap: () => notifier.setMaxDeliveryMinutes(
                    filters.maxDeliveryMinutes == window.maxMinutes
                        ? null
                        : window.maxMinutes,
                  ),
                ),
            ],
          ),

          const _GroupTitle('Price'),
          _ChipWrap(
            children: [
              for (var band = 1; band <= 4; band++)
                _FilterChip(
                  label: '\$' * band,
                  selected: filters.priceBand == band,
                  onTap: () => notifier
                      .setPriceBand(filters.priceBand == band ? null : band),
                ),
            ],
          ),

          const _GroupTitle('Rating'),
          _ChipWrap(
            children: [
              for (final rating in _ratingOptions)
                _FilterChip(
                  label: '${rating.toStringAsFixed(1)}+',
                  icon: Icons.star_rounded,
                  iconTint: AppColors.rating,
                  selected: filters.minRating == rating,
                  onTap: () => notifier
                      .setMinRating(filters.minRating == rating ? null : rating),
                ),
            ],
          ),

          const _GroupTitle('Cuisine'),
          _ChipWrap(
            children: [
              for (final category in kDiscoveryCategories)
                _FilterChip(
                  label: category.label,
                  icon: category.icon,
                  selected: filters.categories.contains(category.label),
                  onTap: () => notifier.toggleCategory(category.label),
                ),
            ],
          ),

          const _GroupTitle('Dietary'),
          _ChipWrap(
            children: [
              for (final need in _dietaryOptions)
                _FilterChip(
                  label: need,
                  selected: filters.dietaryNeeds.contains(need),
                  onTap: () => notifier.toggleDietaryNeed(need),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveSummary extends StatelessWidget {
  const _ActiveSummary({required this.filters, required this.notifier});

  final FilterState filters;
  final Filters notifier;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Applied filters', style: AppTextStyles.bodyStrong),
              ),
              ZvButton.tertiary(label: 'Clear all', onPressed: notifier.reset),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final chip in filters.summary)
                _FilterChip(
                  label: chip.label,
                  selected: true,
                  trailingIcon: Icons.close_rounded,
                  onTap: () => notifier.clearFacet(chip.facet, chip.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xl,
        bottom: AppSpacing.sm,
      ),
      child: Text(title, style: AppTextStyles.h3),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: children,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: AppRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.bodyStrong),
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconTint,
    this.trailingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? iconTint;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? AppColors.textOnDark : AppColors.textPrimary;
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: selected ? '$label, selected' : label,
      child: AnimatedContainer(
        duration: context.motion(AppMotion.fast),
        curve: AppMotion.standard,
        height: AppSpacing.minTapTarget,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.actionDefault : AppColors.surface,
          borderRadius: AppRadius.fullAll,
          border: Border.all(
            color: selected ? AppColors.actionDefault : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? ink : (iconTint ?? AppColors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.xxs + 2),
            ],
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: ink,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: AppSpacing.xxs + 2),
              Icon(trailingIcon, size: 15, color: ink),
            ],
          ],
        ),
      ),
    );
  }
}
