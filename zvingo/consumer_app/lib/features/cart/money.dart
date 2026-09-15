/// Integer-minor-unit money for the ordering funnel.
///
/// Rule (§ design-system "money never renders bare", B2 finance contract):
/// **no float ever takes part in an arithmetic step.** The API still hands us
/// `price_usd` as a JSON number, so a conversion happens exactly once, at the
/// boundary, through [Money.fromMajor]. Everything after that — line totals,
/// fees, tips, discounts, promo maths — is integer cents, so a basket can never
/// drift a cent away from what the backend charges.
///
/// Zimbabwe is a multi-currency market (USD prices, settlement in USD / ZIG /
/// ZAR), so a [Money] always carries its currency and [format] always prints a
/// symbol. There is no "bare amount" constructor on purpose.
library;

import 'dart:math' as math;

/// The currency every catalog price is quoted in (`MenuItem.price_usd`).
const String kDefaultCurrency = 'USD';

/// Currencies the backend can settle in — mirrors `app/finance/money.py`'s
/// `CURRENCIES` map. Keep the two in step.
const Map<String, CurrencySpec> kCurrencies = <String, CurrencySpec>{
  'USD': CurrencySpec(code: 'USD', exponent: 2, symbol: r'US$', name: 'US dollar'),
  'ZIG': CurrencySpec(code: 'ZIG', exponent: 2, symbol: 'ZiG', name: 'Zimbabwe Gold'),
  'ZAR': CurrencySpec(code: 'ZAR', exponent: 2, symbol: 'R', name: 'South African rand'),
};

/// Static facts about a currency Zvingo settles in.
class CurrencySpec {
  const CurrencySpec({
    required this.code,
    required this.exponent,
    required this.symbol,
    required this.name,
  });

  /// ISO code, e.g. `USD`.
  final String code;

  /// Number of decimal places, e.g. 2 for cents.
  final int exponent;

  /// Symbol shown to users, e.g. `US$`.
  final String symbol;

  /// Human name, used in the currency picker.
  final String name;

  /// 10^[exponent] — minor units in one major unit.
  int get scale => math.pow(10, exponent).toInt();
}

/// Resolve a currency code, defaulting to USD rather than guessing an exponent
/// (a wrong exponent is a 100× money error).
CurrencySpec currencySpec(String? code) =>
    kCurrencies[(code ?? kDefaultCurrency).trim().toUpperCase()] ??
    kCurrencies[kDefaultCurrency]!;

/// An exact amount of money, held as integer minor units.
class Money implements Comparable<Money> {
  const Money._(this.minor, this.currency);

  /// Build from integer minor units — the canonical constructor.
  factory Money.minorUnits(int minor, {String currency = kDefaultCurrency}) =>
      Money._(minor, currencySpec(currency).code);

  /// Zero in [currency].
  factory Money.zero([String currency = kDefaultCurrency]) =>
      Money._(0, currencySpec(currency).code);

  /// Convert a major-unit value that came from JSON (or a text field) exactly
  /// once, here. Parsing goes through the decimal *string* so `0.1` becomes
  /// 10 cents rather than its binary expansion.
  factory Money.fromMajor(num value, {String currency = kDefaultCurrency}) {
    final spec = currencySpec(currency);
    return Money._(_minorFromString(value.toString(), spec), spec.code);
  }

