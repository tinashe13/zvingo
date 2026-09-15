/// How the customer is paying, which decides whether the driver has to collect
/// anything at the door.
enum PaymentMethod {
  cash,
  ecocash;

  /// The backend sends `payment_method` as an int (`0` = cash, `1` = EcoCash).
  factory PaymentMethod.fromInt(int value) =>
      value == 0 ? PaymentMethod.cash : PaymentMethod.ecocash;

  String get displayName => switch (this) {
        cash => 'Cash',
        ecocash => 'EcoCash',
      };

  /// True when the driver has to take money at the door. Drives the "collect
  /// $X" reminder on the handover screen.
  bool get isCollectedByDriver => this == PaymentMethod.cash;
}

/// One delivery offer, and — once accepted — the job the driver is carrying.
///
/// The same object survives acceptance rather than being thrown away, because
/// every downstream screen needs the addresses and coordinates that only exist
/// here. (`/dispatch/state` returns a thinner version on resume; see
/// [OrderOffer.fromDispatchState].)
class OrderOffer {
  final String orderId;
  final String shortId;
  final String merchantName;
  final String merchantAddress;
  final double pickupLat;
  final double pickupLng;
  final String customerName;
  final String customerAddress;
  final double deliveryLat;
  final double deliveryLng;
  final int deliveryFeeCents;
  final int totalCents;
  final double estimatedDistanceKm;
  final double pickupDistanceKm;
  final int estimatedTimeMinutes;
  final int pickupTimeMinutes;
  final PaymentMethod paymentMethod;
  final String orderType;
  final String itemsSummary;
  final int itemCount;
  final int tipCents;
  final int orderSubtotalCents;
  final int timeoutSeconds;

  /// Device clock at the moment this offer reached the app.
  ///
  /// Deliberately local, not the server's `timestamp`: the countdown has to be
  /// honest on a phone whose clock is minutes out, and an offer that looks
  /// expired the instant it arrives is worse than one that expires a second
  /// late.
  final int receivedAt;

