/// Model for a single delivery earning record from the backend.
/// Used in the earnings reconciliation / history view.
class DriverEarningRecord {
  final String id;
  final String orderId;
  final String merchantName;
  final String pickupArea;
  final String dropoffArea;
  final int deliveryFeeCents;
  final int driverEarningCents;
  final int tipCents;
  final int totalEarningCents;
  final String paymentMethod;
  final double distanceKm;
  final DateTime completedAt;

  const DriverEarningRecord({
    required this.id,
    required this.orderId,
    required this.merchantName,
    this.pickupArea = '',
    this.dropoffArea = '',
    this.deliveryFeeCents = 0,
    this.driverEarningCents = 0,
    this.tipCents = 0,
    this.totalEarningCents = 0,
    this.paymentMethod = 'cash',
    this.distanceKm = 0.0,
    required this.completedAt,
  });

  factory DriverEarningRecord.fromJson(Map<String, dynamic> json) {
    return DriverEarningRecord(
      id: json['id'] ?? '',
      orderId: json['order_id'] ?? '',
      merchantName: json['merchant_name'] ?? 'Unknown',
      pickupArea: json['pickup_area'] ?? '',
      dropoffArea: json['dropoff_area'] ?? '',
      deliveryFeeCents: json['delivery_fee_cents'] ?? 0,
      driverEarningCents: json['driver_earning_cents'] ?? 0,
      tipCents: json['tip_cents'] ?? 0,
      totalEarningCents: json['total_earning_cents'] ?? 0,
      paymentMethod: json['payment_method'] ?? 'cash',
      distanceKm: (json['distance_km'] ?? 0.0).toDouble(),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : DateTime.now(),
    );
  }

  String get formattedEarnings =>
      '\$${(totalEarningCents / 100).toStringAsFixed(2)}';

  String get formattedDriverEarnings =>
      '\$${(driverEarningCents / 100).toStringAsFixed(2)}';

  String get formattedTip =>
      '\$${(tipCents / 100).toStringAsFixed(2)}';

  String get formattedDistance => '${distanceKm.toStringAsFixed(1)} km';

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(completedAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${completedAt.day}/${completedAt.month}/${completedAt.year}';
  }

  String get formattedDateTime {
    final h = completedAt.hour.toString().padLeft(2, '0');
    final m = completedAt.minute.toString().padLeft(2, '0');
    final d = completedAt.day.toString().padLeft(2, '0');
    final mo = completedAt.month.toString().padLeft(2, '0');
    return '$d/$mo/${completedAt.year} $h:$m';
  }

  String get routeDescription {
    if (pickupArea.isNotEmpty && dropoffArea.isNotEmpty) {
      return '$pickupArea → $dropoffArea';
    }
    if (pickupArea.isNotEmpty) return pickupArea;
    return merchantName;
  }
}
