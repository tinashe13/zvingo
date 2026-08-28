import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/widgets/category_row.dart';
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

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Address Bar + Cart ───────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    // Zvingo logo / brand
                    Text(
                      'Zvingo',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (deliveryLoc != null) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: GestureDetector(
                          onTap: () => AddressSelectionSheet.show(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on_outlined,
                                    size: 16, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    deliveryLoc.displayName,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Cart button with badge
                    GestureDetector(
                      onTap: () => context.push('/cart'),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.shopping_bag_outlined,
                                size: 22, color: AppColors.textPrimary),
                          ),
                          if (cartItems.isNotEmpty)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                child: Text(
                                  '${cartItems.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Search Bar ──────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: GestureDetector(
                  onTap: () {
                    context.push('/search');
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(Icons.search,
                            color: AppColors.primary.withOpacity(0.7),
                            size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'What are you craving?',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Delivery Address Row ────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => AddressSelectionSheet.show(context),
                        child: Row(
                          children: [
                            const Icon(Icons.delivery_dining_outlined,
                                size: 18, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              'Delivery to ',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                            Flexible(
                              child: Text(
                                deliveryLoc?.displayName ?? 'Set Address',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down,
                                size: 18, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.push('/filters'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: filterState.hasActiveFilters
                              ? AppColors.primarySurface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: filterState.hasActiveFilters
                              ? Border.all(
                                  color: AppColors.primary.withOpacity(0.3))
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.tune,
                                size: 16,
                                color: filterState.hasActiveFilters
                                    ? AppColors.primary
                                    : AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              filterState.hasActiveFilters
                                  ? 'Filters (${filterState.activeCount})'
                                  : 'Filters',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: filterState.hasActiveFilters
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                fontWeight: filterState.hasActiveFilters
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Category Row ────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 4),
                child: CategoryRow(),
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
                      onTap: () => context.push('/search'),
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
                  data: (restaurants) => ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: restaurants.length.clamp(0, 6),
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final r = restaurants[index];
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
                                      size: 12, color: AppColors.textSecondary),
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
                  ),
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
                // Apply client-side filters
                var filtered = restaurants.toList();
                if (filterState.freeDeliveryOnly) {
                  filtered = filtered.where((r) => r.deliveryFee == 0).toList();
                }
                if (filterState.minRating != null) {
                  filtered = filtered
                      .where((r) => r.rating >= filterState.minRating!)
                      .toList();
                }
                if (filterState.categories.isNotEmpty) {
                  filtered = filtered
                      .where((r) => filterState.categories.any((c) =>
                          r.category.toLowerCase().contains(c.toLowerCase())))
                      .toList();
                }
                // Sort
                switch (filterState.sortBy) {
                  case SortOption.rating:
                    filtered.sort((a, b) => b.rating.compareTo(a.rating));
                    break;
                  case SortOption.deliveryTime:
                    filtered.sort((a, b) =>
                        a.deliveryTimeMin.compareTo(b.deliveryTimeMin));
                    break;
                  case SortOption.priceLowToHigh:
                    filtered
                        .sort((a, b) => a.deliveryFee.compareTo(b.deliveryFee));
                    break;
                  case SortOption.priceHighToLow:
                    filtered
                        .sort((a, b) => b.deliveryFee.compareTo(a.deliveryFee));
                    break;
                  default:
                    break;
                }

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

            const SliverToBoxAdapter(child: SizedBox(height: 16)),
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
