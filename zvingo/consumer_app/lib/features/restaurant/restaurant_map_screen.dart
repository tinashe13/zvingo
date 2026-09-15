import 'dart:math' as math;

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/discovery_provider.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

/// Nearby restaurants on a map.
///
/// Tiles are CARTO basemaps built from OpenStreetMap data. Both licences
/// require the attribution to be **visible on the map**, not hidden behind an
/// info button — see [_MapAttribution].
class RestaurantMapScreen extends ConsumerStatefulWidget {
  const RestaurantMapScreen({super.key});

  @override
  ConsumerState<RestaurantMapScreen> createState() =>
      _RestaurantMapScreenState();
}

class _RestaurantMapScreenState extends ConsumerState<RestaurantMapScreen> {
  static const double _focusZoom = 15.5;
  static const double _meZoom = 15;

  final MapController _mapController = MapController();
  String? _selectedId;
  String _lastFitSignature = '';

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _fitAll(
    DeliveryLocation location,
    List<DiscoveryRestaurant> stores, {
    bool force = false,
  }) {
    final mappable = stores.where(_isMappable).toList();
    final signature = '${location.lat},${location.lng}:'
        '${mappable.map((s) => s.id).join(',')}';
    if (!force && signature == _lastFitSignature) return;
    _lastFitSignature = signature;

    final points = <LatLng>[
      LatLng(location.lat, location.lng),
      ...mappable.map(
        (s) => LatLng(s.restaurant.latitude!, s.restaurant.longitude!),
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, _meZoom);
        return;
      }
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.fromLTRB(54, 132, 54, 240),
        ),
      );
    });
  }

  void _recentreOnMe(DeliveryLocation location) {
    setState(() => _selectedId = null);
    _mapController.move(LatLng(location.lat, location.lng), _meZoom);
  }

  void _select(DiscoveryRestaurant store) {
    setState(() => _selectedId = store.id);
    _mapController.move(
      LatLng(store.restaurant.latitude!, store.restaurant.longitude!),
      math.max(_mapController.camera.zoom, _focusZoom),
    );
  }

  /// Zooming into a cluster is the only sane response to tapping one.
  void _expandCluster(_MarkerCluster cluster) {
    _mapController.move(
      cluster.centre,
      math.min(_mapController.camera.zoom + 2, 18),
    );
  }

  static bool _isMappable(DiscoveryRestaurant store) =>
      store.restaurant.latitude != null && store.restaurant.longitude != null;

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(deliveryLocationNotifierProvider);
    if (location == null) return const _NoLocationState();

    final filters = ref.watch(filtersProvider);
    final query = DiscoveryQuery.from(filters, location, radiusKm: 25);
    final feed = ref.watch(discoveryFeedProvider(query));
    final userPoint = LatLng(location.lat, location.lng);
    final stores = (feed.valueOrNull ?? const <DiscoveryRestaurant>[])
        .where(_isMappable)
        .toList();

    if (feed.hasValue) _fitAll(location, feed.value!);

    final selected =
        stores.where((store) => store.id == _selectedId).firstOrNull;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: userPoint,
                initialZoom: 14.5,
                minZoom: 3,
                maxZoom: 18,
                onTap: (_, __) => setState(() => _selectedId = null),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.zvingo.consumer',
                  maxNativeZoom: 18,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: userPoint,
                      width: 28,
                      height: 28,
                      child: const _UserLocationPin(),
                    ),
                  ],
                ),
                _ClusteredStoreLayer(
                  stores: stores,
                  selectedId: _selectedId,
                  onSelect: _select,
                  onExpandCluster: _expandCluster,
                ),
                const _MapAttribution(),
              ],
            ),
          ),

          // ── Top chrome ────────────────────────────────────────────
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
            child: Column(
              children: [
                _LocationHeader(
                  location: location,
                  onTap: () => AddressSelectionSheet.show(context),
                ),
                if (feed.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xs),
                    child: _MapNotice(
                      icon: Icons.travel_explore_rounded,
                      message: 'Finding restaurants near you…',
                    ),
                  ),
                if (feed.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: _MapNotice(
                      icon: Icons.wifi_off_rounded,
                      message: ZvErrorState.messageFor(feed.error).title,
                      actionLabel: 'Retry',
                      onAction: () =>
                          ref.invalidate(discoveryFeedProvider(query)),
                    ),
                  ),
                if (feed.hasValue && stores.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: _MapNotice(
                      icon: Icons.storefront_outlined,
                      message: 'No restaurants mapped within 25 km',
                      actionLabel: 'Change address',
                      onAction: () => AddressSelectionSheet.show(context),
                    ),
                  ),
              ],
            ),
          ),

          // ── Map controls ──────────────────────────────────────────
          Positioned(
            right: AppSpacing.md,
            bottom: 196,
            child: Column(
              children: [
                _MapControl(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Recentre on my address',
                  onPressed: () => _recentreOnMe(location),
                ),
                const SizedBox(height: AppSpacing.xs),
                _MapControl(
                  icon: Icons.zoom_out_map_rounded,
                  tooltip: 'Fit all restaurants',
                  onPressed: stores.isEmpty
                      ? null
                      : () => _fitAll(location, stores, force: true),
                ),
              ],
            ),
          ),

          // ── Bottom preview ────────────────────────────────────────
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: 104,
            child: selected != null
                ? _MapPreviewCard(
                    store: selected,
                    userPoint: userPoint,
                    onOpen: () => context.push('/restaurant/${selected.id}'),
                    onDismiss: () => setState(() => _selectedId = null),
                  )
                : stores.isEmpty
                    ? const SizedBox.shrink()
                    : _NearbyBar(
                        count: stores.length,
                        onShowList: () =>
                            _showNearbySheet(context, stores, userPoint),
                      ),
          ),
        ],
      ),
    );
  }

  void _showNearbySheet(
    BuildContext context,
    List<DiscoveryRestaurant> stores,
    LatLng userPoint,
  ) {
    final sorted = [...stores]..sort((a, b) {
        final da = a.distanceKm ?? double.infinity;
        final db = b.distanceKm ?? double.infinity;
        return da.compareTo(db);
      });
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ZvSheet(
        title: 'Nearby restaurants',
        subtitle: '${sorted.length} within 25 km, closest first',
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: ZvStaggeredListView.builder(
            itemCount: sorted.length,
            gap: 0,
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            itemBuilder: (context, index) {
              final store = sorted[index];
              return _NearbyRow(
                store: store,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _select(store);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Markers & clustering ──────────────────────────────────────────────────

/// One pin, or a bubble standing in for several pins that would overlap.
class _MarkerCluster {
  _MarkerCluster(this.centre, this.stores);

  final LatLng centre;
  final List<DiscoveryRestaurant> stores;

  bool get isSingle => stores.length == 1;
}

/// Groups markers that land in the same ~64px screen cell, so a dense
/// neighbourhood reads as one "12" bubble instead of a pile of pins.
class _ClusteredStoreLayer extends StatelessWidget {
  const _ClusteredStoreLayer({
    required this.stores,
    required this.selectedId,
    required this.onSelect,
    required this.onExpandCluster,
  });

  static const double _cellPx = 64;

  final List<DiscoveryRestaurant> stores;
  final String? selectedId;
  final void Function(DiscoveryRestaurant) onSelect;
  final void Function(_MarkerCluster) onExpandCluster;

  List<_MarkerCluster> _cluster(MapCamera camera) {
    final buckets = <String, List<DiscoveryRestaurant>>{};
    for (final store in stores) {
      final point = LatLng(
        store.restaurant.latitude!,
        store.restaurant.longitude!,
      );
      // The selected pin always stands alone — you must be able to see what
      // you just tapped.
      if (store.id == selectedId) {
        buckets['selected:${store.id}'] = [store];
        continue;
      }
      final screen = camera.latLngToScreenPoint(point);
      final key = '${(screen.x / _cellPx).floor()}:'
          '${(screen.y / _cellPx).floor()}';
      buckets.putIfAbsent(key, () => <DiscoveryRestaurant>[]).add(store);
    }

    return buckets.values.map((group) {
      if (group.length == 1) {
        final store = group.first;
        return _MarkerCluster(
          LatLng(store.restaurant.latitude!, store.restaurant.longitude!),
          group,
        );
      }
      final lat = group
              .map((s) => s.restaurant.latitude!)
              .reduce((a, b) => a + b) /
          group.length;
      final lng = group
              .map((s) => s.restaurant.longitude!)
              .reduce((a, b) => a + b) /
          group.length;
      return _MarkerCluster(LatLng(lat, lng), group);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (stores.isEmpty) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    final clusters = _cluster(camera);

    return MarkerLayer(
      markers: [
        for (final cluster in clusters)
          if (cluster.isSingle)
            Marker(
              point: cluster.centre,
              width: 48,
              height: 48,
              child: _StorePin(
                store: cluster.stores.first,
                selected: cluster.stores.first.id == selectedId,
                onTap: () => onSelect(cluster.stores.first),
              ),
            )
          else
            Marker(
              point: cluster.centre,
              width: 48,
              height: 48,
              child: _ClusterPin(
                count: cluster.stores.length,
                onTap: () => onExpandCluster(cluster),
              ),
            ),
      ],
    );
  }
}

class _StorePin extends StatelessWidget {
  const _StorePin({
    required this.store,
    required this.selected,
    required this.onTap,
  });

  final DiscoveryRestaurant store;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final closed = store.isClosed;
    return Semantics(
      button: true,
      label: '${store.name}${closed ? ', closed' : ''}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedContainer(
            duration: context.motion(AppMotion.fast),
            curve: AppMotion.standard,
            height: selected ? 44 : 34,
            width: selected ? 44 : 34,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.actionDefault
                  : closed
                      ? AppColors.neutral300
                      : AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.brandLime : AppColors.surface,
                width: selected ? 3 : 2,
              ),
              boxShadow: AppShadows.sm,
            ),
            child: Icon(
              closed ? Icons.schedule_rounded : Icons.restaurant_rounded,
              size: selected ? 22 : 17,
              color: selected
                  ? AppColors.textOnDark
                  : closed
                      ? AppColors.neutral600
                      : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClusterPin extends StatelessWidget {
  const _ClusterPin({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$count restaurants here. Tap to zoom in',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Container(
            height: 40,
            width: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.actionDefault,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2),
              boxShadow: AppShadows.sm,
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: AppTextStyles.tabular(AppTextStyles.bodyStrong)
                  .copyWith(color: AppColors.textOnDark, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserLocationPin extends StatelessWidget {
  const _UserLocationPin();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Your delivery address',
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.info,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 4),
          boxShadow: AppShadows.sm,
        ),
      ),
    );
  }
}

// ── Attribution (Finding X7) ──────────────────────────────────────────────

/// Always-visible tile attribution.
///
/// `RichAttributionWidget` hides its sources behind an info button by default
/// (`popupInitialDisplayDuration` is `Duration.zero`), which does not satisfy
/// either the OpenStreetMap ODbL attribution requirement or CARTO's basemap
/// terms. This renders the credit permanently and opens the full notice on
/// tap.
class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  static const String osm = '© OpenStreetMap contributors';
  static const String carto = '© CARTO';
  static const String osmUrl = 'https://www.openstreetmap.org/copyright';
  static const String cartoUrl = 'https://carto.com/attributions';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(
          right: AppSpacing.xxs,
          bottom: AppSpacing.xxs,
        ),
        child: GestureDetector(
          onTap: () => _showNotice(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxxs,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.86),
              borderRadius: AppRadius.smAll,
            ),
            child: Text(
              '$osm · $carto',
              style: AppTextStyles.caption.copyWith(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showNotice(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => const ZvSheet(
        title: 'Map data',
        subtitle: 'Who the map you are looking at belongs to',
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AttributionRow(
                title: 'Map data $osm',
                detail: 'Licensed under the Open Database License (ODbL).',
                url: osmUrl,
              ),
              SizedBox(height: AppSpacing.md),
              _AttributionRow(
                title: 'Basemap tiles $carto',
                detail: 'CARTO Voyager basemap, used under CARTO’s terms.',
                url: cartoUrl,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttributionRow extends StatelessWidget {
  const _AttributionRow({
    required this.title,
    required this.detail,
    required this.url,
  });

  final String title;
  final String detail;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTextStyles.bodyStrong),
        const SizedBox(height: AppSpacing.xxxs),
        Text(
          detail,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        ZvButton.tertiary(
          label: url,
          icon: Icons.copy_rounded,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Licence link copied')),
            );
          },
        ),
      ],
    );
  }
}

// ── Chrome ────────────────────────────────────────────────────────────────

class _NoLocationState extends StatelessWidget {
  const _NoLocationState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ZvEmptyState(
          icon: Icons.map_outlined,
          title: 'Choose where to explore',
          message:
              'Set a delivery address and we will pin every restaurant that delivers to it.',
          actionLabel: 'Set address',
          onAction: () => AddressSelectionSheet.show(context),
          secondaryActionLabel: 'Browse everything',
          onSecondaryAction: () => context.go('/home'),
        ),
      ),
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({required this.location, required this.onTap});

  final DeliveryLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      onTap: onTap,
      raised: true,
      padding: const EdgeInsets.all(AppSpacing.sm),
      semanticLabel:
          'Showing restaurants near ${location.displayName}. Tap to change',
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.brandGreenSurface,
              borderRadius: AppRadius.mdAll,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              size: 20,
              color: AppColors.brandGreen,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RESTAURANTS NEAR',
                  style: AppTextStyles.overline
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  location.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyStrong,
                ),
              ],
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded),
        ],
      ),
    );
  }
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppShadows.md,
      ),
      child: ZvIconButton(
        icon: icon,
        tooltip: tooltip,
        background: AppColors.surface,
        onPressed: onPressed,
      ),
    );
  }
}

