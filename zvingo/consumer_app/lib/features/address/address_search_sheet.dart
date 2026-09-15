import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/address/geocode_provider.dart';

export 'package:consumer_app/features/address/geocode_provider.dart'
    show GeocodedAddress;

/// Search for a street address.
///
/// Suggestions come from `GET /location/geocode`, through [GeocodeService],
/// which debounces, caches and throttles — see the note on finding X3 there.
/// This sheet therefore never fires a request per keystroke, and a query the
/// user has typed before returns instantly from cache with no spinner.
class AddressSearchSheet extends ConsumerStatefulWidget {
  const AddressSearchSheet({super.key, this.initialQuery});

  final String? initialQuery;

  static Future<GeocodedAddress?> show(
    BuildContext context, {
    String? initialQuery,
  }) {
    return showModalBottomSheet<GeocodedAddress>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => AddressSearchSheet(initialQuery: initialQuery),
    );
  }

  @override
  ConsumerState<AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends ConsumerState<AddressSearchSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery ?? '');

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(geocodeSearchProvider.notifier)
            .onQueryChanged(widget.initialQuery!);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(geocodeSearchProvider);

    return ZvSheet(
      title: 'Find your address',
      subtitle: 'Start with the street or the suburb, then fine-tune the pin.',
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ZvSearchField(
              controller: _controller,
              autofocus: (widget.initialQuery ?? '').isEmpty,
              hint: 'e.g. 123 Samora Machel Ave, Harare',
              onChanged: (value) =>
                  ref.read(geocodeSearchProvider.notifier).onQueryChanged(value),
              onClear: () =>
                  ref.read(geocodeSearchProvider.notifier).onQueryChanged(''),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _buildBody(search)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(GeocodeSearchState search) {
    if (search.loading) {
      return const ZvSkeletonList.tiles(count: 5);
    }

    if (search.error != null) {
      return ZvErrorState(
        error: search.error,
        title: 'Address search is unavailable',
        onRetry: () => ref.read(geocodeSearchProvider.notifier).retry(),
      );
    }

    if (!GeocodeService.isSearchable(search.query)) {
      return const ZvEmptyState(
        icon: Icons.travel_explore_rounded,
        title: 'Type at least 3 letters',
        message: 'Search by street, building or suburb — for example '
            '"Borrowdale" or "Samora Machel".',
      );
    }

    if (search.results.isEmpty && search.hasSearched) {
      return ZvEmptyState(
        icon: Icons.location_off_outlined,
        title: 'No match for "${search.query.trim()}"',
        message: 'Try the suburb on its own, then drop the pin exactly where '
            'you want your delivery.',
        actionLabel: 'Drop a pin instead',
        onAction: () => Navigator.of(context).pop(),
      );
    }

    return ZvStaggeredListView.builder(
      itemCount: search.results.length,
      gap: AppSpacing.xs,
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      itemBuilder: (context, index) {
        final result = search.results[index];
        return ZvCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          onTap: () => Navigator.of(context).pop(result),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(
                  _iconFor(result.type),
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.primaryLine,
                      style: AppTextStyles.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (result.secondaryLine.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxxs),
                      Text(
                        result.secondaryLine,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.neutral400),
            ],
          ),
        );
      },
    );
  }

  IconData _iconFor(String type) => switch (type) {
        'house' || 'building' || 'residential' => Icons.home_outlined,
        'road' || 'street' || 'highway' => Icons.signpost_outlined,
        'suburb' || 'neighbourhood' || 'city' || 'town' =>
          Icons.location_city_outlined,
        'restaurant' || 'cafe' || 'fast_food' => Icons.storefront_outlined,
        _ => Icons.location_on_outlined,
      };
}