  /// Parse user input such as `"2.50"`. Returns null when the text is not a
  /// non-negative amount, so a caller can show a field error instead of
  /// silently treating junk as zero.
  static Money? tryParse(String raw, {String currency = kDefaultCurrency}) {
    final text = raw.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(text) || text == '.') return null;
    final spec = currencySpec(currency);
    return Money._(_minorFromString(text, spec), spec.code);
  }

  /// The amount in minor units (cents). All arithmetic uses this.
  final int minor;

  /// ISO currency code this amount is denominated in.
  final String currency;

  CurrencySpec get spec => currencySpec(currency);

  /// Presentation only — never feed this back into arithmetic.
  double get major => minor / spec.scale;

  /// Symbol for this currency, e.g. `US$`.
  String get symbol => spec.symbol;

  bool get isZero => minor == 0;
  bool get isPositive => minor > 0;
  bool get isNegative => minor < 0;

  Money operator +(Money other) {
    _assertSame(other);
    return Money._(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _assertSame(other);
    return Money._(minor - other.minor, currency);
  }

  /// Multiply by a whole number of units (a line quantity).
  Money operator *(int quantity) => Money._(minor * quantity, currency);

  Money operator -() => Money._(-minor, currency);

  bool operator <(Money other) => _cmp(other) < 0;
  bool operator <=(Money other) => _cmp(other) <= 0;
  bool operator >(Money other) => _cmp(other) > 0;
  bool operator >=(Money other) => _cmp(other) >= 0;

  /// [basisPoints]/10000 of this amount, rounded half-up, in integer maths.
  /// `serviceFee = subtotal.basisPoints(1500)` is a 15% fee with no float.
  Money basisPoints(int points) {
    final scaled = minor * points;
    final rounded = (scaled.abs() + 5000) ~/ 10000;
    return Money._(scaled.isNegative ? -rounded : rounded, currency);
  }

  /// Clamp into `[low, high]`; either bound may be omitted.
  Money clampRange({Money? low, Money? high}) {
    var result = this;
    if (low != null && result < low) result = low;
    if (high != null && result > high) result = high;
    return result;
  }

  /// Never below zero — used so a discount can't turn a total negative.
  Money get orZeroIfNegative => isNegative ? Money._(0, currency) : this;

  /// Convert to another currency at [rate] major units per 1 of this currency.
  /// Used only at the payment step, where the backend pins the same rate.
  Money convertTo(String targetCurrency, num rate) {
    final target = currencySpec(targetCurrency);
    final rateMinor = _minorFromString(rate.toString(), const CurrencySpec(
      code: '_rate',
      exponent: 6,
      symbol: '',
      name: '',
    ));
    final converted = (minor * rateMinor + 500000) ~/ 1000000;
    return Money._(converted, target.code);
  }

  /// `US$12.50`, `ZiG1,234.00`. Always carries the symbol (§1.5 / §2).
  String format({bool showSign = false}) {
    final sign = isNegative ? '-' : (showSign && isPositive ? '+' : '');
    final abs = minor.abs();
    final s = spec;
    final whole = (abs ~/ s.scale).toString();
    final frac = (abs % s.scale).toString().padLeft(s.exponent, '0');
    final grouped = _group(whole);
    return s.exponent == 0
        ? '$sign${s.symbol}$grouped'
        : '$sign${s.symbol}$grouped.$frac';
  }

  /// Plain digits with no symbol — for prefilling a text field.
  String toEditableString() =>
      (minor.abs() / spec.scale).toStringAsFixed(spec.exponent);

  @override
  int compareTo(Money other) => _cmp(other);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => format();

  int _cmp(Money other) {
    _assertSame(other);
    return minor.compareTo(other.minor);
  }

  void _assertSame(Money other) {
    assert(
      other.currency == currency,
      'Cannot combine $currency with ${other.currency} — convert first.',
    );
  }

  static String _group(String digits) {
    if (digits.length <= 3) return digits;
    final buffer = StringBuffer();
    final firstGroup = digits.length % 3;
    if (firstGroup > 0) buffer.write(digits.substring(0, firstGroup));
    for (var i = firstGroup; i < digits.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write(',');
      buffer.write(digits.substring(i, i + 3));
    }
    return buffer.toString();
  }

  /// Decimal-string → minor units, rounding half-up at the currency's exponent.
  static int _minorFromString(String raw, CurrencySpec spec) {
    var text = raw.trim();
    if (text.isEmpty) return 0;
    var negative = false;
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.contains('e') || text.contains('E')) {
      // Exponential notation is vanishingly rare for prices; fall back to a
      // single numeric rounding rather than hand-rolling a float parser.
      final value = double.tryParse(text) ?? 0;
      final minor = (value * spec.scale).round();
      return negative ? -minor : minor;
    }
    final dot = text.indexOf('.');
    final wholePart = dot == -1 ? text : text.substring(0, dot);
    final fracPart = dot == -1 ? '' : text.substring(dot + 1);
    final whole = wholePart.isEmpty ? 0 : (int.tryParse(wholePart) ?? 0);
    final kept = fracPart.length <= spec.exponent
        ? fracPart.padRight(spec.exponent, '0')
        : fracPart.substring(0, spec.exponent);
    var minor = whole * spec.scale + (kept.isEmpty ? 0 : int.tryParse(kept) ?? 0);
    if (fracPart.length > spec.exponent) {
      final nextDigit = int.tryParse(fracPart[spec.exponent]) ?? 0;
      if (nextDigit >= 5) minor += 1;
    }
    return negative ? -minor : minor;
  }
}

/// Sum a list of amounts without ever touching a float.
extension MoneyIterable on Iterable<Money> {
  Money sum({String currency = kDefaultCurrency}) {
    var total = Money.zero(currency);
    for (final amount in this) {
      total = total + amount;
    }
    return total;
  }
}
