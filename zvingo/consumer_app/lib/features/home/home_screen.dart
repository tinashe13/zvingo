import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/discovery_provider.dart';
import 'package:consumer_app/features/home/widgets/category_row.dart';
import 'package:consumer_app/features/home/widgets/promo_banner.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/pickup/pickup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The first ten seconds of every session.
///
/// Address → search → categories → offers → ranked restaurant sections.
/// Every section header is a [ZvSectionHeader], every list enters staggered,
/// every load is a layout-matched skeleton and every failure offers Retry.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Clears the dock's own bottom inset so the last card is reachable.
  static const double _dockInset = 118;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(deliveryLocationNotifierProvider);
    final filters = ref.watch(filtersProvider);
    final cartItems = ref.watch(cartProvider);
    final query = DiscoveryQuery.from(filters, location);
    final feed = ref.watch(discoveryFeedProvider(query));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.actionDefault,
          onRefresh: () async {
            ref.invalidate(discoveryFeedProvider(query));
            await ref.read(discoveryFeedProvider(query).future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _AddressBar(
                  address: location?.displayName,
                  cartCount: cartItems.length,
                  onAddressTap: () => AddressSelectionSheet.show(context),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchHeaderDelegate(
                  activeFilters: filters.activeCount,
                  onSearchTap: () => context.go('/search'),
                  onFilterTap: () => context.push('/filters'),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xs)),
              SliverToBoxAdapter(
                child: _FulfilmentToggle(
                  onPickup: () => openPickupScreen(context),
                ),
              ),
              if (filters.hasActiveFilters)
                SliverToBoxAdapter(
                  child: _ActiveFilterStrip(filters: filters),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              const SliverToBoxAdapter(child: CategoryRow()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              const SliverToBoxAdapter(child: PromoBanner()),
              ...feed.when(
                loading: () => const [_HomeSkeleton()],
                error: (error, _) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxl),
                      child: ZvErrorState(
                        error: error,
                        onRetry: () =>
                            ref.invalidate(discoveryFeedProvider(query)),
                      ),
                    ),
                  ),
                ],
                data: (stores) => _sections(
                  context: context,
                  ref: ref,
                  stores: stores,
                  filters: filters,
                  hasLocation: location != null,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: _dockInset)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections({
    required BuildContext context,
    required WidgetRef ref,
    required List<DiscoveryRestaurant> stores,
    required FilterState filters,
    required bool hasLocation,
  }) {
    if (stores.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            child: filters.hasActiveFilters
                ? ZvEmptyState(
                    icon: Icons.filter_alt_off_rounded,
                    title: 'Nothing matches those filters',
                    message:
                        'You have ${filters.activeCount} filters on. Clearing them usually brings back a full feed.',
                    actionLabel: 'Clear filters',
                    onAction: () => ref.read(filtersProvider.notifier).reset(),
                    secondaryActionLabel: 'Change filters',
                    onSecondaryAction: () => context.push('/filters'),
                  )
                : ZvEmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No restaurants here yet',
                    message:
                        'We have not reached this address yet. Try a different delivery address to see what is nearby.',
                    actionLabel: 'Change address',
                    onAction: () => AddressSelectionSheet.show(context),
                  ),
          ),
        ),
      ];
    }

    void open(DiscoveryRestaurant store) =>
        context.push('/restaurant/${store.id}');

    final openNow = stores.where((s) => !s.isClosed).toList();
    final pool = openNow.isEmpty ? stores : openNow;

    final nearby = [...pool.where((s) => s.distanceKm != null)]
      ..sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
    final fastest = [...pool]..sort(
        (a, b) => a.restaurant.deliveryTimeMax
            .compareTo(b.restaurant.deliveryTimeMax),
      );
    final deals =
        pool.where((s) => s.hasPromotion || s.isFreeDelivery).toList();

    // The main feed keeps the order the backend ranked or sorted it into —
    // re-sorting here would silently undo the user's chosen sort. The only
    // change is that closed stores sink to the bottom.
    final feed = <DiscoveryRestaurant>[
      ...stores.where((s) => !s.isClosed),
      ...stores.where((s) => s.isClosed),
    ];

    return [
      if (hasLocation && nearby.isNotEmpty)
        _RailSection(
          title: 'Near you',
          subtitle: 'The closest kitchens to your address',
          stores: nearby.take(10).toList(),
          onOpen: open,
          onSeeAll: () => context.go('/map'),
          seeAllLabel: 'See on map',
        )
      else if (!hasLocation)
        SliverToBoxAdapter(
          child: _SetAddressPrompt(
            onTap: () => AddressSelectionSheet.show(context),
          ),
        ),
      if (fastest.isNotEmpty)
        _RailSection(
          title: 'Fastest delivery',
          subtitle: 'Arriving in ${fastest.first.restaurant.deliveryTimeMin}'
              '–${fastest.first.restaurant.deliveryTimeMax} min',
          stores: fastest.take(10).toList(),
          onOpen: open,
          onSeeAll: () => ref
              .read(filtersProvider.notifier)
              .setSortBy(SortOption.deliveryTime),
          seeAllLabel: 'Fastest first',
        ),
      if (deals.isNotEmpty)
        _RailSection(
          title: 'Offers',
          subtitle: '${deals.length} restaurants with a deal on right now',
          stores: deals.take(10).toList(),
          onOpen: open,
          onSeeAll: () => context.push('/offers'),
          seeAllLabel: 'All offers',
        ),
      SliverToBoxAdapter(
        child: ZvSectionHeader(
          title: filters.sortBy == SortOption.recommended
              ? 'Popular near you'
              : 'All restaurants',
          subtitle: '${feed.length} '
              '${feed.length == 1 ? 'restaurant' : 'restaurants'} · '
              '${filters.sortBy.label}',
          actionLabel: 'Filters',
          onAction: () => context.push('/filters'),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        sliver: ZvStaggeredSliverList(
          itemCount: feed.length,
          gap: 0,
          itemBuilder: (context, index) => RestaurantCard.discovery(
            feed[index],
            onTap: () => open(feed[index]),
          ),
        ),
      ),
    ];
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _AddressBar extends StatelessWidget {
  const _AddressBar({
    required this.address,
    required this.cartCount,
    required this.onAddressTap,
  });

  final String? address;
  final int cartCount;
  final VoidCallback onAddressTap;

  @override
  Widget build(BuildContext context) {
    final known = address != null && address!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: ZvTapScale(
              onTap: onAddressTap,
              semanticLabel: known
                  ? 'Delivering to $address. Tap to change'
                  : 'Set your delivery address',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    known ? 'DELIVER TO' : 'WHERE TO?',
                    style: AppTextStyles.overline
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xxxs),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 18,
                        color: AppColors.brandGreen,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Flexible(
                        child: Text(
                          known ? address! : 'Set delivery address',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h3,
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          ZvIconButton(
            icon: Icons.favorite_border_rounded,
            tooltip: 'Saved restaurants',
            onPressed: () => context.push('/favourites'),
          ),
          const SizedBox(width: AppSpacing.xxs),
          ZvIconButton(
            icon: Icons.shopping_bag_outlined,
            tooltip: 'Your cart',
            badgeCount: cartCount,
            onPressed: () => context.push('/cart'),
          ),
        ],
      ),
    );
  }
}

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SearchHeaderDelegate({
    required this.activeFilters,
    required this.onSearchTap,
    required this.onFilterTap,
  });

  final int activeFilters;
  final VoidCallback onSearchTap;
  final VoidCallback onFilterTap;

  static const double _extent = 68;

  @override
  double get maxExtent => _extent;

  @override
  double get minExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: ZvSearchField(
              hint: 'Search restaurants or dishes',
              readOnly: true,
              onTap: onSearchTap,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterButton(count: activeFilters, onTap: onFilterTap),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate oldDelegate) =>
      activeFilters != oldDelegate.activeFilters;
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return ZvTapScale(
      onTap: onTap,
      semanticLabel:
          active ? '$count filters applied. Change filters' : 'Filters',
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: active ? AppColors.actionDefault : AppColors.surface,
          borderRadius: AppRadius.fullAll,
          border: Border.all(
            color: active ? AppColors.actionDefault : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 20,
              color: active ? AppColors.textOnDark : AppColors.textPrimary,
            ),
            if (active) ...[
              const SizedBox(width: AppSpacing.xxs + 2),
              Text(
                '$count',
                style: AppTextStyles.tabular(AppTextStyles.bodyStrong)
                    .copyWith(color: AppColors.textOnDark),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FulfilmentToggle extends StatelessWidget {
  const _FulfilmentToggle({required this.onPickup});

  final VoidCallback onPickup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        decoration: const BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.fullAll,
        ),
        child: Row(
          children: [
            const Expanded(
              child: _ModePill(
                label: 'Delivery',
                icon: Icons.pedal_bike_rounded,
                selected: true,
                onTap: null,
              ),
            ),
            Expanded(
              child: _ModePill(
                label: 'Pickup',
                icon: Icons.storefront_rounded,
                selected: false,
                onTap: onPickup,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: selected ? '$label, selected' : 'Switch to $label',
      child: AnimatedContainer(
        duration: context.motion(AppMotion.fast),
        curve: AppMotion.standard,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: AppRadius.fullAll,
          boxShadow: selected ? AppShadows.sm : AppShadows.none,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xxs + 2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The active filters, each individually removable. Makes "why am I seeing
/// this?" and "how do I undo it?" answerable without opening the filter sheet.
class _ActiveFilterStrip extends ConsumerWidget {
  const _ActiveFilterStrip({required this.filters});

  final FilterState filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = filters.summary;
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: chips.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (context, index) {
            if (index == chips.length) {
              return ZvTapScale(
                onTap: () => ref.read(filtersProvider.notifier).reset(),
                semanticLabel: 'Clear all filters',
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Text(
                    'Clear all',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              );
            }
            final chip = chips[index];
            return ZvTapScale(
              onTap: () => ref
                  .read(filtersProvider.notifier)
                  .clearFacet(chip.facet, chip.value),
              semanticLabel: 'Remove filter ${chip.label}',
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.actionDefault,
                  borderRadius: AppRadius.fullAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chip.label,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textOnDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs + 2),
                    const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: AppColors.textOnDark,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SetAddressPrompt extends StatelessWidget {
  const _SetAddressPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: ZvCard(
        onTap: onTap,
        color: AppColors.brandGreenSurface,
        borderColor: AppColors.brandGreenSurface,
        child: const Row(
          children: [
            Icon(
              Icons.my_location_rounded,
              color: AppColors.brandGreen,
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Set your delivery address',
                      style: AppTextStyles.bodyStrong),
                  SizedBox(height: AppSpacing.xxxs),
                  Text(
                    'We will show distance, accurate delivery times and what is open near you.',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

// ── Sections ──────────────────────────────────────────────────────────────

class _RailSection extends StatelessWidget {
  const _RailSection({
    required this.title,
    required this.stores,
    required this.onOpen,
    this.subtitle,
    this.onSeeAll,
    this.seeAllLabel = 'See all',
  });

  final String title;
  final String? subtitle;
  final List<DiscoveryRestaurant> stores;
  final void Function(DiscoveryRestaurant) onOpen;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ZvSectionHeader(
            title: title,
            subtitle: subtitle,
            actionLabel: seeAllLabel,
            onAction: onSeeAll,
          ),
          SizedBox(
            height: restaurantRailHeight(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: stores.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.listGap),
              itemBuilder: (context, index) => ZvEntrance(
                index: index,
                child: RestaurantRailCard(
                  store: stores[index],
                  onTap: () => onOpen(stores[index]),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

/// Matches the real layout: two rails then the vertical feed.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final railHeight = restaurantRailHeight(context);
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonHeader(),
          SizedBox(
            height: railHeight,
            child: const ZvSkeletonRail(count: 3, cardWidth: 176),
          ),
          const SizedBox(height: AppSpacing.md),
          const _SkeletonHeader(),
          SizedBox(
            height: railHeight,
            child: const ZvSkeletonRail(count: 3, cardWidth: 176),
          ),
          const SizedBox(height: AppSpacing.md),
          const _SkeletonHeader(),
          const ZvSkeletonList.restaurants(count: 3),
        ],
      ),
    );
  }
}

class _SkeletonHeader extends StatelessWidget {
  const _SkeletonHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: ZvShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ZvSkeletonBox(height: 18, width: 160),
            SizedBox(height: AppSpacing.xs),
            ZvSkeletonBox(height: 12, width: 110),
          ],
        ),
      ),
    );
  }
}
