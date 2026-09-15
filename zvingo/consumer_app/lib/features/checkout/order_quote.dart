/// The single place the money on the checkout screen is decided.
///
/// Every figure the customer sees — and every figure sent to
/// `POST /orders/checkout` — comes from one [OrderQuote]. That is what makes
/// the breakdown reconcile: `subtotal + delivery + service + tax + tip
/// - discount == total`, checked by an assertion, in integer cents.
///
/// The delivery fee deliberately mirrors the backend formula in
/// `app/finance/fee_calculator.py` (**$5 per started 5 km block**) for the case
/// where the restaurant has no configured fee, because `OrderService`
/// recomputes the fee itself whenever the client sends `delivery_fee <= 0`.
/// Quoting one number and being charged another is exactly the "surprise after
/// the tap" this screen must not have.
library;

import 'dart:math' as math;

import 'package:consumer_app/features/cart/money.dart';
import 'package:flutter/foundation.dart';

/// Delivery or self-collection.
enum FulfilmentMode { delivery, pickup }

/// Service fee: 15% of the food subtotal, floored at US$0.99 and capped at
/// US$9.99. Expressed in basis points so the maths stays integral.
const int kServiceFeeBasisPoints = 1500;
const int kServiceFeeMinCents = 99;
const int kServiceFeeMaxCents = 999;

/// Backend pricing constants, mirrored from `app/finance/fee_calculator.py`.
const int kDeliveryBlockPriceCents = 500;
const double kDeliveryBlockSizeKm = 5;

/// Every money component of one checkout, in exact minor units.
@immutable
class OrderQuote {
  OrderQuote({
    required this.subtotal,
    required this.deliveryFee,
    required this.serviceFee,
    required this.tax,
    required this.tip,
    required this.discount,
    required this.mode,
    this.freeDeliveryFromPromo = false,
  }) : assert(
          subtotal.currency == deliveryFee.currency &&
              subtotal.currency == serviceFee.currency &&
              subtotal.currency == tip.currency &&
              subtotal.currency == discount.currency,
          'Every component of a quote must share one currency',
        );

  /// A quote for an empty cart.
  factory OrderQuote.empty([String currency = kDefaultCurrency]) => OrderQuote(
        subtotal: Money.zero(currency),
        deliveryFee: Money.zero(currency),
        serviceFee: Money.zero(currency),
        tax: Money.zero(currency),
        tip: Money.zero(currency),
        discount: Money.zero(currency),
        mode: FulfilmentMode.delivery,
      );

  /// Build the quote the checkout screen renders and submits.
  ///
  /// [restaurantDeliveryFee] is the restaurant's configured fee; when it is
  /// null or zero and coordinates are available, the backend's block formula is
  /// applied so the quoted fee is the fee that will be charged.
  factory OrderQuote.forCart({
    required Money subtotal,
    required FulfilmentMode mode,
    Money? restaurantDeliveryFee,
    double? restaurantLat,
    double? restaurantLng,
    double? dropoffLat,
    double? dropoffLng,
    Money? tip,
    Money? discount,
    Money? tax,
    bool freeDeliveryFromPromo = false,
  }) {
    final currency = subtotal.currency;
    final zero = Money.zero(currency);

    Money delivery;
    if (mode == FulfilmentMode.pickup || freeDeliveryFromPromo) {
      delivery = zero;
    } else if (restaurantDeliveryFee != null && restaurantDeliveryFee.isPositive) {
      delivery = restaurantDeliveryFee;
    } else {
      delivery = estimatedDeliveryFee(
        restaurantLat: restaurantLat,
        restaurantLng: restaurantLng,
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
        currency: currency,
      );
    }

    final service = subtotal.isZero
        ? zero
        : subtotal.basisPoints(kServiceFeeBasisPoints).clampRange(
              low: Money.minorUnits(kServiceFeeMinCents, currency: currency),
              high: Money.minorUnits(kServiceFeeMaxCents, currency: currency),
            );

    return OrderQuote(
      subtotal: subtotal,
      deliveryFee: delivery,
      serviceFee: service,
      tax: tax ?? zero,
      tip: tip ?? zero,
      discount: discount ?? zero,
      mode: mode,
      freeDeliveryFromPromo: freeDeliveryFromPromo,
    );
  }

  final Money subtotal;
  final Money deliveryFee;
  final Money serviceFee;
  final Money tax;
  final Money tip;

  /// Promo discount, stored positive and subtracted.
  final Money discount;

  final FulfilmentMode mode;

  /// True when a promo waived the delivery fee (shown as a struck-through fee).
  final bool freeDeliveryFromPromo;

  String get currency => subtotal.currency;

  /// Everything except the tip — the figure the "before tip" row shows.
  Money get totalBeforeTip =>
      (subtotal + deliveryFee + serviceFee + tax - discount).orZeroIfNegative;

  /// What the customer is charged. Mirrors
  /// `FeeBreakdown.customer_total_minor` on the backend exactly.
  Money get total => (totalBeforeTip + tip).orZeroIfNegative;

  bool get hasDiscount => discount.isPositive;
  bool get isPickup => mode == FulfilmentMode.pickup;

  /// The invariant this class exists for. Called by the checkout screen before
  /// it enables the pay button, and asserted in debug builds.
  bool get reconciles {
    final rebuilt = subtotal.minor +
        deliveryFee.minor +
        serviceFee.minor +
        tax.minor +
        tip.minor -
        discount.minor;
    return math.max(rebuilt, 0) == total.minor;
  }

  OrderQuote copyWith({
    Money? subtotal,
    Money? deliveryFee,
    Money? serviceFee,
    Money? tax,
    Money? tip,
    Money? discount,
    FulfilmentMode? mode,
    bool? freeDeliveryFromPromo,
  }) =>
      OrderQuote(
        subtotal: subtotal ?? this.subtotal,
        deliveryFee: deliveryFee ?? this.deliveryFee,
        serviceFee: serviceFee ?? this.serviceFee,
        tax: tax ?? this.tax,
        tip: tip ?? this.tip,
        discount: discount ?? this.discount,
        mode: mode ?? this.mode,
        freeDeliveryFromPromo:
            freeDeliveryFromPromo ?? this.freeDeliveryFromPromo,
      );

  /// The backend's `$5 per started 5 km block` fee, so the quote matches the
  /// charge when the restaurant has no configured fee.
  static Money estimatedDeliveryFee({
    double? restaurantLat,
    double? restaurantLng,
    double? dropoffLat,
    double? dropoffLng,
    String currency = kDefaultCurrency,
  }) {
    if (restaurantLat == null ||
        restaurantLng == null ||
        dropoffLat == null ||
        dropoffLng == null) {
      // One block is the backend's floor for an unknown distance.
      return Money.minorUnits(kDeliveryBlockPriceCents, currency: currency);
    }
    final km = haversineKm(restaurantLat, restaurantLng, dropoffLat, dropoffLng);
    final blocks = km <= 0 ? 1 : math.max(1, (km / kDeliveryBlockSizeKm).ceil());
    return Money.minorUnits(kDeliveryBlockPriceCents * blocks,
        currency: currency);
  }

  /// Great-circle distance in km (the backend uses the same formula).
  static double haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    double toRad(double deg) => deg * math.pi / 180.0;
    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
