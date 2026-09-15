import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/router.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/widgets.dart';
import 'map_attribution.dart';

/// The offer takeover: one job, one decision, a few seconds to make it.
///
/// Three things this screen has to get right, in order of how much they cost a
/// driver when they are wrong:
///
/// 1. **The countdown must be honest.** When the window closes the card is
///    replaced by an explicit expired state with a way out. It used to keep
///    accepting taps on a dead offer, which produced a silent server-side
///    failure and a driver staring at a screen wondering if they got the job.
/// 2. **Losing the race is not the driver's fault.** Dispatch fans an offer out
///    to more than one driver, so `POST /dispatch/accept` answers 409 when
///    somebody else claimed it first. That reads as "no harm done", never as a
///    failure.
/// 3. **Nothing happens twice.** Accepting locks the card via
///    `OfferCard(isSubmitting:)` while the claim is in flight.
class OfferScreen extends ConsumerStatefulWidget {
  const OfferScreen({super.key});

  @override
  ConsumerState<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends ConsumerState<OfferScreen> {
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _remainingSeconds =
        ref.read(deliveryProvider).currentOffer?.remainingSeconds ?? 0;
    // Recompute from the offer's own clock every tick rather than decrementing
    // a local counter: a screen rebuilt after a moment in the background then
    // shows the real time left instead of a number frozen where it paused.
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final offer = ref.read(deliveryProvider).currentOffer;
      if (!mounted) return;
      setState(() => _remainingSeconds = offer?.remainingSeconds ?? 0);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    final accepted = await ref.read(deliveryProvider.notifier).acceptOffer();
    if (!mounted) return;
    if (accepted) {
      context.go(routeNavigateToMerchant);
      return;
    }
    _leaveWithMessage();
  }

  Future<void> _decline() async {
    unawaited(ref.read(deliveryProvider.notifier).declineOffer());
    if (!mounted) return;
    context.go(routeHome);
  }

  /// Leave the takeover, carrying whatever the provider wants said. A notice
  /// (lost the race, ran out of time) is neutral; an error is red.
  void _leaveWithMessage() {
    final delivery = ref.read(deliveryProvider);
    final notice = delivery.notice;
    final error = delivery.error;
    context.go(routeHome);
    if (notice != null) {
      DriverSnack.show(context, notice, icon: Icons.info_outline_rounded);
    } else if (error != null) {
      DriverSnack.error(context, error);
    }
    ref.read(deliveryProvider.notifier).clearMessages();
  }