  OrderOffer({
    required this.orderId,
    required this.shortId,
    required this.merchantName,
    required this.merchantAddress,
    this.pickupLat = 0,
    this.pickupLng = 0,
    this.customerName = 'Customer',
    this.customerAddress = '',
    this.deliveryLat = 0,
    this.deliveryLng = 0,
    required this.deliveryFeeCents,
    this.totalCents = 0,
    this.tipCents = 0,
    this.orderSubtotalCents = 0,
    this.estimatedDistanceKm = 0,
    this.pickupDistanceKm = 0,
    this.estimatedTimeMinutes = 0,
    this.pickupTimeMinutes = 0,
    this.paymentMethod = PaymentMethod.ecocash,
    this.orderType = 'delivery',
    this.itemsSummary = '',
    this.itemCount = 0,
    this.timeoutSeconds = 45,
    int? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// True once the offer window has closed. Accepting past this point can only
  /// fail server-side, so the UI must stop offering it.
  bool get isExpired => remainingSeconds <= 0;

  /// Whole seconds left in the offer window, floored at zero.
  int get remainingSeconds {
    final elapsed = (DateTime.now().millisecondsSinceEpoch - receivedAt) ~/ 1000;
    return (timeoutSeconds - elapsed).clamp(0, timeoutSeconds);
  }

  /// True when the offer carries real coordinates for both ends. Dispatch
  /// refuses to send orders whose pickup is Null Island, but a resumed job can
  /// still arrive without a drop-off point, and navigating to (0, 0) would send
  /// a driver into the Atlantic.
  bool get hasPickupCoords => pickupLat != 0 || pickupLng != 0;
  bool get hasDeliveryCoords => deliveryLat != 0 || deliveryLng != 0;

  /// Take-home for this job in cents: the driver's share of the delivery fee
  /// plus the whole tip. Mirrors `OfferCard.payoutCents`, and
  /// `driver_share_minor` on the backend.
  int payoutCents({double driverFeeShare = 0.85}) =>
      (deliveryFeeCents * driverFeeShare).round() + tipCents;

  /// Cash the driver must collect at the door, in cents. Zero for prepaid
  /// orders.
  int get cashToCollectCents =>
      paymentMethod.isCollectedByDriver ? totalCents : 0;

  OrderOffer copyWith({
    String? shortId,
    String? merchantName,
    String? merchantAddress,
    double? pickupLat,
    double? pickupLng,
    String? customerName,
    String? customerAddress,
    double? deliveryLat,
    double? deliveryLng,
    int? deliveryFeeCents,
    int? totalCents,
    int? receivedAt,
  }) {
    return OrderOffer(
      orderId: orderId,
      shortId: shortId ?? this.shortId,
      merchantName: merchantName ?? this.merchantName,
      merchantAddress: merchantAddress ?? this.merchantAddress,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      customerName: customerName ?? this.customerName,
      customerAddress: customerAddress ?? this.customerAddress,
      deliveryLat: deliveryLat ?? this.deliveryLat,
      deliveryLng: deliveryLng ?? this.deliveryLng,
      deliveryFeeCents: deliveryFeeCents ?? this.deliveryFeeCents,
      totalCents: totalCents ?? this.totalCents,
      tipCents: tipCents,
      orderSubtotalCents: orderSubtotalCents,
      estimatedDistanceKm: estimatedDistanceKm,
      pickupDistanceKm: pickupDistanceKm,
      estimatedTimeMinutes: estimatedTimeMinutes,
      pickupTimeMinutes: pickupTimeMinutes,
      paymentMethod: paymentMethod,
      orderType: orderType,
      itemsSummary: itemsSummary,
      itemCount: itemCount,
      timeoutSeconds: timeoutSeconds,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  /// Parse the dispatch offer payload
  /// (`NotificationService._build_offer_payload`).
  factory OrderOffer.fromJson(Map<String, dynamic> json) {
    return OrderOffer(
      orderId: json['order_id'] as String? ?? '',
      shortId: json['short_id'] as String? ?? '',
      merchantName: json['merchant_name'] as String? ?? '',
      merchantAddress: json['merchant_address'] as String? ?? '',
      pickupLat: (json['pickup_lat'] as num?)?.toDouble() ?? 0,
      pickupLng: (json['pickup_lng'] as num?)?.toDouble() ?? 0,
      customerName: json['customer_name'] as String? ?? 'Customer',
      customerAddress: json['customer_address'] as String? ?? '',
      deliveryLat: (json['delivery_lat'] as num?)?.toDouble() ?? 0,
      deliveryLng: (json['delivery_lng'] as num?)?.toDouble() ?? 0,
      deliveryFeeCents: (json['delivery_fee_cents'] as num?)?.toInt() ?? 0,
      totalCents: (json['total_cents'] as num?)?.toInt() ?? 0,
      tipCents: (json['tip_cents'] as num?)?.toInt() ?? 0,
      orderSubtotalCents: (json['order_subtotal_cents'] as num?)?.toInt() ?? 0,
      estimatedDistanceKm:
          (json['estimated_distance_km'] as num?)?.toDouble() ?? 0,
      pickupDistanceKm: (json['pickup_distance_km'] as num?)?.toDouble() ?? 0,
      estimatedTimeMinutes:
          (json['estimated_time_minutes'] as num?)?.toInt() ?? 0,
      pickupTimeMinutes: (json['pickup_time_minutes'] as num?)?.toInt() ?? 0,
      paymentMethod:
          PaymentMethod.fromInt((json['payment_method'] as num?)?.toInt() ?? 1),
      orderType: json['order_type'] as String? ?? 'delivery',
      itemsSummary: json['items_summary'] as String? ?? '',
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      timeoutSeconds: (json['timeout_seconds'] as num?)?.toInt() ?? 45,
    );
  }

  /// Rebuild the in-flight job from `GET /dispatch/state`'s `active_order`.
  ///
  /// That payload is deliberately thin — order id, short id, state and the two
  /// GeoJSON points — but the coordinates are the part the navigation screens
  /// cannot do without. Before this existed, a driver who restarted the app
  /// mid-delivery was navigated to a hardcoded point in central Harare.
  ///
  /// `pickup` / `dropoff` are GeoJSON `Point`s, so `coordinates` is
  /// **[longitude, latitude]** — the one ordering mistake that silently sends
  /// someone to the wrong hemisphere.
  static OrderOffer? fromDispatchState(Map<String, dynamic> activeOrder) {
    final orderId = activeOrder['order_id'] as String?;
    if (orderId == null || orderId.isEmpty) return null;

    final pickup = _pointOf(activeOrder['pickup']);
    final dropoff = _pointOf(activeOrder['dropoff']);

    return OrderOffer(
      orderId: orderId,
      shortId: activeOrder['short_id'] as String? ??
          'ZV${orderId.length >= 6 ? orderId.substring(orderId.length - 6).toUpperCase() : orderId.toUpperCase()}',
      merchantName: activeOrder['merchant_name'] as String? ?? 'Restaurant',
      merchantAddress: activeOrder['merchant_address'] as String? ?? '',
      pickupLat: pickup?.$1 ?? 0,
      pickupLng: pickup?.$2 ?? 0,
      customerName: activeOrder['customer_name'] as String? ?? 'Customer',
      customerAddress: activeOrder['customer_address'] as String? ?? '',
      deliveryLat: dropoff?.$1 ?? 0,
      deliveryLng: dropoff?.$2 ?? 0,
      deliveryFeeCents: (activeOrder['delivery_fee_cents'] as num?)?.toInt() ?? 0,
      totalCents: (activeOrder['total_cents'] as num?)?.toInt() ?? 0,
      tipCents: (activeOrder['tip_cents'] as num?)?.toInt() ?? 0,
    );
  }

  /// `(lat, lng)` from a GeoJSON `Point`, or null when the field is missing or
  /// malformed.
  static (double, double)? _pointOf(Object? value) {
    if (value is! Map) return null;
    final coords = value['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final lng = (coords[0] as num?)?.toDouble();
    final lat = (coords[1] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return (lat, lng);
  }
}
