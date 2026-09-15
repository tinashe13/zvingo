import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/discovery_provider.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A plain, filter-aware restaurant list.
///
/// Drop-in body for any surface that just needs "the restaurants, ranked":
/// it honours the shared filters, shows a layout-matched skeleton while
/// loading, and offers Retry rather than an exception on failure.
class RestaurantListView extends ConsumerWidget {
  const RestaurantListView({
    super.key,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
    this.mode = RestaurantCardMode.delivery,
  });

  final EdgeInsets padding;
  final RestaurantCardMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(deliveryLocationNotifierProvider);
    final filters = ref.watch(filtersProvider);
    final query = DiscoveryQuery.from(filters, location);
    final feed = ref.watch(discoveryFeedProvider(query));

    return feed.when(
      loading: () => const ZvSkeletonList.restaurants(count: 4),
      error: (error, _) => ZvErrorState(
        error: error,
        onRetry: () => ref.invalidate(discoveryFeedProvider(query)),
      ),
      data: (stores) {
        if (stores.isEmpty) {
          return ZvEmptyState(
            icon: Icons.storefront_outlined,
            title: 'No restaurants found',
            message: filters.hasActiveFilters
                ? 'Your ${filters.activeCount} active filters are hiding everything here.'
                : 'Nothing is listed for this address yet.',
            actionLabel:
                filters.hasActiveFilters ? 'Clear filters' : 'Change filters',
            onAction: () => filters.hasActiveFilters
                ? ref.read(filtersProvider.notifier).reset()
                : context.push('/filters'),
          );
        }

        return ZvStaggeredListView.builder(
          itemCount: stores.length,
          gap: 0,
          padding: padding,
          itemBuilder: (context, index) => RestaurantCard.discovery(
            stores[index],
            mode: mode,
            onTap: () => context.push('/restaurant/${stores[index].id}'),
          ),
        );
      },
    );
  }
}
