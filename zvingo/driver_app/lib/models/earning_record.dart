import 'earnings_models.dart';

/// One completed delivery, as returned by
/// `GET /finance/earnings/driver/{driver_id}/history`.
///
/// Field-for-field mirror of `DriverEarning` in
/// `backend/app/finance/models.py`. Addresses arrive already masked
/// (`mask_address` strips the street number), so nothing here re-masks them.
///
/// Every money field is integer minor units. The class deliberately exposes no
/// `double` amount: arithmetic on these values happens in [breakdown], in
/// cents, and the division by 100 happens once inside [Money.format].
class DriverEarningRecord {
  final String id;
  final String orderId;
  final String merchantName;

  /// Masked pickup address, e.g. `** Selous Ave, Harare`.
  final String pickupArea;

  /// Masked dropoff address.
  final String dropoffArea;

  /// Gross delivery fee the customer paid for this trip.
  final Money deliveryFee;

  /// The driver's share of [deliveryFee] (85% by default, banker's rounded
  /// server-side — never recomputed here).
  final Money driverEarning;

  /// Customer tip. Passes through to the driver in full.
  final Money tip;

  /// Any incentive or promotion. The backend does not send this yet
  /// (`DriverEarning` has no bonus column) so it is 0 until it does; the row
  /// is simply not rendered while it is zero.
  final Money bonus;

  /// What the driver was actually paid for this delivery. Authoritative.
  final Money total;

  /// `cash` or a mobile-money method such as `ecocash`.
  final String paymentMethod;

  final double distanceKm;
  final DateTime completedAt;

  const DriverEarningRecord({
    required this.id,
    required this.orderId,
    required this.merchantName,
    required this.completedAt,
    this.pickupArea = '',
    this.dropoffArea = '',
    this.deliveryFee = const Money.zero(),
    this.driverEarning = const Money.zero(),
    this.tip = const Money.zero(),
    this.bonus = const Money.zero(),
    this.total = const Money.zero(),
    this.paymentMethod = 'cash',
    this.distanceKm = 0.0,
  });

  factory DriverEarningRecord.fromJson(Map<String, dynamic> json) {
    final currency = (json['currency'] as String?) ?? Money.usd;
    return DriverEarningRecord(
      id: (json['id'] as String?) ?? '',
      orderId: (json['order_id'] as String?) ?? '',
      merchantName: (json['merchant_name'] as String?) ?? 'Unknown merchant',
      pickupArea: (json['pickup_area'] as String?) ?? '',
      dropoffArea: (json['dropoff_area'] as String?) ?? '',
      deliveryFee: Money.parse(json['delivery_fee_cents'], currency),
      driverEarning: Money.parse(json['driver_earning_cents'], currency),
      tip: Money.parse(json['tip_cents'], currency),
      bonus: Money.parse(json['bonus_cents'], currency),
      total: Money.parse(json['total_earning_cents'], currency),
      paymentMethod:
          ((json['payment_method'] as String?) ?? 'cash').toLowerCase(),
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      completedAt:
          DateTime.tryParse(json['completed_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }

  /// Zvingo's cut, derived as the exact remainder of the delivery fee — the
  /// same way `commission_minor()` derives it server-side, which is what makes
  /// the split reconcile to the cent for every amount.
  Money get platformFee => deliveryFee - driverEarning;

  /// The line-by-line breakdown shown in the drill-down. Its rows sum to
  /// [total]; see [EarningsBreakdown.reconciles].
  EarningsBreakdown get breakdown => EarningsBreakdown(
        deliveryFee: deliveryFee,
        platformFee: platformFee,
        driverShare: driverEarning,
        tip: tip,
        bonus: bonus,
        total: total,
        distanceKm: distanceKm,
      );

  /// Does the server's own arithmetic hold for this record?
  ///
  /// `total_earning_cents` must equal `driver_earning_cents + tip_cents`
  /// (+ bonus once that exists). When it does not, the record is flagged in
  /// the UI rather than silently rendered — a driver noticing a bad line and
  /// being able to report it is the whole point of a reconciliation screen.
  bool get reconciles =>
      driverEarning.cents + tip.cents + bonus.cents == total.cents;

  /// True when the driver physically holds the customer's cash for this trip.
  bool get isCash => paymentMethod == 'cash';

  /// `EcoCash` / `Cash` / `OneMoney` — title-cased for display.
  String get paymentLabel {
    switch (paymentMethod) {
      case 'cash':
        return 'Cash';
      case 'ecocash':
        return 'EcoCash';
      case 'onemoney':
        return 'OneMoney';
      case 'innbucks':
        return 'InnBucks';
      case 'card':
        return 'Card';
      default:
        if (paymentMethod.isEmpty) return 'Unknown';
        return paymentMethod[0].toUpperCase() + paymentMethod.substring(1);
    }
  }

  /// `4.2 km`.
  String get formattedDistance => '${distanceKm.toStringAsFixed(1)} km';

  /// `14:05` — the time of day the delivery closed out.
  String get formattedTime => DateLabels.time(completedAt);

  /// `15 Sep 2026 · 14:05`.
  String get formattedDateTime =>
      '${DateLabels.full(completedAt)} · $formattedTime';

  /// The day this delivery belongs to, used to group the history list.
  DateTime get day =>
      DateTime(completedAt.year, completedAt.month, completedAt.day);

  /// `** Selous Ave → ** Samora Machel Ave`, or whatever part of it is known.
  String get routeDescription {
    if (pickupArea.isNotEmpty && dropoffArea.isNotEmpty) {
      return '$pickupArea → $dropoffArea';
    }
    if (pickupArea.isNotEmpty) return pickupArea;
    if (dropoffArea.isNotEmpty) return dropoffArea;
    return merchantName;
  }

  /// A short order reference a driver can quote to support. Order ids are
  /// Mongo ObjectIds; the last six characters are enough to find one and short
  /// enough to read out over a phone.
  String get shortOrderRef => orderId.length > 6
      ? '#${orderId.substring(orderId.length - 6).toUpperCase()}'
      : '#${orderId.toUpperCase()}';
}
