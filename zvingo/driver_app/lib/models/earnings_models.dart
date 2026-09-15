import 'dart:math' as math;

/// Money formatting and currency handling for the driver app.
///
/// Every amount that crosses the API boundary is an **integer minor unit**
/// (cents). Nothing in the UI layer may divide by 100 into a `double` and then
/// add — a driver who cannot reconcile their pay to the cent stops trusting
/// the platform, and binary floating point is exactly how a total ends up
/// $0.01 off the sum of its parts.
///
/// The rule this file enforces:
///
/// * **Add, subtract and compare in `int` cents.**
/// * **Divide by 100 exactly once**, at the moment of rendering.
///
/// Zvingo is multi-currency (USD primary, ZIG, ZAR). The backend's driver
/// earnings ledger posts in USD today (`app/finance/router.py` →
/// `build_driver_payout_posting(currency="USD")`) and `DriverEarning` carries
/// no currency field, so [Money.usd] is the default. When the backend starts
/// sending `currency`, [Money.parse] picks it up with no other change here.
class Money {
  /// Amount in integer minor units (cents for all three supported currencies).
  final int cents;

  /// ISO 4217 code: `USD`, `ZIG` or `ZAR`.
  final String currency;

  const Money(this.cents, [this.currency = usd]);

  static const String usd = 'USD';
  static const String zig = 'ZIG';
  static const String zar = 'ZAR';

  /// Zero in [currency] — the identity for [+].
  const Money.zero([this.currency = usd]) : cents = 0;

  /// Reads `{amount}_cents` style integers off a JSON map.
  ///
  /// Anything that is not an integer (a stray `double`, a string, a null)
  /// becomes 0 rather than throwing: a malformed field must not blank the
  /// whole earnings screen.
  factory Money.parse(Object? value, [String currency = usd]) {
    if (value is int) return Money(value, currency);
    if (value is num) return Money(value.round(), currency);
    if (value is String) return Money(int.tryParse(value) ?? 0, currency);
    return Money(0, currency);
  }

  /// The symbol drivers actually recognise for each currency.
  static String symbolFor(String currency) => switch (currency.toUpperCase()) {
        zig => 'ZiG ',
        zar => 'R',
        _ => r'$',
      };

  String get symbol => symbolFor(currency);

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;

  Money operator +(Money other) => Money(cents + other.cents, currency);
  Money operator -(Money other) => Money(cents - other.cents, currency);
  Money operator -() => Money(-cents, currency);

  /// `$23.65`. Always carries an explicit symbol (§ brief: money never renders
  /// bare). The single division by 100 lives here and nowhere else.
  String get formatted => format(cents, currency);

  /// `+$2.50` / `−$1.50` — for signed rows in a reconciliation breakdown,
  /// where the sign is the whole point. Uses a real minus sign (U+2212), which
  /// is the same width as a digit in a tabular-figures font.
  String get signed {
    if (cents == 0) return formatted;
    final magnitude = format(cents.abs(), currency);
    return cents > 0 ? '+$magnitude' : '−$magnitude';
  }

  /// Formats integer minor units as display money.
  static String format(int cents, [String currency = usd]) {
    final sign = cents < 0 ? '-' : '';
    final absolute = cents.abs();
    final major = absolute ~/ 100;
    final minor = (absolute % 100).toString().padLeft(2, '0');
    return '$sign${symbolFor(currency)}${_grouped(major)}.$minor';
  }

  /// Thousands separators, so `$1,240.00` does not read as `$124000`.
  static String _grouped(int value) {
    final digits = value.toString();
    if (digits.length <= 3) return digits;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.cents == cents && other.currency == currency;

  @override
  int get hashCode => Object.hash(cents, currency);

  @override
  String toString() => formatted;
}

/// One line of a per-delivery pay breakdown.
///
/// A breakdown is only trustworthy if its lines *sum to the total*. Every
/// component the driver is shown is a [PayLine] and
/// [EarningsBreakdown.reconciles] asserts the sum.
class PayLine {
  /// What the driver sees, e.g. "Base fare" or "Zvingo service fee".
  final String label;

  /// One line explaining where the number comes from. Never marketing copy.
  final String explanation;

  /// Signed contribution to the payout, in minor units.
  final Money amount;

