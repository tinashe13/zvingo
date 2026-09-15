/// Order submission — the one irreversible step in the funnel.
///
/// Two guards make a double-tap harmless:
///
/// * the notifier refuses to start a second submission while one is in flight,
///   so the button cannot be pressed twice; and
/// * every attempt carries the **same** `idempotency_key` until it succeeds, so
///   even a retried HTTP request (or a lost response) returns the order that
///   already exists instead of creating a second one — see
///   `OrderService.create_order`, which looks the key up before inserting.
library;

import 'dart:math' as math;

import 'package:consumer_app/features/cart/cart_provider.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:consumer_app/features/checkout/order_quote.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'order_placement_provider.g.dart';

enum PlacementStage { idle, placing, placed, failed }

@immutable
class PlacementState {
  const PlacementState({
    this.stage = PlacementStage.idle,
    this.result,
    this.error,
  });

  final PlacementStage stage;
  final CheckoutResult? result;

  /// Customer-safe failure copy.
  final String? error;

  bool get isPlacing => stage == PlacementStage.placing;
  bool get isPlaced => stage == PlacementStage.placed;
  bool get hasFailed => stage == PlacementStage.failed;
}

@Riverpod(keepAlive: true)
class OrderPlacement extends _$OrderPlacement {
  String? _idempotencyKey;

  @override
  PlacementState build() => const PlacementState();

  /// Submit the cart. Returns the result, or null when it failed (the reason
  /// is in `state.error`).
  Future<CheckoutResult?> place({
    required double dropoffLat,
    required double dropoffLng,
    required OrderQuote quote,
    String? deliveryInstructions,
    String? promoCode,
    DateTime? scheduledAt,
  }) async {
    if (state.isPlacing) return null; // the double-tap guard
    if (state.isPlaced) return state.result; // already done; never resubmit

    // One key per checkout attempt, reused across retries.
    _idempotencyKey ??= _newKey();

    state = const PlacementState(stage: PlacementStage.placing);
    try {
      final result = await ref.read(cartProvider.notifier).checkout(
            dropoffLat: dropoffLat,
            dropoffLng: dropoffLng,
            idempotencyKey: _idempotencyKey!,
            deliveryInstructions: deliveryInstructions,
            tip: quote.tip,
            deliveryFee: quote.deliveryFee,
            serviceFee: quote.serviceFee,
            tax: quote.tax,
            promoCode: promoCode,
            scheduledAt: scheduledAt,
            isPickup: quote.isPickup,
            // The basket stays put until the money has actually settled, so a
            // customer staring at a mobile-money prompt still sees what they
            // ordered. `_idempotencyKey` makes re-submitting a no-op, so there
            // is no way to turn the surviving cart into a second order.
            clearCartOnSuccess: false,
          );
      state = PlacementState(stage: PlacementStage.placed, result: result);
      return result;
    } on CheckoutFailure catch (e) {
      state = PlacementState(stage: PlacementStage.failed, error: e.message);
      return null;
    } catch (e) {
      debugPrint('Unexpected checkout failure: $e');
      state = const PlacementState(
        stage: PlacementStage.failed,
        error: 'Something went wrong placing your order. '
            'Nothing has been charged — please try again.',
      );
      return null;
    }
  }

  /// Clear after the user leaves the success screen, so the next cart gets a
  /// fresh key.
  void reset() {
    _idempotencyKey = null;
    state = const PlacementState();
  }

  /// Drop only the error, keeping the key so a retry stays idempotent.
  void dismissError() {
    if (state.hasFailed) state = const PlacementState();
  }

  static String _newKey() {
    final random = math.Random.secure();
    final suffix = List<int>.generate(8, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'zv-${DateTime.now().toUtc().millisecondsSinceEpoch}-$suffix';
  }
}

/// A tip preset expressed in exact minor units.
@immutable
class TipPreset {
  const TipPreset(this.cents);
  final int cents;
  Money money(String currency) => Money.minorUnits(cents, currency: currency);
}

/// Tip presets offered at checkout. 100% of a tip goes to the driver
/// (`FeeBreakdown.driver_payout_minor`), which the UI says out loud.
const List<TipPreset> kTipPresets = <TipPreset>[
  TipPreset(0),
  TipPreset(100),
  TipPreset(200),
  TipPreset(300),
];

/// Delivery or pickup, chosen on the restaurant screen and honoured at
/// checkout. Kept out of the cart so switching mode never touches the basket.
final fulfilmentModeProvider =
    StateProvider<FulfilmentMode>((ref) => FulfilmentMode.delivery);

/// The scheduled slot, when the customer picked one. Null means "as soon as
/// possible".
final scheduledSlotProvider = StateProvider<DateTime?>((ref) => null);
