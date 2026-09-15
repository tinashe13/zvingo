import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../core/router.dart';
import '../../models/delivery_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/delivery_provider.dart';
import '../../providers/home_provider.dart';
import '../../services/location_service.dart';
import '../../widgets/widgets.dart';
import '../delivery/map_attribution.dart';

/// The dash: the screen a driver sits on between jobs.
///
/// Its job is to answer "am I earning?" at a glance and to make going online
/// the easiest thing on the screen. Everything else — zones, earnings, the map
/// — is context around that one switch.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Height the dash panel occupies at rest. The map controls and the
  /// attribution sit clear of it rather than under it.
  static const double _panelHeight = 296;

  final MapController _mapController = MapController();

  LatLng? _currentLocation;
  MapBasemap _basemap = MapBasemap.positron;
  bool _locatingFailed = false;

  @override
  void initState() {
    super.initState();
    _locate();

    Future.microtask(() {
      if (!mounted) return;
      ref.read(homeProvider.notifier).refreshEarnings();
      final auth = ref.read(authProvider);
      if (auth.isAuthenticated && auth.userId != null) {
        // Resume whatever the server thinks this driver is doing, including
        // any delivery already in progress.
        ref.read(deliveryProvider.notifier).fetchCurrentState(auth.userId!);
      }
    });

    // An offer takes over the screen the moment it lands.
    ref.listenManual<DeliveryFlowState>(deliveryProvider, (previous, next) {
      if (!mounted) return;
      if (next.deliveryState == DeliveryState.offered &&
          next.currentOffer != null &&
          previous?.currentOffer?.orderId != next.currentOffer?.orderId) {
        context.go(routeOffer);
      }
    });
  }

  /// Centre the map on the driver. Failure is reported inline rather than
  /// thrown into the void — the previous implementation returned a
  /// `Future.error` nobody awaited, so the driver just saw a map of Harare
  /// city centre with no explanation.
  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locatingFailed = true);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locatingFailed = true);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _locatingFailed = false;
      });
      _mapController.move(_currentLocation!, 15);
    } catch (e) {
      debugPrint('HomeScreen: locate failed: $e');
      if (mounted) setState(() => _locatingFailed = true);
    }
  }

  Future<void> _setOnline(bool goOnline) async {
    final notifier = ref.read(deliveryProvider.notifier);
    if (goOnline) {
      final userId = ref.read(authProvider).userId ?? '';
      await notifier.goOnline(userId);
      if (!mounted) return;
      ref.read(homeProvider.notifier).setDashing(
            ref.read(deliveryProvider).isOnline,
          );
    } else {
      final wentOffline = await notifier.goOffline();
      if (!mounted) return;
      if (wentOffline) {
        ref.read(homeProvider.notifier).setDashing(false);
      }
    }
    if (!mounted) return;
    final error = ref.read(deliveryProvider).error;
    if (error != null) {
      DriverSnack.error(context, error);
      ref.read(deliveryProvider.notifier).clearMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeProvider);
    final delivery = ref.watch(deliveryProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),

          // Top chrome: the realtime banner sits above everything, because a
          // dropped socket means missed offers and that has to be the first
          // thing a driver notices.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Only while on shift. An offline driver is *supposed* to have
                // no socket, so reporting it would be a permanent false alarm
                // — and a banner that is always up is a banner nobody reads
                // on the day it matters.
                ConnectionStatusBanner(
                  status: delivery.isOnline
                      ? delivery.connectionStatus
                      : ConnectionStatus.connected,
                  message: delivery.connectionMessage,
                  onRetry: () =>
                      ref.read(deliveryProvider.notifier).reconnect(),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    MediaQuery.of(context).padding.top + AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Column(
                    children: [
                      _ShiftSummaryBar(
                        isOnline: delivery.isOnline,
                        earnings: home.formattedEarnings,
                        trips: home.todayTrips,
                      ),
                      if (delivery.locationIssue != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _LocationWarning(
                          issue: delivery.locationIssue!,
                          onFix: () => ref
                              .read(deliveryProvider.notifier)
                              .openLocationSettings(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Map controls.
          Positioned(
            right: AppSpacing.lg,
            bottom: _panelHeight + AppSpacing.xs + bottomInset,
            child: Column(
              children: [
                FloatingMapButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Centre on me',
                  isActive: _currentLocation != null,
                  onPressed: _locate,
                ),
                const SizedBox(height: AppSpacing.md),
                // Was `onPressed: () {}`. It now cycles the basemap, which is
                // what the layers glyph has always promised: the plain map is
                // far easier to read in direct sunlight, the dark one at night.
                FloatingMapButton(
                  icon: _basemap.next.icon,
                  tooltip: 'Map style: ${_basemap.next.label}',
                  onPressed: () => setState(() => _basemap = _basemap.next),
                ),
              ],
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _DashPanel(
              isOnline: delivery.isOnline,
              isBusy: delivery.isSwitchingShift,
              hasActiveDelivery: delivery.hasActiveDelivery,
              todayEarnings: home.formattedEarnings,
              todayTrips: home.todayTrips,
              selectedZone: home.selectedZone,
              zones: home.zones,
              bottomPadding: bottomInset,
              onChanged: _setOnline,
              onSelectZone: (zone) {
                ref.read(homeProvider.notifier).selectZone(zone);
                final target = home.zones.firstWhere(
                  (z) => z.name == zone,
                  orElse: () => home.zones.first,
                );
                if (target.lat != 0 && target.lng != 0) {
                  _mapController.move(LatLng(target.lat, target.lng), 13);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? const LatLng(-17.8216, 31.0492),
        initialZoom: 14,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: _basemap.urlTemplate,
          subdomains: _basemap.subdomains,
          userAgentPackageName: MapBasemap.userAgentPackageName,
        ),
        if (_currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _currentLocation!,
                width: 44,
                height: 44,
                child: const _DriverPuck(),
              ),
            ],
          ),
        if (_locatingFailed)
          const Align(
            alignment: Alignment.center,
            child: _LocatingFailedChip(),
          ),
        // OSM data is ODbL and CARTO's terms require credit (finding X7).
        MapAttribution(
          bottomInset: _panelHeight + MediaQuery.of(context).padding.bottom,
        ),
      ],
    );
  }
}

/// The driver's own position on the map.
class _DriverPuck extends StatelessWidget {
  const _DriverPuck();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.neutral900,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.neutral0, width: 3),
        boxShadow: AppSpacing.shadowMd,
      ),
      child: const Icon(
        Icons.navigation_rounded,
        color: AppColors.brandLime,
        size: 22,
      ),
    );
  }
}

