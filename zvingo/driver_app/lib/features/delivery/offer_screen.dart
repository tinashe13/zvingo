import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/offer_card.dart';

/// OfferScreen — Uber-style full-screen offer with route map background.
class OfferScreen extends ConsumerStatefulWidget {
  const OfferScreen({super.key});

  @override
  ConsumerState<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends ConsumerState<OfferScreen> {
  Timer? _countdownTimer;
  int _remainingSeconds = 45;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    final offer = ref.read(deliveryProvider).currentOffer;
    if (offer != null) {
      _remainingSeconds = offer.remainingSeconds;
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _remainingSeconds = (_remainingSeconds - 1).clamp(0, 45);
        });
        if (_remainingSeconds <= 0) {
          _countdownTimer?.cancel();
          _handleDecline();
        }
      }
    });
  }

  void _handleAccept() {
    _countdownTimer?.cancel();
    ref.read(deliveryProvider.notifier).acceptOffer();
    context.go('/delivery/navigate-to-merchant');
  }

  void _handleDecline() {
    _countdownTimer?.cancel();
    ref.read(deliveryProvider.notifier).declineOffer();
    context.go('/');
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delivery = ref.watch(deliveryProvider);
    final offer = delivery.currentOffer;

    if (offer == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No active offer'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      );
    }

    final hasCoords =
        offer.pickupLat != 0 && offer.deliveryLat != 0;

    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen route map background ──────────
          if (hasCoords)
            _StaticRouteMap(
              pickupLat: offer.pickupLat,
              pickupLng: offer.pickupLng,
              deliveryLat: offer.deliveryLat,
              deliveryLng: offer.deliveryLng,
            )
          else
            Container(
              color: AppColors.primarySurface,
              child: const Center(
                child: Icon(Icons.map_outlined, size: 80, color: AppColors.primary),
              ),
            ),

          // ── Gradient overlay (improves contrast for card) ──
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.35, 0.65, 1.0],
                    colors: [
                      Colors.black.withOpacity(0.15),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.25),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom offer card panel ─────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: OfferCard(
                merchantName: offer.merchantName,
                merchantAddress: offer.merchantAddress,
                customerName: offer.customerName,
                customerAddress: offer.customerAddress,
                deliveryFeeCents: offer.deliveryFeeCents,
                tipCents: offer.tipCents,
                orderSubtotalCents: offer.orderSubtotalCents,
                itemsSummary: offer.itemsSummary,
                estimatedDistanceKm: offer.estimatedDistanceKm,
                estimatedTimeMinutes: offer.estimatedTimeMinutes,
                remainingSeconds: _remainingSeconds,
                paymentMethod: offer.paymentMethod.displayName,
                onAccept: _handleAccept,
                onDecline: _handleDecline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A non-interactive flutter_map showing the pickup → delivery route.
class _StaticRouteMap extends StatelessWidget {
  final double pickupLat;
  final double pickupLng;
  final double deliveryLat;
  final double deliveryLng;

  const _StaticRouteMap({
    required this.pickupLat,
    required this.pickupLng,
    required this.deliveryLat,
    required this.deliveryLng,
  });

  double _calcZoom() {
    final latDiff = (pickupLat - deliveryLat).abs();
    final lngDiff = (pickupLng - deliveryLng).abs();
    final diff = max(latDiff, lngDiff);
    if (diff < 0.01) return 15;
    if (diff < 0.03) return 14;
    if (diff < 0.06) return 13;
    if (diff < 0.12) return 12;
    if (diff < 0.25) return 11;
    if (diff < 0.55) return 10;
    return 9;
  }

  @override
  Widget build(BuildContext context) {
    final pickup = LatLng(pickupLat, pickupLng);
    final delivery = LatLng(deliveryLat, deliveryLng);
    final center = LatLng(
      (pickupLat + deliveryLat) / 2,
      (pickupLng + deliveryLng) / 2,
    );

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: _calcZoom(),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.zvingo.driver',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: [pickup, delivery],
              color: AppColors.primary,
              strokeWidth: 4,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            // Merchant / pickup marker
            Marker(
              point: pickup,
              width: 36,
              height: 36,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6),
                  ],
                ),
                child: const Icon(Icons.store, color: Colors.white, size: 16),
              ),
            ),
            // Customer / delivery marker
            Marker(
              point: delivery,
              width: 36,
              height: 36,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6),
                  ],
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
