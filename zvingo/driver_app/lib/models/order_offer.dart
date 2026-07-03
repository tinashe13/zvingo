/// Payment method for an order.
enum PaymentMethod {
  cash,
  ecocash;

  factory PaymentMethod.fromInt(int value) =>
      value == 0 ? PaymentMethod.cash : PaymentMethod.ecocash;

  String get displayName => switch (this) {
        cash => 'Cash',
        ecocash => 'EcoCash',
      };
}

/// Data class for an incoming delivery offer — mirrors OrderOffer.kt.
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

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch - receivedAt > timeoutSeconds * 1000;

  int get remainingSeconds {
    final elapsed = (DateTime.now().millisecondsSinceEpoch - receivedAt) ~/ 1000;
    return (timeoutSeconds - elapsed).clamp(0, timeoutSeconds);
  }

  /// Parse from server JSON.
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
      estimatedDistanceKm: (json['estimated_distance_km'] as num?)?.toDouble() ?? 0,
      pickupDistanceKm: (json['pickup_distance_km'] as num?)?.toDouble() ?? 0,
      estimatedTimeMinutes: (json['estimated_time_minutes'] as num?)?.toInt() ?? 0,
      pickupTimeMinutes: (json['pickup_time_minutes'] as num?)?.toInt() ?? 0,
      paymentMethod: PaymentMethod.fromInt((json['payment_method'] as num?)?.toInt() ?? 1),
      orderType: json['order_type'] as String? ?? 'delivery',
      itemsSummary: json['items_summary'] as String? ?? '',
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      timeoutSeconds: (json['timeout_seconds'] as num?)?.toInt() ?? 45,
    );
  }
}