/// Small non-blocking note when the map could not find the driver.
class _LocatingFailedChip extends StatelessWidget {
  const _LocatingFailedChip();

  @override
  Widget build(BuildContext context) {
    return const StatusChip(
      label: "Can't find you on the map",
      tone: StatusTone.warning,
      icon: Icons.location_disabled_rounded,
      preserveCase: true,
    );
  }
}

/// The floating status bar: are you earning, and how much so far.
class _ShiftSummaryBar extends StatelessWidget {
  final bool isOnline;
  final String earnings;
  final int trips;

  const _ShiftSummaryBar({
    required this.isOnline,
    required this.earnings,
    required this.trips,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppSpacing.brMd,
        boxShadow: AppSpacing.shadowMdOf(context),
        // The online ring is a *positive* state signal, so it uses the success
        // token. `AppColors.primary` became near-black in §1.2, which would
        // have rendered this ring invisible against the bar's own border.
        border: Border.all(
          color: isOnline
              ? AppColors.successOf(context)
              : AppColors.borderOf(context),
          width: isOnline ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isOnline
                  ? AppColors.successSurfaceOf(context)
                  : AppColors.surfaceMutedOf(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOnline ? Icons.bolt_rounded : Icons.bedtime_outlined,
              size: 20,
              color: isOnline
                  ? AppColors.successOf(context)
                  : AppColors.neutral500,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isOnline ? "You're online" : "You're offline",
                  style: AppTextStyles.onSurface(context, AppTextStyles.h3),
                ),
                Text(
                  isOnline
                      ? 'Waiting for the next offer'
                      : 'Go online to start earning',
                  style:
                      AppTextStyles.onSurface(context, AppTextStyles.caption),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                earnings,
                style: AppTextStyles.onSurface(context, AppTextStyles.money),
              ),
              Text(
                trips == 1 ? '1 trip' : '$trips trips',
                style: AppTextStyles.onSurface(context, AppTextStyles.caption),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Explains a location problem and offers the one thing that fixes it.
class _LocationWarning extends StatelessWidget {
  final LocationStartFailure issue;
  final VoidCallback onFix;

  const _LocationWarning({required this.issue, required this.onFix});

  (String, String) get _copy => switch (issue) {
        LocationStartFailure.serviceDisabled => (
            'Location is switched off',
            'Dispatch cannot send you orders without it.',
          ),
        LocationStartFailure.denied => (
            'Zvingo needs your location',
            'Allow it so we can send you nearby orders.',
          ),
        LocationStartFailure.deniedForever => (
            'Location is blocked',
            "Open Settings and allow it, or you won't get any orders.",
          ),
        LocationStartFailure.backgroundDenied => (
            'Tracking stops when you lock the screen',
            'Set location to "Allow all the time" to keep getting offers.',
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (title, detail) = _copy;
    final tone = AppColors.warningOf(context);

    return TapScale(
      onTap: onFix,
      enforceMinTarget: false,
      semanticLabel: '$title. $detail. Opens settings.',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        decoration: BoxDecoration(
          color: AppColors.warningSurfaceOf(context),
          borderRadius: AppSpacing.brMd,
          border: Border.all(color: tone.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off_rounded, size: 20, color: tone),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyStrong.copyWith(color: tone),
                  ),
                  Text(
                    detail,
                    style: AppTextStyles.caption.copyWith(color: tone),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: tone),
          ],
        ),
      ),
    );
  }
}

/// The bottom panel: today's numbers, the zone picker, and the one switch that
/// matters.
class _DashPanel extends StatelessWidget {
  final bool isOnline;
  final bool isBusy;
  final bool hasActiveDelivery;
  final String todayEarnings;
  final int todayTrips;
  final String selectedZone;
  final List<ZoneStatus> zones;
  final double bottomPadding;
  final ValueChanged<bool> onChanged;
  final ValueChanged<String> onSelectZone;

  const _DashPanel({
    required this.isOnline,
    required this.isBusy,
    required this.hasActiveDelivery,
    required this.todayEarnings,
    required this.todayTrips,
    required this.selectedZone,
    required this.zones,
    required this.bottomPadding,
    required this.onChanged,
    required this.onSelectZone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppSpacing.brSheetTop,
        boxShadow: AppSpacing.shadowDockOf(context),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg + bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.borderOf(context),
              borderRadius: AppSpacing.brFull,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _StatTile(label: 'Today', value: todayEarnings),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(label: 'Trips', value: '$todayTrips'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(
                  label: 'Area',
                  value: selectedZone.isEmpty ? 'Nearby' : selectedZone,
                ),
              ),
            ],
          ),
          if (!isOnline && zones.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: zones.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final zone = zones[index];
                  return _ZoneChip(
                    zone: zone,
                    selected: zone.name == selectedZone,
                    onTap: () => onSelectZone(zone.name),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          // F2's toggle already confirms going offline and blocks it outright
          // while a delivery is live, with a plain-language explanation.
          OnlineOfflineToggle(
            isOnline: isOnline,
            isBusy: isBusy,
            hasActiveDelivery: hasActiveDelivery,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ZoneChip extends StatelessWidget {
  final ZoneStatus zone;
  final bool selected;
  final VoidCallback onTap;

  const _ZoneChip({
    required this.zone,
    required this.selected,
    required this.onTap,
  });

  Color _dotColor(BuildContext context) => switch (zone.status) {
        'busy' => AppColors.successOf(context),
        'moderate' => AppColors.warningOf(context),
        _ => AppColors.neutral400,
      };

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      enforceMinTarget: false,
      semanticLabel: '${zone.name}, ${zone.status}',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.actionOf(context)
              : AppColors.surfaceMutedOf(context),
          borderRadius: AppSpacing.brFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _dotColor(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              zone.name,
              style: AppTextStyles.caption.copyWith(
                color: selected
                    ? AppColors.onActionOf(context)
                    : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMutedOf(context),
        borderRadius: AppSpacing.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.onSurface(context, AppTextStyles.overline),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.onSurface(context, AppTextStyles.bodyStrong),
          ),
        ],
      ),
    );
  }
}
