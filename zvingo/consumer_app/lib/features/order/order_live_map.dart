import 'dart:async';
import 'dart:convert';

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_config.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// A compact, live journey map for the order selected on the Orders screen.
///
/// The order endpoint supplies the first known positions and remains a fallback
/// when a live stream is unavailable. Once a courier is assigned, the existing
/// driver location stream moves the courier marker using real GPS updates.
class OrderLiveMap extends ConsumerStatefulWidget {
  const OrderLiveMap({
    super.key,
    required this.orderId,
    required this.initialState,
    required this.onOpenTracking,
  });

  final String orderId;
  final String initialState;
  final VoidCallback onOpenTracking;

  @override
  ConsumerState<OrderLiveMap> createState() => _OrderLiveMapState();
}

class _OrderLiveMapState extends ConsumerState<OrderLiveMap> {
  final MapController _mapController = MapController();
  Timer? _pollTimer;
  StreamSubscription<dynamic>? _locationSubscription;

  LatLng? _driverLocation;
  LatLng? _deliveryLocation;
  LatLng? _pickupLocation;
  String _driverId = '';
  String _driverName = '';
  String _state = 'CREATED';
  bool _loading = true;
  bool _didFitMap = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _loadOrder();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadOrder(silent: true),
    );
  }

  @override
  void didUpdateWidget(covariant OrderLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId == widget.orderId) return;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _driverLocation = null;
    _deliveryLocation = null;
    _pickupLocation = null;
    _driverId = '';
    _driverName = '';
    _state = widget.initialState;
    _loading = true;
    _didFitMap = false;
    _loadOrder();
  }

  Future<void> _loadOrder({bool silent = false}) async {
    try {
      final response = await ref.read(apiClientProvider).get(
            '/orders/${widget.orderId}',
          );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return;

      final nextDriverId = data['driver_id']?.toString() ?? '';
      setState(() {
        _loading = false;
        _state = _normaliseState(data['state'] ?? _state);
        _driverName = (data['driver_name'] as String?)?.split(' ').first ?? '';
        _deliveryLocation = _coordinates(
              data['delivery_lat'],
              data['delivery_lng'],
            ) ??
            _deliveryLocation;
        _pickupLocation = _coordinates(
              data['pickup_lat'],
              data['pickup_lng'],
            ) ??
            _pickupLocation;
        _driverLocation = _coordinates(
              data['driver_lat'],
              data['driver_lng'],
            ) ??
            _driverLocation;
      });

      if (nextDriverId.isNotEmpty && nextDriverId != _driverId) {
        _driverId = nextDriverId;
        _subscribeToDriver(nextDriverId);
      }
      _fitMapOnce();
    } catch (_) {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  void _subscribeToDriver(String driverId) {
    _locationSubscription?.cancel();
    final url = '${AppConfig.apiBaseUrl}/location/driver/$driverId/track';
    _locationSubscription = SSEClient.subscribeToSSE(
      method: SSERequestType.GET,
      url: url,
      header: const {
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    ).listen((event) {
      if (!mounted || event.data == null || event.data!.isEmpty) return;
      try {
        final data = jsonDecode(event.data!) as Map<String, dynamic>;
        final location = _coordinates(data['lat'], data['lng']);
        if (location == null) return;
        setState(() => _driverLocation = location);
        if (!_didFitMap) _fitMapOnce();
      } catch (_) {
        // A malformed location event should not interrupt order tracking.
      }
    });
  }

  LatLng? _coordinates(dynamic latitude, dynamic longitude) {
    if (latitude is! num || longitude is! num) return null;
    final lat = latitude.toDouble();
    final lng = longitude.toDouble();
    if (lat.abs() < 0.01 && lng.abs() < 0.01) return null;
    return LatLng(lat, lng);
  }

  void _fitMapOnce() {
    if (_didFitMap) return;
    final points = [
      if (_driverLocation != null) _driverLocation!,
      if (_deliveryLocation != null) _deliveryLocation!,
      if (_pickupLocation != null) _pickupLocation!,
    ];
    if (points.isEmpty) return;
    _didFitMap = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 15.5);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.fromLTRB(46, 70, 46, 118),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _locationSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _liveStatus(_state);
    final initialCenter = _driverLocation ??
        _deliveryLocation ??
        _pickupLocation ??
        const LatLng(-17.8216, 31.0492);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 326,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.surfaceMuted,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: 14.5,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag |
                          InteractiveFlag.pinchZoom |
                          InteractiveFlag.doubleTapZoom,
                    ),
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
                        if (_pickupLocation != null)
                          Marker(
                            point: _pickupLocation!,
                            width: 36,
                            height: 36,
                            child: const _MapMarker(
                              icon: Icons.storefront_rounded,
                              background: AppColors.white,
                              foreground: AppColors.textPrimary,
                            ),
                          ),
                        if (_deliveryLocation != null)
                          Marker(
                            point: _deliveryLocation!,
                            width: 40,
                            height: 40,
                            child: const _MapMarker(
                              icon: Icons.home_rounded,
                              background: AppColors.accent,
                              foreground: AppColors.textPrimary,
                            ),
                          ),
                        if (_driverLocation != null)
                          Marker(
                            point: _driverLocation!,
                            width: 48,
                            height: 48,
                            child: const _MapMarker(
                              icon: Icons.delivery_dining_rounded,
                              background: AppColors.selectedDark,
                              foreground: AppColors.white,
                              prominent: true,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.selectedDark,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(color: Color(0x26000000), blurRadius: 14),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _driverLocation == null ? 'Tracking ready' : 'Live GPS',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Material(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(18),
                elevation: 2,
                shadowColor: const Color(0x33000000),
                child: InkWell(
                  onTap: widget.onOpenTracking,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: status.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child:
                              Icon(status.icon, color: status.color, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(status.title,
                                  style: AppTextStyles.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                _driverLocation != null
                                    ? (_driverName.isEmpty
                                        ? 'Courier location updating live'
                                        : '$_driverName is sharing a live location')
                                    : (_loading
                                        ? 'Loading the latest journey'
                                        : 'The map updates when a courier is assigned'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    required this.icon,
    required this.background,
    required this.foreground,
    this.prominent = false,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.white, width: prominent ? 3 : 2),
          boxShadow: const [
            BoxShadow(
                color: Color(0x35000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Icon(icon, color: foreground, size: prominent ? 24 : 19),
      );
}

String _normaliseState(dynamic value) =>
    value.toString().replaceFirst('OrderState.', '');

({String title, IconData icon, Color color, Color surface}) _liveStatus(
  String state,
) {
  switch (state) {
    case 'PICKED_UP':
    case 'EN_ROUTE':
      return (
        title: 'Your order is on the way',
        icon: Icons.delivery_dining_rounded,
        color: AppColors.info,
        surface: const Color(0xFFEAF2FF),
      );
    case 'ARRIVED_AT_CUSTOMER':
      return (
        title: 'Your courier has arrived',
        icon: Icons.location_on_rounded,
        color: AppColors.info,
        surface: const Color(0xFFEAF2FF),
      );
    case 'ACCEPTED':
    case 'PREPARING':
    case 'ARRIVED_AT_MERCHANT':
    case 'READY_FOR_PICKUP':
      return (
        title: 'The kitchen is working on it',
        icon: Icons.restaurant_rounded,
        color: AppColors.brandGreen,
        surface: AppColors.brandGreenSurface,
      );
    default:
      return (
        title: 'Your order is confirmed',
        icon: Icons.receipt_long_rounded,
        color: AppColors.warning,
        surface: AppColors.warningSurface,
      );
  }
}
