import 'package:consumer_app/common/widgets/app_ui.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_selection_sheet.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

class RestaurantMapScreen extends ConsumerStatefulWidget {
  const RestaurantMapScreen({super.key});

  @override
  ConsumerState<RestaurantMapScreen> createState() =>
      _RestaurantMapScreenState();
}

class _RestaurantMapScreenState extends ConsumerState<RestaurantMapScreen> {
  final MapController _mapController = MapController();
  String? _selectedRestaurantId;
  String _lastFitSignature = '';

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _fitRestaurants(
    DeliveryLocation location,
    List<Restaurant> restaurants, {
    bool force = false,
  }) {
    final mappable = restaurants
        .where((restaurant) =>
            restaurant.latitude != null && restaurant.longitude != null)
        .toList();
    final signature = '${location.lat},${location.lng}:'
        '${mappable.map((restaurant) => restaurant.id).join(',')}';
    if (!force && signature == _lastFitSignature) return;
    _lastFitSignature = signature;

    final points = <LatLng>[
      LatLng(location.lat, location.lng),
      ...mappable.map(
        (restaurant) => LatLng(
          restaurant.latitude!,
          restaurant.longitude!,
        ),
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 14.5);
        return;
      }
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.fromLTRB(54, 128, 54, 230),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(deliveryLocationNotifierProvider);
    if (location == null) {
      return Scaffold(
        body: SafeArea(
          child: AppEmptyState(
            icon: Icons.map_outlined,
            title: 'Choose where to explore',
            message:
                'Set a delivery location to see nearby restaurants pinned on the map.',
            action: ElevatedButton(
              onPressed: () => AddressSelectionSheet.show(context),
              child: const Text('Set location'),
            ),
          ),
        ),
      );
    }

    final locationPoint = (lat: location.lat, lng: location.lng);
    final restaurantsAsync = ref.watch(
      nearbyRestaurantsProvider(locationPoint),
    );
    final userPoint = LatLng(location.lat, location.lng);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: restaurantsAsync.when(
              loading: () => _MapCanvas(
                mapController: _mapController,
                initialCenter: userPoint,
                userPoint: userPoint,
                restaurants: const [],
                selectedRestaurantId: null,
                onRestaurantTap: (_) {},
                onMapTap: () {},
              ),
              error: (_, __) => _MapCanvas(
                mapController: _mapController,
                initialCenter: userPoint,
                userPoint: userPoint,
                restaurants: const [],
                selectedRestaurantId: null,
                onRestaurantTap: (_) {},
                onMapTap: () {},
              ),
              data: (restaurants) {
                _fitRestaurants(location, restaurants);
                return _MapCanvas(
                  mapController: _mapController,
                  initialCenter: userPoint,
                  userPoint: userPoint,
                  restaurants: restaurants,
                  selectedRestaurantId: _selectedRestaurantId,
                  onRestaurantTap: (id) =>
                      setState(() => _selectedRestaurantId = id),
                  onMapTap: () => setState(() => _selectedRestaurantId = null),
                );
              },
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.paddingOf(context).top + 12,
            child: _LocationHeader(
              location: location,
              onTap: () => AddressSelectionSheet.show(context),
            ),
          ),
          Positioned(
            right: 16,
            top: MediaQuery.paddingOf(context).top + 88,
            child: Material(
              color: AppColors.white.withOpacity(0.9),
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(
                tooltip: 'Recenter map',
                onPressed: () {
                  restaurantsAsync.whenData(
                    (restaurants) =>
                        _fitRestaurants(location, restaurants, force: true),
                  );
                },
                icon: const Icon(Icons.my_location_rounded),
              ),
            ),
          ),
          restaurantsAsync.when(
            loading: () => const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
            error: (_, __) => Positioned(
              left: 28,
              right: 28,
              top: MediaQuery.paddingOf(context).top + 98,
              child: _MapMessage(
                icon: Icons.wifi_off_rounded,
                message: 'Could not load nearby restaurants',
                actionLabel: 'Retry',
                onAction: () =>
                    ref.invalidate(nearbyRestaurantsProvider(locationPoint)),
              ),
            ),
            data: (restaurants) {
              final mappable = restaurants
                  .where((restaurant) =>
                      restaurant.latitude != null &&
                      restaurant.longitude != null)
                  .toList();
              if (mappable.isEmpty) {
                return Positioned(
                  left: 28,
                  right: 28,
                  top: MediaQuery.sizeOf(context).height * 0.42,
                  child: const _MapMessage(
                    icon: Icons.restaurant_menu_rounded,
                    message: 'No restaurants found within 25 km',
                  ),
                );
              }

              final selected = mappable
                  .where((restaurant) => restaurant.id == _selectedRestaurantId)
                  .firstOrNull;
              return Positioned(
                left: 16,
                right: 16,
                bottom: 104,
                child: selected == null
                    ? _NearbyCount(count: mappable.length)
                    : _RestaurantMapCard(
                        restaurant: selected,
                        userPoint: userPoint,
                        onTap: () => context.push('/restaurant/${selected.id}'),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MapCanvas extends StatelessWidget {
  const _MapCanvas({
    required this.mapController,
    required this.initialCenter,
    required this.userPoint,
    required this.restaurants,
    required this.selectedRestaurantId,
    required this.onRestaurantTap,
    required this.onMapTap,
  });

  final MapController mapController;
  final LatLng initialCenter;
  final LatLng userPoint;
  final List<Restaurant> restaurants;
  final String? selectedRestaurantId;
  final ValueChanged<String> onRestaurantTap;
  final VoidCallback onMapTap;

  @override
  Widget build(BuildContext context) => FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: initialCenter,
          initialZoom: 14.5,
          onTap: (_, __) => onMapTap(),
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
            subdomains: const ['a', 'b', 'c', 'd'],
            userAgentPackageName: 'com.zvingo.consumer',
          ),
          MarkerLayer(
            markers: [
              ...restaurants.where((restaurant) {
                return restaurant.latitude != null &&
                    restaurant.longitude != null;
              }).map((restaurant) {
                final selected = restaurant.id == selectedRestaurantId;
                return Marker(
                  point: LatLng(
                    restaurant.latitude!,
                    restaurant.longitude!,
                  ),
                  width: selected ? 54 : 44,
                  height: selected ? 54 : 44,
                  child: GestureDetector(
                    onTap: () => onRestaurantTap(restaurant.id),
                    child: _RestaurantPin(selected: selected),
                  ),
                );
              }),
              Marker(
                point: userPoint,
                width: 34,
                height: 34,
                child: const _UserLocationPin(),
              ),
            ],
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
              TextSourceAttribution('CARTO'),
            ],
          ),
        ],
      );
}

class _RestaurantPin extends StatelessWidget {
  const _RestaurantPin({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? AppColors.selectedDark : AppColors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.white,
            width: selected ? 3 : 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x35101211),
              blurRadius: 11,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.restaurant_rounded,
          size: selected ? 25 : 21,
          color: selected ? AppColors.white : AppColors.textPrimary,
        ),
      );
}

class _UserLocationPin extends StatelessWidget {
  const _UserLocationPin();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.info,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.white, width: 4),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 9),
          ],
        ),
      );
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({required this.location, required this.onTap});
  final DeliveryLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        shadowColor: const Color(0x26000000),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.location_on_rounded, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RESTAURANTS NEAR',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 9,
                          letterSpacing: 1,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      location.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ]),
          ),
        ),
      );
}

