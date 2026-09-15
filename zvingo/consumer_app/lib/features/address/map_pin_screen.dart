import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/address/address_provider.dart';

/// The exact point a driver should ride to.
class PinnedPoint {
  const PinnedPoint({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  String toString() =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

/// Drag the map to put the pin on the gate, not the street centroid.
///
/// Geocoding gets you to the road; it does not know which of four identical
/// gates is yours. This screen is the difference between a driver arriving and
/// a driver phoning. The pin stays fixed in the centre of the screen and the
/// *map* moves underneath it — the interaction every mapping app uses, and the
/// one that works with a thumb.
class MapPinScreen extends ConsumerStatefulWidget {
  const MapPinScreen({
    super.key,
    required this.initial,
    this.addressLine,
  });

  final PinnedPoint initial;

  /// Shown in the confirmation card so the user can tell whether the pin still
  /// matches the address they searched for.
  final String? addressLine;

  static const double _defaultZoom = 17;

  static Future<PinnedPoint?> push(
    BuildContext context, {
    required PinnedPoint initial,
    String? addressLine,
  }) {
    return Navigator.of(context, rootNavigator: true).push<PinnedPoint>(
      MaterialPageRoute<PinnedPoint>(
        builder: (_) =>
            MapPinScreen(initial: initial, addressLine: addressLine),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<MapPinScreen> createState() => _MapPinScreenState();
}

class _MapPinScreenState extends ConsumerState<MapPinScreen> {
  final MapController _controller = MapController();

  late LatLng _centre = LatLng(widget.initial.lat, widget.initial.lng);
  bool _moving = false;
  bool _locating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final current = await ref.refresh(currentLocationAddressProvider.future);
      final point = LatLng(current.lat, current.lng);
      if (!mounted) return;
      _controller.move(point, MapPinScreen._defaultZoom);
      setState(() => _centre = point);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not get your location. Check that location is switched '
            'on and that Zvingo has permission.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ZvScreen(
      title: 'Drop the pin',
      subtitle: 'Move the map so the pin sits on your gate or door',
      fallbackRoute: '/addresses',
      footer: ZvStickyFooter(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.addressLine != null) ...[
              Row(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      widget.addressLine!,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            ZvButton.primary(
              label: 'Use this spot',
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop(
                PinnedPoint(
                  lat: _centre.latitude,
                  lng: _centre.longitude,
                ),
              ),
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: _centre,
                initialZoom: MapPinScreen._defaultZoom,
                minZoom: 4,
                maxZoom: 19,
                onPositionChanged: (camera, hasGesture) {
                  if (!hasGesture) return;
                  setState(() {
                    _centre = camera.center;
                    _moving = true;
                  });
                },
                onMapEvent: (event) {
                  if (event is MapEventMoveEnd ||
                      event is MapEventFlingAnimationEnd) {
                    setState(() => _moving = false);
                  }
                },
              ),
              children: const [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                  subdomains: ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.zvingo.consumer',
                ),
                // Attribution is a licence condition of both OpenStreetMap and
                // CARTO, not decoration (finding X7).
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                    TextSourceAttribution('CARTO'),
                  ],
                ),
              ],
            ),
          ),
          // The pin is pinned to the screen, not the map.
          IgnorePointer(
            child: Center(
              child: _CentrePin(lifted: _moving),
            ),
          ),
          Positioned(
            right: AppSpacing.md,
            top: AppSpacing.md,
            child: Column(
              children: [
                ZvIconButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Use my current location',
                  loading: _locating,
                  background: AppColors.surface,
                  onPressed: _locating ? null : _useCurrentLocation,
                ),
                const SizedBox(height: AppSpacing.xs),
                ZvIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Zoom in',
                  background: AppColors.surface,
                  onPressed: () => _controller.move(
                    _centre,
                    (_controller.camera.zoom + 1).clamp(4, 19),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ZvIconButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Zoom out',
                  background: AppColors.surface,
                  onPressed: () => _controller.move(
                    _centre,
                    (_controller.camera.zoom - 1).clamp(4, 19),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A map marker that lifts off its shadow while the map is being dragged, so it
/// is obvious the pin is placing itself rather than sitting still.
class _CentrePin extends StatelessWidget {
  const _CentrePin({required this.lifted});

  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final rise = context.motionDistance(lifted ? 10 : 0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSlide(
          duration: context.motion(AppMotion.fast),
          curve: context.motionCurve(AppMotion.standard),
          offset: Offset(0, -rise / 48),
          child: const Icon(
            Icons.location_on_rounded,
            size: 48,
            color: AppColors.actionDefault,
          ),
        ),
        AnimatedContainer(
          duration: context.motion(AppMotion.fast),
          width: lifted ? 6 : 10,
          height: lifted ? 6 : 10,
          decoration: const BoxDecoration(
            color: AppColors.actionDefault,
            shape: BoxShape.circle,
          ),
        ),
        // Leaves room under the pin so the marker tip, not its middle, sits on
        // the map centre.
        const SizedBox(height: 44),
      ],
    );
  }
}
