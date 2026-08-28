import 'dart:ui';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/widgets/promo_banner.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:consumer_app/common/widgets/shimmer_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantsAsync = ref.watch(restaurantListProvider);
    final deliveryLoc = ref.watch(deliveryLocationNotifierProvider);
    final cartItems = ref.watch(cartProvider);
    final filterState = ref.watch(filtersProvider);
    final selectedShortcut = filterState.categories.isEmpty
        ? 'Hot food'
        : filterState.categories.first;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _DiscoveryHeader(
                address: deliveryLoc?.displayName ?? 'Set delivery address',
                cartCount: cartItems.length,
                onAddressTap: () => AddressSelectionSheet.show(context),
                onCartTap: () => context.push('/cart'),
                onNotificationTap: () => _showUpdatesSheet(context),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _ShortcutHeaderDelegate(
                selectedShortcut: selectedShortcut,
                onBurgersTap: () => ref
                    .read(filtersProvider.notifier)
                    .selectCategory('Burgers'),
                onPizzaTap: () =>
                    ref.read(filtersProvider.notifier).selectCategory('Pizza'),
                onHotFoodTap: () =>
                    ref.read(filtersProvider.notifier).selectCategory(null),
                onGroceryTap: () => ref
                    .read(filtersProvider.notifier)
                    .selectCategory('Grocery'),
                onRidesTap: () => _showRidesSheet(context),
              ),
            ),

            // ── Promo Banner (fetched from backend) ─────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: PromoBanner(),
              ),
            ),

            // ── Section: Fastest Near You ───────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Text('Fastest Near You',
                        style: AppTextStyles.titleLarge),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => context.go('/search'),
                      child: Text(
                        'VIEW ALL',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Horizontal fast restaurants ─────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200,
                child: restaurantsAsync.when(
                  data: (restaurants) {
                    final visible = _filterRestaurants(
                      restaurants,
                      filterState,
                    );
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: visible.length.clamp(0, 6),
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final r = visible[index];
                        return GestureDetector(
                          onTap: () => context.push('/restaurant/${r.id}'),
                          child: SizedBox(
                            width: 155,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Image
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    height: 120,
                                    width: 155,
                                    color: AppColors.primarySurface,
                                    child: r.imageUrl.isNotEmpty
                                        ? Image.network(r.imageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _horizontalPlaceholder(r.name))
                                        : _horizontalPlaceholder(r.name),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  r.name,
                                  style: AppTextStyles.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  r.category,
                                  style: AppTextStyles.bodySmall
                                      .copyWith(fontSize: 11),
                                  maxLines: 1,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time,
                                        size: 12,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 3),
                                    Text(
                                      r.deliveryTime,
                                      style: AppTextStyles.bodySmall
                                          .copyWith(fontSize: 11),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.star,
                                        size: 12, color: AppColors.rating),
                                    const SizedBox(width: 2),
                                    Text(
                                      r.rating.toStringAsFixed(1),
                                      style: AppTextStyles.bodySmall.copyWith(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const ShimmerHorizontalRow(),
                  error: (_, __) => const Center(
                    child: Text('Could not load restaurants'),
                  ),
                ),
              ),
            ),

            // ── Section: Try something new ────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child:
                    Text('Try something new', style: AppTextStyles.titleLarge),
              ),
            ),

            // ── Restaurant List (vertical) ──────────────
            restaurantsAsync.when(
              data: (restaurants) {
                final filtered = _filterRestaurants(restaurants, filterState);

                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.filter_list_off,
                                size: 48, color: AppColors.textHint),
                            const SizedBox(height: 12),
                            const Text('No restaurants match your filters',
                                style: AppTextStyles.bodyMedium),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () =>
                                  ref.read(filtersProvider.notifier).reset(),
                              child: Text('Clear Filters',
                                  style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final r = filtered[index];
                      return RestaurantCard(
                        restaurant: r,
                        onTap: () => context.push('/restaurant/${r.id}'),
                      );
                    },
                    childCount: filtered.length,
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: ShimmerRestaurantList(),
              ),
              error: (err, __) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off,
                          size: 48, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      const Text('Could not load restaurants',
                          style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 4),
                      Text('$err',
                          style: AppTextStyles.bodySmall,
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 118)),
          ],
        ),
      ),
    );
  }

  Widget _horizontalPlaceholder(String name) {
    return Container(
      color: AppColors.primarySurface,
      child: const Center(
        child: Icon(Icons.restaurant, size: 32, color: AppColors.primary),
      ),
    );
  }
}

