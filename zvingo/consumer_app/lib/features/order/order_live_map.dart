/// The live journey map, shared by the tracking screen and the orders tab.
///
/// Three things this widget exists to get right:
///
/// 1. **The courier moves, it does not teleport.** GPS fixes land every few
///    seconds; the marker animates between them over [_markerGlide] so the eye
///    can follow it.
/// 2. **You can always see the whole trip.** The camera fits courier,
///    restaurant and destination on first load and whenever the set of known
///    points changes, and a recentre control brings it back after a pan.
/// 3. **The tiles are attributed.** CARTO's basemaps are OpenStreetMap data;
///    shipping them unattributed is a licence breach (cross-team finding X7).
///    [ZvMapAttribution] is always visible — never hidden behind a tap.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/order/order_providers.dart';
import 'package:consumer_app/features/order/order_timeline.dart';
import 'package:consumer_app/features/order/order_tracking_transport.dart';

/// Harare city centre — only ever used as the camera's opening pose before any
/// real coordinate is known. No marker is ever drawn here.
const LatLng kHarareCentre = LatLng(-17.8216, 31.0492);

/// CARTO Voyager raster tiles, which render OpenStreetMap data.
const String kTileUrlTemplate =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png';

/// Attribution required by the OpenStreetMap ODbL and CARTO's basemap terms.
///
/// Rendered as a persistent, legible chip rather than flutter_map's collapsible
/// `RichAttributionWidget`: the licence asks for visible credit, and a credit
/// behind a tap is not visible.
class ZvMapAttribution extends StatelessWidget {
  const ZvMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Map data from OpenStreetMap contributors, tiles by CARTO',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.86),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.sm),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxxs,
          ),
          child: Text(
            '© OpenStreetMap contributors · © CARTO',
            style: TextStyle(
              fontSize: 9,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The live map for one order.
///
/// Reads [orderTrackingProvider], so it shares the single tracker connection
/// with the rest of the order feature rather than opening its own.
class OrderLiveMap extends ConsumerStatefulWidget {
  const OrderLiveMap({
    super.key,
    required this.orderId,
    this.height = 320,
    this.borderRadius = AppRadius.xlAll,
    this.interactive = true,
    this.onOpenTracking,
    this.topInset = AppSpacing.md,
  });

  final String orderId;

  /// Fixed map height. The tracking screen uses a share of the viewport.
  final double height;

  final BorderRadius borderRadius;

  /// Whether the user can pan/zoom. The compact card on the orders tab does
  /// allow it; a tap-through preview would not.
  final bool interactive;

  /// Shown as a tappable footer card when provided (the orders tab).
  final VoidCallback? onOpenTracking;

  /// Extra top padding for the camera fit, so markers clear a status bar or a
  /// floating control.
  final double topInset;

  @override
  ConsumerState<OrderLiveMap> createState() => _OrderLiveMapState();
}

class _OrderLiveMapState extends ConsumerState<OrderLiveMap>
    with TickerProviderStateMixin {
  /// How long the courier marker takes to slide between two fixes. Slightly
  /// longer than the typical update gap so movement reads as continuous.
  static const Duration _markerGlide = Duration(milliseconds: 900);

  final MapController _mapController = MapController();

  late final AnimationController _markerController;
  AnimationController? _cameraController;

  LatLng? _markerFrom;
  LatLng? _markerTo;
  OrderTrackingState? _applied;
  int _knownPointCount = 0;
  bool _mapReady = false;
  bool _userMovedCamera = false;

  @override
  void initState() {
    super.initState();
    _markerController = AnimationController(vsync: this, duration: _markerGlide)
      ..addListener(_onMarkerTick);
  }

  void _onMarkerTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _markerController
      ..removeListener(_onMarkerTick)
      ..dispose();
    _cameraController?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Current interpolated courier position.
  LatLng? get _courierPosition {
    final to = _markerTo;
    if (to == null) return null;
    final from = _markerFrom;
    if (from == null || !_markerController.isAnimating) return to;
    final t = Curves.easeInOut.transform(_markerController.value);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  void _pushCourierPosition(LatLng? next, {required bool animate}) {
    if (next == null) return;
    final current = _markerTo;
    if (current != null &&
        (current.latitude - next.latitude).abs() < 1e-7 &&
        (current.longitude - next.longitude).abs() < 1e-7) {
      return;
    }
    _markerFrom = _courierPosition ?? current ?? next;
    _markerTo = next;
    if (!animate || _markerFrom == next) {
      _markerController.value = 1;
      return;
    }
    _markerController.forward(from: 0);
  }

  List<LatLng> _tripPoints(OrderTrackingState state) {
    final order = state.order;
    return <LatLng>[
      if (_markerTo != null) _markerTo!,
      if (order?.pickup != null) order!.pickup!,
      if (order?.destination != null) order!.destination!,
    ];
  }

  /// Fits the camera to every known point. Called on first data and whenever a
  /// new kind of point appears (courier assigned, destination resolved).
  void _fitCamera(List<LatLng> points, {bool force = false}) {
    if (!_mapReady || points.isEmpty) return;
    if (!force && _userMovedCamera) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      try {
        if (points.length == 1) {
          _moveCamera(points.first, 15.5);
          return;
        }
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              widget.topInset + AppSpacing.xxl,
              AppSpacing.xxl,
              widget.onOpenTracking != null ? 110 : AppSpacing.xxl,
            ),
          ),
        );
        _userMovedCamera = false;
      } catch (_) {
        // Degenerate bounds (all points identical) — centre instead.
        _moveCamera(points.first, 14);
      }
    });
  }

  /// Eased camera move. flutter_map has no animated `move`, so it is driven
  /// here rather than snapping the viewport.
  void _moveCamera(LatLng target, double zoom) {
    if (!_mapReady) return;
    _cameraController?.dispose();
    final camera = _mapController.camera;
    final startCentre = camera.center;
    final startZoom = camera.zoom;
    final curve = AppMotion.curve(context, AppMotion.standard);
    final controller = AnimationController(
      vsync: this,
      duration: AppMotion.duration(context, AppMotion.slow),
    );
    _cameraController = controller;

    void tick() {
      if (!mounted || !_mapReady) return;
      final t = curve.transform(controller.value);
      _mapController.move(
        LatLng(
          startCentre.latitude + (target.latitude - startCentre.latitude) * t,
          startCentre.longitude +
              (target.longitude - startCentre.longitude) * t,
        ),
        startZoom + (zoom - startZoom) * t,
      );
    }

    controller.addListener(tick);
    controller.forward().whenComplete(() {
      controller.removeListener(tick);
      controller.dispose();
      if (identical(_cameraController, controller)) _cameraController = null;
    });
  }

  /// Applies a new tracking snapshot. Always runs **outside** build, so it may
  /// call `setState` and start animations.
  void _apply(OrderTrackingState state) {
    setState(() => _pushCourierPosition(
          state.driverPosition,
          animate: _markerTo != null,
        ));
    final points = _tripPoints(state);
    if (points.length != _knownPointCount) {
      _knownPointCount = points.length;
      _fitCamera(points);
    }
  }

  void _recentre(OrderTrackingState state) {
    _userMovedCamera = false;
    _fitCamera(_tripPoints(state), force: true);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(orderTrackingProvider(widget.orderId));
    final state = async.valueOrNull;

    // Marker glide and camera fits mutate state and start animations, so they
    // are deferred out of the build phase.
    if (state != null && !identical(state, _applied)) {
      _applied = state;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _apply(state);
      });
    }

    final order = state?.order;
    final courier = _courierPosition;
    final opening = courier ??
        order?.destination ??
        order?.pickup ??
        kHarareCentre;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.surfaceMuted,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: opening,
                    initialZoom: 14.5,
                    onMapReady: () {
                      _mapReady = true;
                      if (state != null) _fitCamera(_tripPoints(state));
                    },
                    // A deliberate pan wins: auto-fit stops fighting the user
                    // until they ask for it back with the recentre control.
                    onPositionChanged: (_, hasGesture) {
                      if (hasGesture) _userMovedCamera = true;
                    },
                    interactionOptions: InteractionOptions(
                      flags: widget.interactive
                          ? InteractiveFlag.drag |
                              InteractiveFlag.pinchZoom |
                              InteractiveFlag.doubleTapZoom |
                              InteractiveFlag.flingAnimation
                          : InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: kTileUrlTemplate,
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.zvingo.consumer',
                      retinaMode: false,
                    ),
                    if (order != null)
                      PolylineLayer(
                        polylines: [
                          if (order.pickup != null && order.destination != null)
                            Polyline(
                              points: [order.pickup!, order.destination!],
                              strokeWidth: 4,
                              color: AppColors.neutral400.withValues(alpha: 0.7),
                            ),
                          if (courier != null && order.destination != null)
                            Polyline(
                              points: [courier, order.destination!],
                              strokeWidth: 5,
                              color: AppColors.actionDefault
                                  .withValues(alpha: 0.85),
                            ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (order?.pickup != null)
                          Marker(
                            point: order!.pickup!,
                            width: 38,
                            height: 38,
                            child: const _MapPin(
                              icon: Icons.storefront_rounded,
                              background: AppColors.surface,
                              foreground: AppColors.textPrimary,
                              tooltip: 'Restaurant',
                            ),
                          ),
                        if (order?.destination != null)
                          Marker(
                            point: order!.destination!,
                            width: 40,
                            height: 40,
                            child: const _MapPin(
                              icon: Icons.home_rounded,
                              background: AppColors.brandLime,
                              foreground: AppColors.textPrimary,
                              tooltip: 'Your address',
                            ),
                          ),
                        if (courier != null)
                          Marker(
                            point: courier,
                            width: 52,
                            height: 52,
                            child: const _CourierPin(),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Live/degraded pill — the map says whether it is actually live.
            Positioned(
              left: AppSpacing.sm,
              top: widget.topInset,
              child: _LiveBadge(state: state),
            ),

            // Recentre — always available, not only after a pan, so the
            // control never appears and disappears under the thumb.
            Positioned(
              right: AppSpacing.sm,
              top: widget.topInset,
              child: ZvIconButton(
                icon: Icons.my_location_rounded,
                tooltip: 'Recentre the map on your delivery',
                background: AppColors.surface,
                onPressed:
                    state == null ? null : () => _recentre(state),
              ),
            ),

            const Positioned(
              right: 0,
              bottom: 0,
              child: ZvMapAttribution(),
            ),

            if (widget.onOpenTracking != null)
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.md,
                child: _MapFooterCard(
                  state: state,
                  onTap: widget.onOpenTracking!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Live GPS" / "Updates paused" pill.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.state});

  final OrderTrackingState? state;

  @override
  Widget build(BuildContext context) {
    final status = state?.status ?? OrderConnectionStatus.connecting;
    late final String label;
    late final Color dot;
    switch (status) {
      case OrderConnectionStatus.live:
        label = state?.driverPosition != null ? 'Live GPS' : 'Live';
        dot = AppColors.brandLime;
        break;
      case OrderConnectionStatus.connecting:
        label = 'Connecting';
        dot = AppColors.neutral400;
        break;
      case OrderConnectionStatus.degraded:
        label = 'Updates paused';
        dot = AppColors.warning;
        break;
      case OrderConnectionStatus.offline:
        label = 'Offline';
        dot = AppColors.error;
        break;
      case OrderConnectionStatus.closed:
        label = 'Trip finished';
        dot = AppColors.brandGreen;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.actionDefault,
        borderRadius: AppRadius.fullAll,
        boxShadow: AppShadows.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTextStyles.overline.copyWith(color: AppColors.textOnDark),
          ),
        ],
      ),
    );
  }
}

/// Tap-through card on the compact map (orders tab).
class _MapFooterCard extends StatelessWidget {
  const _MapFooterCard({required this.state, required this.onTap});

  final OrderTrackingState? state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final order = state?.order;
    final headline = orderHeadline(
      order?.state ?? 'CREATED',
      driverFirstName: order?.driver?.firstName,
    );
    final eta = state?.eta ?? OrderEta.unknown;

    return ZvCard(
      onTap: onTap,
      raised: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      semanticLabel: '${headline.title}. ${eta.label}. Open live tracking',
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: headline.surface,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(headline.icon, color: headline.color, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ZvAnimatedSwap(
                  valueKey: headline.title,
                  child: Text(headline.title, style: AppTextStyles.h3),
                ),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  eta.hasValue && eta.confidence != EtaConfidence.unknown
                      ? '${eta.label} · ${headline.detail}'
                      : headline.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 22),
        ],
      ),
    );
  }
}