class _NearbyBar extends StatelessWidget {
  const _NearbyBar({required this.count, required this.onShowList});

  final int count;
  final VoidCallback onShowList;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ZvTapScale(
        onTap: onShowList,
        semanticLabel: '$count restaurants nearby. Show the list',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.actionDefault,
            borderRadius: AppRadius.fullAll,
            boxShadow: AppShadows.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.list_rounded,
                size: 18,
                color: AppColors.textOnDark,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  '$count restaurant${count == 1 ? '' : 's'} nearby',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textOnDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      raised: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(message, style: AppTextStyles.caption)),
          if (actionLabel != null && onAction != null)
            ZvButton.tertiary(label: actionLabel!, onPressed: onAction),
        ],
      ),
    );
  }
}

class _MapPreviewCard extends StatelessWidget {
  const _MapPreviewCard({
    required this.store,
    required this.userPoint,
    required this.onOpen,
    required this.onDismiss,
  });

  final DiscoveryRestaurant store;
  final LatLng userPoint;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final restaurant = store.restaurant;
    final distanceKm = store.distanceKm ??
        const Distance().as(
          LengthUnit.Kilometer,
          userPoint,
          LatLng(restaurant.latitude!, restaurant.longitude!),
        );

    return ZvEntrance(
      key: ValueKey(store.id),
      rise: 16,
      child: ZvCard(
        raised: true,
        onTap: onOpen,
        padding: const EdgeInsets.all(AppSpacing.sm),
        semanticLabel: 'Preview of ${restaurant.name}. Tap to open',
        child: Row(
          children: [
            ZvNetworkImage(
              url: restaurant.imageUrl.isNotEmpty
                  ? restaurant.imageUrl
                  : restaurant.bannerUrl,
              height: 64,
              width: 64,
              fallbackLabel: restaurant.name,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyStrong,
                        ),
                      ),
                      if (store.isClosed)
                        ZvStatusChip(
                          label: store.availability.closedLabel,
                          icon: Icons.schedule_rounded,
                          compact: true,
                          uppercase: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  RestaurantMetaLine(
                    restaurant: restaurant,
                    distanceLabel: distanceKm < 1
                        ? '${(distanceKm * 1000).round()} m'
                        : '${distanceKm.toStringAsFixed(1)} km',
                  ),
                  if (store.headlinePromotion != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      store.headlinePromotion!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.deal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ZvIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close preview',
              background: Colors.transparent,
              foreground: AppColors.textSecondary,
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({required this.store, required this.onTap});

  final DiscoveryRestaurant store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZvTapScale(
      onTap: onTap,
      semanticLabel: 'Show ${store.name} on the map',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            ZvNetworkImage(
              url: store.restaurant.imageUrl,
              height: 44,
              width: 44,
              fallbackLabel: store.name,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyStrong,
                  ),
                  const SizedBox(height: AppSpacing.xxxs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ZvMetaItem(
                        icon: Icons.star_rounded,
                        label: store.restaurant.rating.toStringAsFixed(1),
                        tint: AppColors.rating,
                      ),
                      if (store.distanceLabel != null)
                        ZvMetaItem(
                          icon: Icons.place_outlined,
                          label: store.distanceLabel!,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
