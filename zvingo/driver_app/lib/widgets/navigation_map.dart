import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import '../core/app_colors.dart';

class _RouteStep {
  final String instruction;
  final double distance; // metres
  final double duration; // seconds
  final int type;
  final int waypointStart;
  final int waypointEnd;

  const _RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.type,
    required this.waypointStart,
    required this.waypointEnd,
  });
}

/// Driving-mode navigation map.
///
/// Routes from the driver's live GPS position to [destination].
/// Optionally shows a [secondaryLocation] marker (e.g. the merchant store
/// while the driver is heading to the customer, or vice versa).
///
/// Features:
/// - Map renders immediately at [destination] while GPS is acquiring
/// - Route polyline from driver → [destination] via OpenRouteService (free)
/// - Turn-by-turn instruction banner with maneuver icon + distance to next turn
/// - Distance & ETA chip
/// - Auto-recalculates route when driver drifts >80 m off the current route
/// - Map heading-lock: rotates to keep direction of travel at the top
/// - Re-centre button when driver pans the map manually
class NavigationMap extends StatefulWidget {
  final LatLng destination;
  final String destinationLabel;
  final LatLng? secondaryLocation;
  final String? secondaryLabel;

  const NavigationMap({
    super.key,
    required this.destination,
    required this.destinationLabel,
    this.secondaryLocation,
    this.secondaryLabel,
  });

  @override
  State<NavigationMap> createState() => _NavigationMapState();
}

class _NavigationMapState extends State<NavigationMap> {
  final MapController _mapController = MapController();
  final Dio _dio = Dio();
  StreamSubscription<Position>? _positionSub;

  Position? _currentPosition;
  bool _isFollowing = true;
  bool _isLoadingRoute = false;

  List<LatLng> _routePoints = [];
  List<_RouteStep> _steps = [];
  int _currentStepIndex = 0;
  double _totalDistanceMeters = 0;
  double _totalDurationSecs = 0;