/// Restaurant / destination pin.
class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.tooltip,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 2),
          boxShadow: AppShadows.sm,
        ),
        child: Icon(icon, color: foreground, size: 20),
      ),
    );
  }
}

/// The courier marker: a dark pin inside a slow pulse, so the eye finds it
/// immediately and reads it as the thing that is moving.
class _CourierPin extends StatefulWidget {
  const _CourierPin();

  @override
  State<_CourierPin> createState() => _CourierPinState();
}

class _CourierPinState extends State<_CourierPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // §4.4: reduced motion means no looping pulse.
    if (AppMotion.reduced(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Your courier',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.isAnimating ? _pulse.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (t > 0)
                Container(
                  width: 28 + 24 * t,
                  height: 28 + 24 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.actionDefault
                        .withValues(alpha: 0.18 * (1 - t)),
                  ),
                ),
              child!,
            ],
          );
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.actionDefault,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface, width: 2.5),
            boxShadow: AppShadows.md,
          ),
          child: const Icon(
            Icons.delivery_dining_rounded,
            color: AppColors.textOnDark,
            size: 19,
          ),
        ),
      ),
    );
  }
}

/// Distance in metres between two points, used by the tracking screen's
/// "N metres away" copy.
double metresBetween(LatLng a, LatLng b) =>
    const Distance().as(LengthUnit.Meter, a, b);

/// Human distance, e.g. "400 m away" / "2.3 km away".
String formatDistance(double metres) {
  if (metres < 950) {
    final rounded = (metres / 50).round() * 50;
    return '${math.max(rounded, 50)} m away';
  }
  return '${(metres / 1000).toStringAsFixed(1)} km away';
}