List<Restaurant> _filterRestaurants(
  List<Restaurant> restaurants,
  FilterState filters,
) {
  var filtered = restaurants.toList();
  if (filters.freeDeliveryOnly) {
    filtered =
        filtered.where((restaurant) => restaurant.deliveryFee == 0).toList();
  }
  if (filters.minRating != null) {
    filtered = filtered
        .where((restaurant) => restaurant.rating >= filters.minRating!)
        .toList();
  }
  if (filters.categories.isNotEmpty) {
    filtered = filtered
        .where((restaurant) => filters.categories.any(
              (category) => restaurant.category
                  .toLowerCase()
                  .contains(category.toLowerCase()),
            ))
        .toList();
  }
  switch (filters.sortBy) {
    case SortOption.rating:
      filtered.sort((a, b) => b.rating.compareTo(a.rating));
      break;
    case SortOption.deliveryTime:
      filtered.sort(
        (a, b) => a.deliveryTimeMin.compareTo(b.deliveryTimeMin),
      );
      break;
    case SortOption.priceLowToHigh:
      filtered.sort((a, b) => a.deliveryFee.compareTo(b.deliveryFee));
      break;
    case SortOption.priceHighToLow:
      filtered.sort((a, b) => b.deliveryFee.compareTo(a.deliveryFee));
      break;
    default:
      break;
  }
  return filtered;
}

class _DiscoveryHeader extends StatelessWidget {
  const _DiscoveryHeader({
    required this.address,
    required this.cartCount,
    required this.onAddressTap,
    required this.onCartTap,
    required this.onNotificationTap,
  });

  final String address;
  final int cartCount;
  final VoidCallback onAddressTap;
  final VoidCallback onCartTap;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: onAddressTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DELIVER NOW',
                          style: AppTextStyles.labelSmall.copyWith(
                              fontSize: 10, color: AppColors.textTertiary)),
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.location_on_rounded,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Flexible(
                            child: Text(address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.titleSmall)),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
            _RoundAction(
              icon: Icons.notifications_none_rounded,
              badge: 0,
              onTap: onNotificationTap,
            ),
            const SizedBox(width: 8),
            _RoundAction(
              icon: Icons.shopping_bag_outlined,
              badge: cartCount,
              onTap: onCartTap,
            ),
          ]),
        ],
      ),
    );
  }
}

class _ShortcutHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ShortcutHeaderDelegate({
    required this.selectedShortcut,
    required this.onBurgersTap,
    required this.onPizzaTap,
    required this.onHotFoodTap,
    required this.onGroceryTap,
    required this.onRidesTap,
  });

  final String selectedShortcut;
  final VoidCallback onBurgersTap;
  final VoidCallback onPizzaTap;
  final VoidCallback onHotFoodTap;
  final VoidCallback onGroceryTap;
  final VoidCallback onRidesTap;

  @override
  double get maxExtent => 94;

  @override
  double get minExtent => 58;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: AppColors.white.withOpacity(overlapsContent ? 0.9 : 0.96),
          padding: EdgeInsets.fromLTRB(
            13,
            8 - (progress * 3),
            13,
            8 - (progress * 3),
          ),
          child: Row(children: [
            _ShrinkingShortcut(
              icon: Icons.lunch_dining_rounded,
              label: 'Burgers',
              selected: selectedShortcut == 'Burgers',
              progress: progress,
              onTap: onBurgersTap,
            ),
            _ShrinkingShortcut(
              icon: Icons.local_pizza_rounded,
              label: 'Pizza',
              selected: selectedShortcut == 'Pizza',
              progress: progress,
              onTap: onPizzaTap,
            ),
            _ShrinkingShortcut(
              icon: Icons.restaurant_rounded,
              label: 'Hot food',
              selected: selectedShortcut == 'Hot food',
              progress: progress,
              onTap: onHotFoodTap,
            ),
            _ShrinkingShortcut(
              icon: Icons.local_grocery_store_rounded,
              label: 'Grocery',
              selected: selectedShortcut == 'Grocery',
              progress: progress,
              onTap: onGroceryTap,
            ),
            _ShrinkingShortcut(
              icon: Icons.directions_car_filled_rounded,
              label: 'Rides',
              selected: false,
              progress: progress,
              onTap: onRidesTap,
            ),
          ]),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ShortcutHeaderDelegate oldDelegate) =>
      selectedShortcut != oldDelegate.selectedShortcut;
}

class _ShrinkingShortcut extends StatelessWidget {
  const _ShrinkingShortcut({
    required this.icon,
    required this.label,
    required this.selected,
    required this.progress,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: EdgeInsets.symmetric(vertical: 10 - (progress * 5)),
            decoration: BoxDecoration(
              color: selected ? AppColors.selectedDark : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(16 - (progress * 3)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 23 - (progress * 4),
                  color: selected ? AppColors.white : AppColors.textPrimary,
                ),
                SizedBox(height: 6 - (progress * 4)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: selected ? AppColors.white : AppColors.textPrimary,
                    fontSize: 10.5 - progress,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction(
      {required this.icon, required this.badge, required this.onTap});
  final IconData icon;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppColors.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 21),
        ),
        if (badge > 0)
          Positioned(
            right: -2,
            top: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text('$badge',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }
}

void _showUpdatesSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.accentSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.notifications_none_rounded, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('You’re all caught up', style: AppTextStyles.titleLarge),
            const SizedBox(height: 7),
            Text(
              'Live order and courier updates will appear here when they arrive.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showRidesSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.selectedDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.directions_car_filled_rounded,
                color: AppColors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Rides are coming to Zvingo',
                style: AppTextStyles.titleLarge),
            const SizedBox(height: 7),
            Text(
              'The shortcut is ready, but ride booking will stay disabled until the rides service is connected.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
