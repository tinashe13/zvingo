import 'dart:async';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/discovery_provider.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens the pickup screen.
///
/// `/pickup` is registered in `core/router.dart` as a redirect to `/map`, so
/// `context.push('/pickup')` silently lands on the map instead. Until that
/// redirect is replaced with a real route, pickup is pushed imperatively onto
/// the root navigator — [ZvScreen] pops it correctly either way.
Future<void> openPickupScreen(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/pickup'),
      builder: (_) => const PickupScreen(),
    ),
  );
}

/// Collect-in-person browsing.
///
/// Pickup changes what matters: there is **no delivery fee**, you collect the
/// order yourself, and **distance beats ETA** — so the sort defaults to
/// nearest-first and every card leads with how far the walk is.
class PickupScreen extends ConsumerStatefulWidget {
  const PickupScreen({super.key});

  @override
  ConsumerState<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends ConsumerState<PickupScreen> {
  static const List<String> _categories = <String>[
    'All',
    'Pizza',
    'Burgers',
    'Chicken',
    'Asian',
    'Coffee',
    'Grocery',
    'Convenience',
    'Pharmacy',
  ];

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _category = 'All';
  bool _openOnly = true;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  List<DiscoveryRestaurant> _visible(List<DiscoveryRestaurant> stores) {
    final needle = _query.toLowerCase();
    final filtered = stores.where((store) {
      if (_openOnly && store.isClosed) return false;
      if (_category != 'All' &&
          !store.restaurant.category
              .toLowerCase()
              .contains(_category.toLowerCase())) {
        return false;
      }
      if (needle.isEmpty) return true;
      return store.name.toLowerCase().contains(needle) ||
          store.restaurant.category.toLowerCase().contains(needle);
    }).toList();

    // Distance is the whole point of pickup. Stores without coordinates sink
    // to the bottom rather than disappearing.
    filtered.sort((a, b) {
      final da = a.distanceKm ?? double.infinity;
      final db = b.distanceKm ?? double.infinity;
      if (da == db) return b.restaurant.rating.compareTo(a.restaurant.rating);
      return da.compareTo(db);
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(deliveryLocationNotifierProvider);
    final query = DiscoveryQuery.from(
      const FilterState(sortBy: SortOption.distance),
      location,
      radiusKm: 10,
    );
    final feed = ref.watch(discoveryFeedProvider(query));

    return ZvScreen(
      title: 'Pickup',
      subtitle: 'Collect in person · no delivery fee',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: ZvSearchField(
              controller: _searchController,
              hint: 'Search pickup stores',
              onChanged: _onQueryChanged,
              onClear: () => setState(() => _query = ''),
            ),
          ),
          _PickupNotice(
            location: location,
            onSetAddress: () => AddressSelectionSheet.show(context),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: _categories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _PickupChip(
                    label: 'Open now',
                    icon: Icons.schedule_rounded,
                    selected: _openOnly,
                    onTap: () => setState(() => _openOnly = !_openOnly),
                  );
                }
                final category = _categories[index - 1];
                return _PickupChip(
                  label: category,
                  selected: _category == category,
                  onTap: () => setState(() => _category = category),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: feed.when(
              loading: () => const ZvSkeletonList.restaurants(count: 4),
              error: (error, _) => ZvErrorState(
                error: error,
                onRetry: () => ref.invalidate(discoveryFeedProvider(query)),
              ),
              data: (stores) {
                final visible = _visible(stores);
                if (visible.isEmpty) {
                  return ZvEmptyState(
                    icon: Icons.storefront_outlined,
                    title: stores.isEmpty
                        ? 'No pickup stores near you'
                        : 'Nothing matches that',
                    message: stores.isEmpty
                        ? 'We could not find a store you can collect from within 10 km of your address.'
                        : 'Try another cuisine, clear the search, or include stores that are closed right now.',
                    actionLabel: stores.isEmpty ? 'Change address' : 'Reset',
                    onAction: () {
                      if (stores.isEmpty) {
                        AddressSelectionSheet.show(context);
                        return;
                      }
                      _searchController.clear();
                      setState(() {
                        _query = '';
                        _category = 'All';
                        _openOnly = false;
                      });
                    },
                  );
                }

                return ZvStaggeredListView.builder(
                  itemCount: visible.length + 1,
                  gap: 0,
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ZvSectionHeader(
                        title: 'Closest to you',
                        subtitle: visible.length == 1
                            ? '1 store you can walk into'
                            : '${visible.length} stores you can walk into',
                      );
                    }
                    final store = visible[index - 1];
                    return RestaurantCard.discovery(
                      store,
                      mode: RestaurantCardMode.pickup,
                      onTap: () => context.push('/restaurant/${store.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// States the pickup contract up front, and fixes the one thing that breaks
/// it — a missing address means no distances.
class _PickupNotice extends StatelessWidget {
  const _PickupNotice({required this.location, required this.onSetAddress});

  final DeliveryLocation? location;
  final VoidCallback onSetAddress;

  @override
  Widget build(BuildContext context) {
    final known = location != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: ZvCard(
        onTap: known ? null : onSetAddress,
        color: known ? AppColors.brandGreenSurface : AppColors.warningSurface,
        borderColor:
            known ? AppColors.brandGreenSurface : AppColors.warningSurface,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(
              known ? Icons.savings_rounded : Icons.my_location_rounded,
              size: 20,
              color: known ? AppColors.brandGreen : AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                known
                    ? 'Pickup orders pay no delivery fee. Distances are from ${location!.displayName}.'
                    : 'Set your address to sort pickup stores by how far you have to walk.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
            if (!known) const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _PickupChip extends StatelessWidget {
  const _PickupChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: selected ? '$label, on' : 'Filter by $label',
      child: AnimatedContainer(
        duration: context.motion(AppMotion.fast),
        curve: AppMotion.standard,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
                size: 15,
                color:
                    selected ? AppColors.textOnDark : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xxs + 2),
            ],
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: selected ? AppColors.textOnDark : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
