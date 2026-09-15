/// Pieces of the menu screen, split out so the screen itself stays readable.
library;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';

/// One menu item: photo, name, description, price, and a quick-add affordance.
class MenuItemRow extends StatelessWidget {
  const MenuItemRow({
    super.key,
    required this.item,
    required this.onTap,
    required this.onQuickAdd,
    required this.orderingEnabled,
    this.inCartQuantity = 0,
  });

  final MenuItem item;
  final VoidCallback onTap;

  /// Null when the item needs choices made first — then the whole row opens
  /// the sheet instead of pretending a one-tap add is possible.
  final VoidCallback? onQuickAdd;

  /// False when the restaurant is closed or the item is sold out.
  final bool orderingEnabled;

  /// How many of this item are already in the cart, shown as a badge.
  final int inCartQuantity;

  @override
  Widget build(BuildContext context) {
    final soldOut = !item.isAvailable;
    final dimmed = soldOut || !orderingEnabled;

    return ZvCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      semanticLabel: '${item.name}, ${item.basePrice.format()}'
          '${soldOut ? ', sold out' : ''}',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (inCartQuantity > 0) ...[
                          _InCartPill(quantity: inCartQuantity),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Expanded(
                          child: Text(
                            item.name,
                            style: AppTextStyles.h3.copyWith(
                              color: dimmed
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        item.description,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(item.basePrice.format(),
                            style: AppTextStyles.money),
                        if (item.hasOptions)
                          Text('Customisable',
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textSecondary)),
                        if (item.isGreatPrice)
                          const ZvBadge.deal(label: 'Great price'),
                        if (item.approvalPercent != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.thumb_up_alt_outlined,
                                  size: 13, color: AppColors.textSecondary),
                              const SizedBox(width: 3),
                              Text('${item.approvalPercent}%',
                                  style: AppTextStyles.caption),
                            ],
                          ),
                        if (soldOut)
                          const ZvStatusChip(
                            label: 'Sold out',
                            tone: ZvTone.warning,
                            icon: Icons.remove_shopping_cart_outlined,
                            compact: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 116,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: dimmed ? 0.45 : 1,
                    child: ZvNetworkImage(
                      url: item.imageUrl,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.zero,
                      fallbackLabel: item.name,
                      fallbackIcon: Icons.restaurant_menu_rounded,
                    ),
                  ),
                  if (orderingEnabled && !soldOut)
                    Positioned(
                      right: AppSpacing.xs,
                      bottom: AppSpacing.xs,
                      child: ZvIconButton(
                        icon: item.hasOptions
                            ? Icons.tune_rounded
                            : Icons.add_rounded,
                        tooltip: item.hasOptions
                            ? 'Choose options for ${item.name}'
                            : 'Add ${item.name} to cart',
                        background: AppColors.surface,
                        onPressed: onQuickAdd ?? onTap,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InCartPill extends StatelessWidget {
  const _InCartPill({required this.quantity});
  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxxs),
      decoration: const BoxDecoration(
        color: AppColors.actionDefault,
        borderRadius: AppRadius.fullAll,
      ),
      child: Text(
        '$quantity in cart',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textOnDark,
          fontWeight: FontWeight.w700,
          fontFeatures: AppTextStyles.tabularFigures,
        ),
      ),
    );
  }
}

/// The pinned header: search-within-menu plus the category rail.
class MenuNavHeaderDelegate extends SliverPersistentHeaderDelegate {
  MenuNavHeaderDelegate({
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.isSearching,
    required this.topPadding,
  });

  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final bool isSearching;
  final double topPadding;

  static const double _searchBlock = 52 + AppSpacing.sm * 2;
  static const double _categoryBlock = 44 + AppSpacing.sm;

  double get _extent =>
      topPadding +
      _searchBlock +
      (isSearching || categories.length < 2 ? 0 : _categoryBlock);

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final showCategories = !isSearching && categories.length > 1;
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: ZvSearchField(
              controller: searchController,
              hint: 'Search this menu',
              onChanged: onSearchChanged,
              onClear: onSearchCleared,
            ),
          ),
          if (showCategories)
            SizedBox(
              height: _categoryBlock,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                itemCount: categories.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final selected = category == selectedCategory;
                  return _CategoryChip(
                    label: category,
                    selected: selected,
                    onTap: () => onCategorySelected(category),
                  );
                },
              ),
            ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant MenuNavHeaderDelegate old) =>
      old.selectedCategory != selectedCategory ||
      old.isSearching != isSearching ||
      old.topPadding != topPadding ||
      !identical(old.categories, categories);
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: 'Jump to $label',
      child: AnimatedContainer(
        duration: context.motion(AppMotion.fast),
        curve: context.motionCurve(AppMotion.standard),
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.actionDefault : AppColors.surfaceMuted,
          borderRadius: AppRadius.fullAll,
        ),
        child: Text(
          label,
          style: AppTextStyles.button.copyWith(
            color: selected ? AppColors.textOnDark : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// The unmissable "this restaurant is closed" state.
class StoreClosedBanner extends StatelessWidget {
  const StoreClosedBanner({
    super.key,
    required this.availability,
    required this.restaurantName,
    required this.onBrowseOthers,
    this.onSchedule,
  });

  final RestaurantAvailability availability;
  final String restaurantName;
  final VoidCallback onBrowseOthers;

  /// Offered only when the backend says pre-orders are accepted.
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final opensAt = availability.opensAt;
    final when = opensAt == null
        ? null
        : '${_weekday(opensAt)} at '
            '${opensAt.hour.toString().padLeft(2, '0')}:'
            '${opensAt.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 20, color: AppColors.warning),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  availability.label,
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            when != null
                ? '$restaurantName reopens $when. You can look through the '
                    'menu now, but orders cannot be placed until then.'
                : '$restaurantName is not taking orders at the moment. '
                    'You can still look through the menu.',
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (onSchedule != null) ...[
                Expanded(
                  child: ZvButton.secondary(
                    label: 'Order for later',
                    icon: Icons.event_available_rounded,
                    onPressed: onSchedule,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: ZvButton.secondary(
                  label: 'Find open places',
                  icon: Icons.storefront_rounded,
                  onPressed: onBrowseOthers,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _weekday(DateTime date) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final today = DateTime.now();
    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      return 'today';
    }
    return 'on ${names[(date.weekday - 1) % 7]}';
  }
}

/// A cart bar for the case where the basket belongs to a different restaurant.
class OtherCartBar extends StatelessWidget {
  const OtherCartBar({
    super.key,
    required this.restaurantName,
    required this.total,
    required this.itemCount,
    required this.onTap,
  });

  final String restaurantName;
  final Money total;
  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvStickyFooter(
      child: ZvCard(
        onTap: onTap,
        color: AppColors.surfaceMuted,
        child: Row(
          children: [
            const Icon(Icons.shopping_bag_outlined,
                size: 20, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You have a cart from $restaurantName',
                      style: AppTextStyles.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '$itemCount item${itemCount == 1 ? '' : 's'} · '
                    '${total.format()} — adding from here starts a new cart',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Layout-matched loading state for the whole menu screen.
class MenuSkeleton extends StatelessWidget {
  const MenuSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        ZvSkeletonBox(height: 220, radius: 0),
        Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ZvSkeletonBox(height: 24, width: 200),
              SizedBox(height: AppSpacing.xs),
              ZvSkeletonBox(height: 14, width: 260),
              SizedBox(height: AppSpacing.md),
              ZvSkeletonBox(height: 52, radius: AppRadius.md),
              SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
        ZvSkeletonList.menuItems(
          count: 5,
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
      ],
    );
  }
}