class _NearbyCount extends StatelessWidget {
  const _NearbyCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.selectedDark.withOpacity(0.92),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(color: Color(0x2B000000), blurRadius: 14),
            ],
          ),
          child: Text(
            '$count restaurant${count == 1 ? '' : 's'} nearby · Tap a pin',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.white),
          ),
        ),
      );
}

class _RestaurantMapCard extends StatelessWidget {
  const _RestaurantMapCard({
    required this.restaurant,
    required this.userPoint,
    required this.onTap,
  });

  final Restaurant restaurant;
  final LatLng userPoint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final restaurantPoint = LatLng(
      restaurant.latitude!,
      restaurant.longitude!,
    );
    final distance = const Distance().as(
      LengthUnit.Kilometer,
      userPoint,
      restaurantPoint,
    );
    return AppSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      color: AppColors.white.withOpacity(0.94),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            width: 62,
            height: 62,
            child: restaurant.imageUrl.isEmpty
                ? Container(
                    color: AppColors.accentSurface,
                    child: const Icon(Icons.restaurant_rounded),
                  )
                : Image.network(
                    restaurant.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.accentSurface,
                      child: const Icon(Icons.restaurant_rounded),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                restaurant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${restaurant.deliveryTime} · ${distance.toStringAsFixed(1)} km',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '★ ${restaurant.rating.toStringAsFixed(1)} · '
                '${restaurant.deliveryFee == 0 ? 'Free delivery' : '\$${restaurant.deliveryFee.toStringAsFixed(2)} delivery'}',
                style: AppTextStyles.labelSmall,
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({
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
  Widget build(BuildContext context) => AppSurface(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppTextStyles.bodySmall)),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ]),
      );
}