  /// True when this line reduces the payout (the platform's commission).
  final bool isDeduction;

  const PayLine({
    required this.label,
    required this.explanation,
    required this.amount,
    this.isDeduction = false,
  });
}

/// The delivery-fee pricing model the backend actually charges, mirrored here
/// only so a breakdown can *explain* a fee it already received — never to
/// compute one.
///
/// `app/finance/fee_calculator.py`: `blocks = ceil(distance_km / 5)`,
/// `gross_fee = blocks * $5`. Both numbers are server settings
/// (`DELIVERY_BLOCK_SIZE_KM`, `DELIVERY_BLOCK_PRICE_USD`), so the split below
/// is *verified* against the fee the server sent and abandoned if it does not
/// divide exactly. A guessed split is worse than no split.
class FarePricing {
  FarePricing._();

  static const double blockSizeKm = 5.0;

  /// Splits a gross delivery fee into (base block, distance blocks).
  ///
  /// Returns null when the received fee is not an exact multiple of a plausible
  /// block price for this distance — a custom fee on the order, a promo, or a
  /// changed server setting. Callers then show one undivided "Delivery fee"
  /// line, which still reconciles.
  static ({Money base, Money distance, int blocks})? split(
    Money deliveryFee,
    double distanceKm,
  ) {
    if (deliveryFee.cents <= 0) return null;
    final blocks = math.max(1, (distanceKm / blockSizeKm).ceil());
    if (blocks <= 0) return null;
    if (deliveryFee.cents % blocks != 0) return null;
    final blockPrice = deliveryFee.cents ~/ blocks;
    // A block price outside $1–$50 means our model of the server's pricing is
    // wrong; say nothing rather than invent a breakdown.
    if (blockPrice < 100 || blockPrice > 5000) return null;
    return (
      base: Money(blockPrice, deliveryFee.currency),
      distance: Money(deliveryFee.cents - blockPrice, deliveryFee.currency),
      blocks: blocks,
    );
  }
}

/// A fully reconciled pay breakdown for one delivery.
///
/// Contract (`backend/app/finance/router.py` → `/finance/earnings/...`):
///
/// ```
/// driver_earning_cents = round_half_even(delivery_fee_cents * DRIVER_SHARE_RATIO)
/// platform_commission  = delivery_fee_cents - driver_earning_cents   (exact remainder)
/// total_earning_cents  = driver_earning_cents + tip_cents
/// ```
///
/// So the driver's payout is
/// `delivery_fee − platform_commission + tip (+ bonus)`, and those four terms
/// are exactly the rows rendered on screen.
class EarningsBreakdown {
  final Money deliveryFee;
  final Money platformFee;
  final Money driverShare;
  final Money tip;
  final Money bonus;
  final Money total;
  final double distanceKm;

  const EarningsBreakdown({
    required this.deliveryFee,
    required this.platformFee,
    required this.driverShare,
    required this.tip,
    required this.bonus,
    required this.total,
    this.distanceKm = 0,
  });

  /// The rows to render, in the order a driver reads them. Each signed amount
  /// adds up to [total] — see [reconciles].
  List<PayLine> get lines {
    final rows = <PayLine>[];
    final split = FarePricing.split(deliveryFee, distanceKm);

    if (split != null && split.blocks > 1) {
      final extraKm = distanceKm - FarePricing.blockSizeKm;
      rows.add(PayLine(
        label: 'Base fare',
        explanation:
            'First ${FarePricing.blockSizeKm.toStringAsFixed(0)} km of the trip',
        amount: split.base,
      ));
      rows.add(PayLine(
        label: 'Distance',
        explanation:
            '${extraKm.toStringAsFixed(1)} km beyond the base, charged in '
            '${FarePricing.blockSizeKm.toStringAsFixed(0)} km blocks',
        amount: split.distance,
      ));
    } else {
      rows.add(PayLine(
        label: 'Delivery fee',
        explanation: distanceKm > 0
            ? 'Charged to the customer for ${distanceKm.toStringAsFixed(1)} km'
            : 'Charged to the customer for this trip',
        amount: deliveryFee,
      ));
    }

    if (platformFee.isPositive) {
      rows.add(PayLine(
        label: 'Zvingo service fee',
        explanation: 'Platform share of the delivery fee',
        amount: -platformFee,
        isDeduction: true,
      ));
    }

    if (tip.isPositive) {
      rows.add(PayLine(
        label: 'Customer tip',
        explanation: 'Tips go to you in full — Zvingo takes nothing',
        amount: tip,
      ));
    }

    if (bonus.isPositive) {
      rows.add(PayLine(
        label: 'Bonus',
        explanation: 'Promotion or incentive applied to this delivery',
        amount: bonus,
      ));
    }

    return rows;
  }