  @override
  Widget build(BuildContext context) {
    final delivery = ref.watch(deliveryProvider);
    final offer = delivery.currentOffer;

    if (offer == null) {
      // The offer was withdrawn, taken, or already answered on another screen.
      return Scaffold(
        appBar: const DriverAppBar(
          title: 'Offer',
          showBack: false,
        ),
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.screenPaddingOf(context)),
          child: DriverEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No offer on screen',
            message: 'This offer is no longer available. Stay online and the '
                'next one will come straight through.',
            actionLabel: 'Back to dash',
            onAction: () => context.go(routeHome),
          ),
        ),
      );
    }

    final expired = delivery.offerExpired || _remainingSeconds <= 0;
    final hasRoute = offer.hasPickupCoords && offer.hasDeliveryCoords;

    return Scaffold(
      body: Stack(
        children: [
          if (hasRoute)
            _StaticRouteMap(
              pickup: LatLng(offer.pickupLat, offer.pickupLng),
              delivery: LatLng(offer.deliveryLat, offer.deliveryLng),
            )
          else
            const _MapUnavailable(),

          // Darkens the top and bottom of the map so the card and the payout
          // stay legible against whatever tiles happen to be underneath.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.35, 0.65, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.28),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: expired
                  ? _ExpiredPanel(
                      onDismiss: () {
                        ref
                            .read(deliveryProvider.notifier)
                            .dismissExpiredOffer();
                        context.go(routeHome);
                      },
                    )
                  : OfferCard(
                      merchantName: offer.merchantName,
                      merchantAddress: offer.merchantAddress,
                      customerName: offer.customerName,
                      customerAddress: offer.customerAddress,
                      deliveryFeeCents: offer.deliveryFeeCents,
                      tipCents: offer.tipCents,
                      orderSubtotalCents: offer.orderSubtotalCents,
                      itemsSummary: offer.itemsSummary,
                      estimatedDistanceKm: offer.estimatedDistanceKm,
                      pickupDistanceKm: offer.pickupDistanceKm,
                      estimatedTimeMinutes: offer.estimatedTimeMinutes,
                      remainingSeconds: _remainingSeconds,
                      totalSeconds: offer.timeoutSeconds,
                      paymentMethod: offer.paymentMethod.displayName,
                      isSubmitting: delivery.isLoading,
                      onAccept: _accept,
                      onDecline: _decline,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once the offer window has closed. An expired offer must look expired.
class _ExpiredPanel extends StatelessWidget {
  final VoidCallback onDismiss;

  const _ExpiredPanel({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppSpacing.brSheetTop,
        boxShadow: AppSpacing.shadowLgOf(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatusChip(
            label: 'Expired',
            tone: StatusTone.neutral,
            icon: Icons.timer_off_outlined,
          ),
          Gap.md,
          Text(
            'That offer ran out of time',
            style: AppTextStyles.onSurface(context, AppTextStyles.h2),
          ),
          Gap.sm,
          Text(
            "It has gone to another driver. You're still online — the next one "
            'comes straight to this screen.',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          Gap.xxl,
          DriverPrimaryButton(
            label: 'Back to dash',
            icon: Icons.explore_outlined,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// Stand-in when the offer has no usable coordinates, so the screen never
/// renders an empty grey rectangle with no explanation.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceMutedOf(context),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              size: 64,
              color: AppColors.textTertiaryOf(context),
            ),
            Gap.md,
            Text(
              'Route preview unavailable',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A non-interactive map of the pickup → drop-off leg.
class _StaticRouteMap extends StatelessWidget {
  final LatLng pickup;
  final LatLng delivery;

  const _StaticRouteMap({required this.pickup, required this.delivery});

  /// Zoom that keeps both ends on screen. Cheaper and steadier than fitting
  /// bounds on a map the driver cannot pan anyway.
  double get _zoom {
    final spread = max(
      (pickup.latitude - delivery.latitude).abs(),
      (pickup.longitude - delivery.longitude).abs(),
    );
    if (spread < 0.01) return 15;
    if (spread < 0.03) return 14;
    if (spread < 0.06) return 13;
    if (spread < 0.12) return 12;
    if (spread < 0.25) return 11;
    if (spread < 0.55) return 10;
    return 9;
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(
          (pickup.latitude + delivery.latitude) / 2,
          (pickup.longitude + delivery.longitude) / 2,
        ),
        initialZoom: _zoom,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: MapBasemap.voyager.urlTemplate,
          subdomains: MapBasemap.voyager.subdomains,
          userAgentPackageName: MapBasemap.userAgentPackageName,
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: [pickup, delivery],
              color: AppColors.brandGreen,
              strokeWidth: 5,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: pickup,
              width: 40,
              height: 40,
              child: const _MapPin(
                icon: Icons.storefront_rounded,
                color: AppColors.brandGreen,
              ),
            ),
            Marker(
              point: delivery,
              width: 40,
              height: 40,
              child: const _MapPin(
                icon: Icons.person_rounded,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        // Licence requirement, not decoration: OSM data is ODbL and CARTO's
        // basemap terms require visible credit (finding X7).
        const MapAttribution(),
      ],
    );
  }
}

class _MapPin extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _MapPin({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.neutral0, width: 2.5),
        boxShadow: AppSpacing.shadowSm,
      ),
      child: Icon(icon, color: AppColors.neutral0, size: 18),
    );
  }
}
