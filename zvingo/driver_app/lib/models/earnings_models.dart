/// Daily earnings summary for the earnings screen.
class DailySummary {
  final String date;
  final int earningsCents;
  final int tipCents;
  final int tripCount;
  final int cashCollectedCents;

  const DailySummary({
    required this.date,
    required this.earningsCents,
    required this.tripCount,
    this.tipCents = 0,
    this.cashCollectedCents = 0,
  });

  factory DailySummary.fromJson(Map<String, dynamic> json) {
    return DailySummary(
      date: json['date'] ?? '',
      earningsCents: json['earnings_cents'] ?? 0,
      tipCents: json['tip_cents'] ?? 0,
      tripCount: json['trip_count'] ?? 0,
      cashCollectedCents: json['cash_collected_cents'] ?? 0,
    );
  }

    int get totalEarningsCents => earningsCents + tipCents;

    String get formattedEarnings =>
      '\$${(totalEarningsCents / 100).toStringAsFixed(2)}';

  String get formattedTips =>
      '\$${(tipCents / 100).toStringAsFixed(2)}';
}