  static const double _recalcThresholdMeters = 80.0;
  static const String _orsApiKey = '5b3ce3597851110001cf6248a8de9b06';

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _dio.close(force: false);
    super.dispose();
  }

  // ── Location ─────────────────────────────────────────────────────────────

  void _startLocationUpdates() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // update every 5 m
      ),
    ).listen(_onPositionUpdate);
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    final isFirstFix = _currentPosition == null;
    setState(() => _currentPosition = pos);

    final driverLatLng = LatLng(pos.latitude, pos.longitude);

    if (_isFollowing) {
      _mapController.move(driverLatLng, 17);
      // Rotate map so direction of travel is always "up"
      if (pos.speed > 1) _mapController.rotate(-pos.heading);
    }

    if (isFirstFix) {
      _fetchRoute(driverLatLng);
      return;
    }

    // Recalculate when driver is off-route
    if (_routePoints.isNotEmpty &&
        _distanceToRoute(driverLatLng) > _recalcThresholdMeters) {
      _fetchRoute(driverLatLng);
      return;
    }

    _updateCurrentStep(driverLatLng);
  }

  // ── Routing ───────────────────────────────────────────────────────────────

  double _distanceToRoute(LatLng point) {
    const calc = Distance();
    var min = double.infinity;
    for (final p in _routePoints) {
      final d = calc.as(LengthUnit.Meter, point, p);
      if (d < min) min = d;
    }
    return min;
  }

  void _updateCurrentStep(LatLng pos) {
    if (_steps.isEmpty || _routePoints.isEmpty) return;
    const calc = Distance();
    int closestIdx = 0;
    double minDist = double.infinity;
    for (int i = 0; i < _routePoints.length; i++) {
      final d = calc.as(LengthUnit.Meter, pos, _routePoints[i]);
      if (d < minDist) {
        minDist = d;
        closestIdx = i;
      }
    }
    for (int i = 0; i < _steps.length; i++) {
      if (closestIdx >= _steps[i].waypointStart &&
          closestIdx <= _steps[i].waypointEnd) {
        if (_currentStepIndex != i && mounted) {
          setState(() => _currentStepIndex = i);
        }
        return;
      }
    }
  }

  Future<void> _fetchRoute(LatLng from) async {
    if (_isLoadingRoute) return;
    if (mounted) setState(() => _isLoadingRoute = true);

    try {
      final url = 'https://api.openrouteservice.org/v2/directions/driving-car'
          '?api_key=$_orsApiKey'
          '&start=${from.longitude},${from.latitude}'
          '&end=${widget.destination.longitude},${widget.destination.latitude}';

      final response = await _dio.get(url);
      if (response.statusCode != 200 || !mounted) return;

      final feature = response.data['features'][0];
      final coords = feature['geometry']['coordinates'] as List;
      final props = feature['properties'];
      final summary = props['summary'];
      final segments = props['segments'] as List;

      final points = coords
          .map<LatLng>(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final steps = <_RouteStep>[];
      if (segments.isNotEmpty) {
        for (final s in segments[0]['steps'] as List) {
          steps.add(_RouteStep(
            instruction: s['instruction'] as String,
            distance: (s['distance'] as num).toDouble(),
            duration: (s['duration'] as num).toDouble(),
            type: s['type'] as int,
            waypointStart: (s['way_points'] as List)[0] as int,
            waypointEnd: (s['way_points'] as List)[1] as int,
          ));
        }
      }

      setState(() {
        _routePoints = points;
        _steps = steps;
        _currentStepIndex = 0;
        _totalDistanceMeters = (summary['distance'] as num).toDouble();
        _totalDurationSecs = (summary['duration'] as num).toDouble();
        _isLoadingRoute = false;
      });
    } catch (e) {
      debugPrint('Route fetch error: $e');
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  IconData _stepIcon(int type) {
    switch (type) {
      case 0:
        return Icons.turn_left;
      case 1:
        return Icons.turn_right;
      case 2:
        return Icons.turn_sharp_left;
      case 3:
        return Icons.turn_sharp_right;
      case 4:
        return Icons.turn_slight_left;
      case 5:
        return Icons.turn_slight_right;
      case 6:
        return Icons.straight;
      case 7:
      case 8:
        return Icons.roundabout_left;
      case 9:
        return Icons.u_turn_right;
      case 10:
        return Icons.location_on;
      case 11:
        return Icons.navigation;
      case 12:
        return Icons.fork_left;
      case 13:
        return Icons.fork_right;
      default:
        return Icons.navigation;
    }
  }

  String _fmtDist(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.round()} m';
  }

  String _fmtEta(double secs) {
    final mins = (secs / 60).round();
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  void _recenter() {
    if (_currentPosition == null) return;
    setState(() => _isFollowing = true);
    _mapController.move(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      17,
    );
    if (_currentPosition!.speed > 1) {
      _mapController.rotate(-_currentPosition!.heading);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Show map at destination immediately while GPS is acquiring.
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : widget.destination;

    final currentStep =
        (_steps.isNotEmpty && _currentStepIndex < _steps.length)
            ? _steps[_currentStepIndex]
            : null;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15.0,
        onPositionChanged: (_, hasGesture) {
          if (hasGesture && mounted) setState(() => _isFollowing = false);
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        // ── Basemap ───────────────────────────────────────────────────────
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.zvingo.driver',
        ),

        // ── Route polyline ────────────────────────────────────────────────
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 6,
                color: AppColors.primary,
              ),
            ],
          ),

        // ── Markers ───────────────────────────────────────────────────────
        MarkerLayer(
          markers: [
            // Secondary (context) location — e.g. merchant when going to customer
            if (widget.secondaryLocation != null)
              Marker(
                point: widget.secondaryLocation!,
                width: 80,
                height: 56,
                rotate: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ],
                      ),
                      child: Text(
                        widget.secondaryLabel ?? '',
                        style: const TextStyle(
                            fontSize: 9, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.store, color: Colors.orange, size: 24),
                  ],
                ),
              ),

            // Destination marker
            Marker(
              point: widget.destination,
              width: 80,
              height: 64,
              rotate: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6)
                      ],
                    ),
                    child: Text(
                      widget.destinationLabel,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.location_on, color: Colors.red, size: 32),
                ],
              ),
            ),

            // Driver arrow (shown once GPS is acquired)
            if (_currentPosition != null)
              Marker(
                point: LatLng(
                    _currentPosition!.latitude, _currentPosition!.longitude),
                width: 52,
                height: 52,
                rotate: true, // stays upright; map rotation aligns "up" = heading
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(10),
                  child: const Icon(Icons.navigation,
                      color: Colors.white, size: 26),
                ),
              ),
          ],
        ),

        // ── Top overlay: instruction banner / locating / calculating ──────
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _buildTopBanner(currentStep),
        ),

        // ── Bottom-left: distance & ETA chip ─────────────────────────────
        if (_totalDistanceMeters > 0)
          Positioned(
            bottom: 12,
            left: 12,
            child: _buildEtaChip(),
          ),

        // ── Bottom-right: re-centre button ────────────────────────────────
        if (!_isFollowing)
          Positioned(
            bottom: 12,
            right: 12,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: _recenter,
              child: const Icon(Icons.my_location, color: AppColors.textPrimary),
            ),
          ),
      ],
    );
  }

  Widget _buildTopBanner(_RouteStep? step) {
    // ① Waiting for first GPS fix
    if (_currentPosition == null) {
      return _bannerShell(
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
            SizedBox(width: 12),
            Text('Getting your location…',
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    // ② GPS acquired but route is still loading
    if (_isLoadingRoute && step == null) {
      return _bannerShell(
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
            SizedBox(width: 12),
            Text('Calculating route…',
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    // ③ Turn-by-turn instruction
    if (step != null) {
      return _bannerShell(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_stepIcon(step.type),
                  color: AppColors.primary, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.instruction,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmtDist(step.distance),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            // Recalculating spinner (route is refreshing but old step visible)
            if (_isLoadingRoute)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _bannerShell({
    required Widget child,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  Widget _buildEtaChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.neutral900,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _fmtDist(_totalDistanceMeters),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('·',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
          ),
          Text(
            _fmtEta(_totalDurationSecs),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