  /// Sum of the rendered rows.
  Money get lineSum => lines.fold(
        Money.zero(total.currency),
        (running, line) => running + line.amount,
      );

  /// True when what is on screen adds up to the headline figure, to the cent.
  ///
  /// If this is ever false the UI says so out loud instead of quietly showing
  /// numbers that do not agree — a visible discrepancy a driver can report
  /// beats a hidden one they only notice on payday.
  bool get reconciles => lineSum.cents == total.cents;

  /// The gap, when it does not reconcile. Zero when it does.
  Money get discrepancy => total - lineSum;
}

/// Daily earnings aggregate — one row of `GET /finance/earnings/driver/{id}/daily`.
///
/// **Contract note (this was a real bug):** the backend builds
/// `earnings_cents` by summing `DriverEarning.total_earning_cents`, and that
/// field is *already* `driver_earning + tip`. `tip_cents` is reported
/// alongside it as an informational split, **not** as an extra amount to add.
/// The previous client did `earnings_cents + tip_cents`, which overstated
/// every daily total by the value of its tips.
class DailySummary {
  /// `YYYY-MM-DD`, in the server's day boundary.
  final String date;

  /// Take-home for the day — already includes tips.
  final Money earnings;

  /// How much of [earnings] was tips. A component, not an addition.
  final Money tips;

  /// Cash the driver physically collected and owes Zvingo.
  final Money cashCollected;

  final int tripCount;

  const DailySummary({
    required this.date,
    required this.earnings,
    required this.tripCount,
    this.tips = const Money.zero(),
    this.cashCollected = const Money.zero(),
  });

  factory DailySummary.fromJson(Map<String, dynamic> json) {
    final currency = (json['currency'] as String?) ?? Money.usd;
    return DailySummary(
      date: (json['date'] as String?) ?? '',
      earnings: Money.parse(json['earnings_cents'], currency),
      tips: Money.parse(json['tip_cents'], currency),
      cashCollected: Money.parse(json['cash_collected_cents'], currency),
      tripCount: (json['trip_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// The day's take-home. Identical to [earnings]; kept as a named getter so
  /// call sites read as an intention rather than a field access.
  Money get total => earnings;

  /// Earnings excluding tips — the fare portion.
  Money get fareEarnings => earnings - tips;

  /// Average per trip, or null when there were no trips (never 0/0).
  Money? get perTrip =>
      tripCount > 0 ? Money(earnings.cents ~/ tripCount, earnings.currency) : null;

  /// `Mon 15 Sep` for the row header, or the raw string if unparseable.
  String get displayDate {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    return DateLabels.dayMonth(parsed);
  }

  /// "Today" / "Yesterday" / weekday name, relative to [now].
  String relativeLabel([DateTime? now]) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    return DateLabels.relative(parsed, now);
  }
}

/// Human date labels, in one place so history grouping and daily rows agree.
class DateLabels {
  DateLabels._();

  static const List<String> weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `15 Sep 2026`.
  static String full(DateTime date) =>
      '${date.day} ${months[date.month - 1]} ${date.year}';

  /// `Mon 15 Sep`.
  static String dayMonth(DateTime date) =>
      '${weekdays[date.weekday - 1].substring(0, 3)} ${date.day} ${months[date.month - 1]}';

  /// `Today`, `Yesterday`, a weekday name within the last week, else `15 Sep`.
  static String relative(DateTime date, [DateTime? now]) {
    final today = _dayOf(now ?? DateTime.now());
    final day = _dayOf(date);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff < 7) return weekdays[day.weekday - 1];
    if (day.year == today.year) return '${day.day} ${months[day.month - 1]}';
    return full(day);
  }

  /// `14:05` — 24h, which is what a Zimbabwean driver's phone shows.
  static String time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
