import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../models/delivery_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/floating_map_button.dart';

/// HomeScreen — driver's main screen with heatmap, FABs, bottom sheet.
/// Port of tabs/home/HomeScreen.kt.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();
    _determinePosition();

    // Refresh today's earnings from the backend
    Future.microtask(() {
      ref.read(homeProvider.notifier).refreshEarnings();
    });

    // Listen for incoming offers and auto-navigate to the offer screen
    ref.listenManual(deliveryProvider, (prev, next) {
      debugPrint('HomeScreen: deliveryProvider changed. prev=${prev?.deliveryState}, next=${next.deliveryState}, hasOffer=${next.currentOffer != null}');
      if (next.deliveryState == DeliveryState.offered &&
          next.currentOffer != null &&
          (prev == null || prev.deliveryState != DeliveryState.offered)) {
        debugPrint('HomeScreen: NAVIGATING to /delivery/offer');
        if (mounted) {
          context.go('/delivery/offer');
        }
      }
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Check if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    // 2. Get location
    try {
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentLocation!, 15);
      }
      
      // 3. Fetch backend state (active order?)
      // We need userId. For now assume auth is ready.
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated && auth.userId != null) {
        ref.read(deliveryProvider.notifier).fetchCurrentState(auth.userId!);
      }
      
    } catch (e) {
      debugPrint('Error getting location/state: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // ── Map / Heatmap Background ───
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation ?? const LatLng(-17.8216, 31.0492), // Harare default
                initialZoom: 15.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  // Use CartoDB Voyager for a cleaner, Google-like look
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.zvingo.driver',
                ),
                if (_currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentLocation!,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 6,
                              )
                            ],
                          ),
                          child: const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // ── Floating Top Bar ──────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Zvingo Driver',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          home.isDashing
                              ? "You're online"
                              : "You're offline",
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: home.isDashing
                                    ? AppColors.success
                                    : AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  // Earnings pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      home.formattedEarnings,
                      style: const TextStyle(
                        color: AppColors.primaryHover,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── FABs (right side, above bottom panel) ──────
          Positioned(
            right: 16,
            bottom: 300 + bottomPadding,
            child: Column(
              children: [
                FloatingMapButton(
                  icon: Icons.my_location,
                  onPressed: _determinePosition,
                ),
                const SizedBox(height: 12),
                FloatingMapButton(
                  icon: Icons.layers_outlined,
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // ── Bottom Sheet ──────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomPanel(
              isDashing: home.isDashing,
              todayEarnings: home.formattedEarnings,
              todayTrips: home.todayTrips,
              selectedZone: home.selectedZone,
              zones: home.zones,
              bottomPadding: bottomPadding,
              onToggleDash: () {
                final auth = ref.read(authProvider);
                ref.read(homeProvider.notifier).toggleDashing();
                if (!home.isDashing) {
                  // Going online — start SSE + GPS
                  final userId = auth.userId ?? '';
                  ref.read(deliveryProvider.notifier).goOnline(userId);
                } else {
                  // Going offline — stop SSE + GPS
                  ref.read(deliveryProvider.notifier).goOffline();
                }
              },
              onSelectZone: (zone) {
                ref.read(homeProvider.notifier).selectZone(zone);
              },
            ),
          ),
        ],
      ),
    );
  }
}



/// Bottom panel with zone selector and dash button.
class _BottomPanel extends StatelessWidget {
  final bool isDashing;
  final String todayEarnings;
  final int todayTrips;
  final String selectedZone;
  final List<ZoneStatus> zones;
  final double bottomPadding;
  final VoidCallback onToggleDash;
  final ValueChanged<String> onSelectZone;

  const _BottomPanel({
    required this.isDashing,
    required this.todayEarnings,
    required this.todayTrips,
    required this.selectedZone,
    required this.zones,
    required this.bottomPadding,
    required this.onToggleDash,
    required this.onSelectZone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.neutral300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Today's stats row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Earnings",
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                    ),
                    Text(
                      todayEarnings,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.neutral100,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$todayTrips trips',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Zone selector (horizontal scroll, when offline)
          if (!isDashing) ...[
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: zones.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final zone = zones[index];
                  final isSelected = zone.name == selectedZone;
                  return GestureDetector(
                    onTap: () => onSelectZone(zone.name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryLight
                            : AppColors.neutral100,
                        borderRadius: BorderRadius.circular(100),
                        border: isSelected
                            ? Border.all(
                                color: AppColors.primary, width: 1)
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: zone.status == 'busy'
                                  ? AppColors.success
                                  : zone.status == 'moderate'
                                      ? AppColors.warning
                                      : AppColors.neutral400,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            zone.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primaryHover
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Dash button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: onToggleDash,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDashing ? AppColors.error : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                isDashing ? 'End Dash' : 'Start Dashing',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}
