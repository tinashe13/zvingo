import 'package:driver_app/models/earning_record.dart';
import 'package:driver_app/models/earnings_models.dart';
import 'package:driver_app/providers/auth_provider.dart';
import 'package:driver_app/providers/earnings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The driver app's single most load-bearing claim is that the money adds up.
/// These tests pin the arithmetic against the real backend contract in
/// `backend/app/finance/` so it cannot silently drift again.
void main() {
  group('Money', () {
    test('renders an explicit currency symbol and two decimals', () {
      expect(const Money(2365).formatted, r'$23.65');
      expect(const Money(0).formatted, r'$0.00');
      expect(const Money(5).formatted, r'$0.05');
      expect(const Money(100).formatted, r'$1.00');
    });

    test('groups thousands so a large payout is readable', () {
      expect(const Money(124000).formatted, r'$1,240.00');
      expect(const Money(123456789).formatted, r'$1,234,567.89');
    });

    test('carries the currency, never assumes USD formatting', () {
      expect(const Money(2500, Money.zig).formatted, 'ZiG 25.00');
      expect(const Money(2500, Money.zar).formatted, 'R25.00');
    });

    test('signed amounts use a real minus sign for deductions', () {
      expect(const Money(250).signed, r'+$2.50');
      expect(const Money(-150).signed, '−\$1.50');
      expect(const Money(0).signed, r'$0.00');
    });

    test('adds in integer cents — no floating point drift', () {
      // 0.1 + 0.2 != 0.3 in binary floating point. In cents it is exact, and
      // this is the whole reason money never becomes a double before display.
      var total = const Money.zero();
      for (var i = 0; i < 10; i++) {
        total = total + const Money(10);
      }
      expect(total.cents, 100);
      expect(total.formatted, r'$1.00');
    });

    test('parses only integers off the wire, and never throws on junk', () {
      expect(Money.parse(1234).cents, 1234);
      expect(Money.parse(null).cents, 0);
      expect(Money.parse('bad').cents, 0);
      expect(Money.parse(12.6).cents, 13);
    });
  });

  group('DriverEarningRecord', () {
    /// A record shaped exactly like `/finance/earnings/driver/{id}/history`
    /// returns: 8 km trip → 2 five-km blocks → $10.00 gross → $8.50 driver
    /// share (85%) → plus a $2.00 tip → $10.50 paid.
    Map<String, dynamic> json({
      int deliveryFee = 1000,
      int driverEarning = 850,
      int tip = 200,
      int? total,
      double distanceKm = 8.0,
      String paymentMethod = 'ecocash',
    }) {
      return {
        'id': 'e1',
        'order_id': '68c1f0a9b2d4e5f60718a2b3',
        'merchant_name': 'Chicken Inn Avondale',
        'pickup_area': '** Samora Machel Ave',
        'dropoff_area': '** Second St',
        'delivery_fee_cents': deliveryFee,
        'driver_earning_cents': driverEarning,
        'tip_cents': tip,
        'total_earning_cents': total ?? (driverEarning + tip),
        'payment_method': paymentMethod,
        'distance_km': distanceKm,
        'completed_at': '2026-09-15T12:05:00',
      };
    }

    test('parses the history payload field for field', () {
      final record = DriverEarningRecord.fromJson(json());
      expect(record.deliveryFee.cents, 1000);
      expect(record.driverEarning.cents, 850);
      expect(record.tip.cents, 200);
      expect(record.total.cents, 1050);
      expect(record.merchantName, 'Chicken Inn Avondale');
      expect(record.paymentLabel, 'EcoCash');
      expect(record.isCash, isFalse);
      expect(record.shortOrderRef, '#18A2B3');
    });

    test('platform fee is the exact remainder of the delivery fee', () {
      // `commission_minor()` derives the platform's cut as the remainder, not
      // by rounding 15% separately. Deriving it the same way here is what
      // guarantees the split reconciles for every amount.
      final record = DriverEarningRecord.fromJson(json());
      expect(record.platformFee.cents, 150);
      expect(
        record.platformFee.cents + record.driverEarning.cents,
        record.deliveryFee.cents,
      );
    });

    test('the rendered breakdown sums to the payout, to the cent', () {
      final record = DriverEarningRecord.fromJson(json());
      final breakdown = record.breakdown;
      expect(breakdown.reconciles, isTrue);
      expect(breakdown.lineSum.cents, record.total.cents);
      expect(breakdown.discrepancy.cents, 0);
    });

    test('an 8 km trip splits into a base fare plus a distance block', () {
      final breakdown = DriverEarningRecord.fromJson(json()).breakdown;
      final labels = breakdown.lines.map((l) => l.label).toList();
      expect(labels, containsAll(<String>['Base fare', 'Distance']));
      final base =
          breakdown.lines.firstWhere((l) => l.label == 'Base fare').amount;
      final distance =
          breakdown.lines.firstWhere((l) => l.label == 'Distance').amount;
      expect(base.cents, 500);
      expect(distance.cents, 500);
      expect(base.cents + distance.cents, 1000);
    });

    test('a single-block trip shows one undivided delivery-fee line', () {
      final breakdown = DriverEarningRecord.fromJson(
        json(deliveryFee: 500, driverEarning: 425, distanceKm: 3.2),
      ).breakdown;
      final labels = breakdown.lines.map((l) => l.label).toList();
      expect(labels, contains('Delivery fee'));
      expect(labels, isNot(contains('Base fare')));
      expect(breakdown.reconciles, isTrue);
    });

    test('a fee that does not divide into blocks is never split by guesswork',
        () {
      // A custom fee carried on the order. Better to show one honest line than
      // a base/distance split we made up.
      final split = FarePricing.split(const Money(733), 8.0);
      expect(split, isNull);

      final breakdown = DriverEarningRecord.fromJson(
        json(deliveryFee: 733, driverEarning: 623, tip: 0),
      ).breakdown;
      expect(breakdown.lines.map((l) => l.label), contains('Delivery fee'));
      expect(breakdown.reconciles, isTrue);
    });

    test('a zero-tip delivery renders no tip line but still reconciles', () {
      final breakdown =
          DriverEarningRecord.fromJson(json(tip: 0)).breakdown;
      expect(breakdown.lines.map((l) => l.label), isNot(contains('Customer tip')));
      expect(breakdown.reconciles, isTrue);
      expect(breakdown.lineSum.cents, 850);
    });

    test('a server record whose own arithmetic is wrong is flagged, not hidden',
        () {
      // total != driver_earning + tip. The UI must surface this rather than
      // draw numbers that quietly disagree.
      final record = DriverEarningRecord.fromJson(json(total: 1100));
      expect(record.reconciles, isFalse);
      expect(record.breakdown.reconciles, isFalse);
      expect(record.breakdown.discrepancy.cents, 50);
    });

    test('reconciles across the whole fee and tip range', () {
      for (var blocks = 1; blocks <= 12; blocks++) {
        final fee = blocks * 500;
        // Banker's rounding of fee * 0.85, matching `apply_ratio`.
        final driver = _bankersRound(fee * 85, 100);
        for (final tip in [0, 1, 7, 50, 199, 1000]) {
          final record = DriverEarningRecord.fromJson(
            json(
              deliveryFee: fee,
              driverEarning: driver,
              tip: tip,
              distanceKm: blocks * 5.0 - 0.5,
            ),
          );
          expect(
            record.reconciles,
            isTrue,
            reason: 'fee=$fee driver=$driver tip=$tip',
          );
          expect(
            record.breakdown.lineSum.cents,
            record.total.cents,
            reason: 'lines must sum to the payout for fee=$fee tip=$tip',
          );
        }
      }
    });
  });

  group('DailySummary — the tip double-count regression', () {
    // `/finance/earnings/driver/{id}/daily` builds `earnings_cents` by summing
    // `DriverEarning.total_earning_cents`, which ALREADY includes the tip it
    // reports separately in `tip_cents`. The previous client added the two,
    // overstating every daily total by the value of its tips.
    final summary = DailySummary.fromJson(const {
      'date': '2026-09-15',
      'earnings_cents': 4250,
      'tip_cents': 600,
      'trip_count': 5,
      'cash_collected_cents': 1500,
    });

    test('the day total is the reported earnings, not earnings plus tips', () {
      expect(summary.total.cents, 4250);
      expect(summary.total.cents, isNot(4250 + 600));
    });

    test('tips are a component of the total, so fares are the remainder', () {
      expect(summary.tips.cents, 600);
      expect(summary.fareEarnings.cents, 3650);
      expect(summary.fareEarnings.cents + summary.tips.cents,
          summary.total.cents);
    });

    test('per-trip average is null rather than a 0/0 division', () {
      expect(summary.perTrip!.cents, 850);
      final empty = DailySummary.fromJson(const {
        'date': '2026-09-14',
        'earnings_cents': 0,
        'trip_count': 0,
      });
      expect(empty.perTrip, isNull);
    });
  });

  group('EarningsState', () {
    const state = EarningsState(
      todayEarnings: Money(4250),
      todayTips: Money(600),
      todayTrips: 5,
      weekEarnings: Money(19800),
      weekTips: Money(2400),
      weekTrips: 23,
    );

    test('the headline figure never adds tips on top of earnings', () {
      expect(state.periodEarnings.cents, 4250);
      expect(
        state.copyWith(period: EarningsPeriod.week).periodEarnings.cents,
        19800,
      );
    });

    test('the fares/tips split always reconstitutes the headline', () {
      for (final period in EarningsPeriod.values) {
        final scoped = state.copyWith(period: period);
        expect(
          scoped.periodFares.cents + scoped.periodTips.cents,
          scoped.periodEarnings.cents,
          reason: 'split must add back up for $period',
        );
      }
    });

    test('a ledger disagreement is detected and quantified', () {
      const mismatch = EarningsState(
        weekEarnings: Money(19800),
        ledgerWeekEarnings: Money(19750),
        ledgerMatches: false,
      );
      expect(mismatch.hasLedgerDiscrepancy, isTrue);
      expect(mismatch.ledgerDiscrepancy!.cents, -50);

      const agreed = EarningsState(
        weekEarnings: Money(19800),
        ledgerWeekEarnings: Money(19800),
        ledgerMatches: true,
      );
      expect(agreed.hasLedgerDiscrepancy, isFalse);
    });

    test('history groups by day and each header sums its own rows', () {
      final records = [
        _record('a', '2026-09-15T09:00:00', 850),
        _record('b', '2026-09-15T18:30:00', 1200),
        _record('c', '2026-09-14T20:00:00', 700),
      ];
      final grouped = EarningsState(historyRecords: records).groupedHistory;

      expect(grouped.length, 2);
      expect(grouped.first.day, DateTime(2026, 9, 15));
      expect(grouped.first.tripCount, 2);
      expect(grouped.first.total.cents, 2050);
      expect(grouped.last.total.cents, 700);

      // Newest day first.
      expect(grouped.first.day.isAfter(grouped.last.day), isTrue);
    });
  });

  group('DateLabels', () {
    final now = DateTime(2026, 9, 15, 14, 30);

    test('names today and yesterday rather than printing a date', () {
      expect(DateLabels.relative(DateTime(2026, 9, 15), now), 'Today');
      expect(DateLabels.relative(DateTime(2026, 9, 14), now), 'Yesterday');
    });

    test('uses the weekday inside the last week, then a date', () {
      expect(DateLabels.relative(DateTime(2026, 9, 11), now), 'Friday');
      expect(DateLabels.relative(DateTime(2026, 9, 1), now), '1 Sep');
      expect(DateLabels.relative(DateTime(2025, 12, 25), now), '25 Dec 2025');
    });

    test('renders 24-hour times zero-padded', () {
      expect(DateLabels.time(DateTime(2026, 9, 15, 9, 5)), '09:05');
      expect(DateLabels.time(DateTime(2026, 9, 15, 18, 0)), '18:00');
    });
  });

  group('Phone normalisation (E.164)', () {
    test('turns the way a driver writes their number into E.164', () {
      expect(AuthNotifier.normalisePhone('0771234567'), '+263771234567');
      expect(AuthNotifier.normalisePhone('077 123 4567'), '+263771234567');
      expect(AuthNotifier.normalisePhone('077-123-4567'), '+263771234567');
      expect(AuthNotifier.normalisePhone('263771234567'), '+263771234567');
      expect(AuthNotifier.normalisePhone('+263771234567'), '+263771234567');
      expect(AuthNotifier.normalisePhone('00263771234567'), '+263771234567');
      expect(AuthNotifier.normalisePhone('771234567'), '+263771234567');
    });

    test('accepts a valid Zimbabwean mobile number', () {
      expect(AuthNotifier.validatePhone('0771234567'), isNull);
      expect(AuthNotifier.validatePhone('+263 78 123 4567'), isNull);
    });

    test('explains what is wrong rather than just refusing', () {
      expect(AuthNotifier.validatePhone(''), 'Enter your phone number');
      expect(AuthNotifier.validatePhone('07712345'), contains('9 digits'));
      expect(AuthNotifier.validatePhone('0241234567'), contains('start with 7'));
    });

    test('does not mangle a non-Zimbabwean number that is already E.164', () {
      expect(AuthNotifier.normalisePhone('+27821234567'), '+27821234567');
      expect(AuthNotifier.validatePhone('+27821234567'), isNull);
    });
  });

  group('Password validation', () {
    test('sign in only requires something to be typed', () {
      expect(AuthNotifier.validatePassword('short'), isNull);
      expect(AuthNotifier.validatePassword(''), 'Enter your password');
    });

    test('registration enforces the backend minimum of 8', () {
      expect(
        AuthNotifier.validatePassword('short', isRegister: true),
        contains('8 characters'),
      );
      expect(
        AuthNotifier.validatePassword('longenough', isRegister: true),
        isNull,
      );
    });
  });
}

DriverEarningRecord _record(String id, String completedAt, int totalCents) {
  return DriverEarningRecord.fromJson({
    'id': id,
    'order_id': 'order$id',
    'merchant_name': 'Merchant $id',
    'delivery_fee_cents': totalCents,
    'driver_earning_cents': totalCents,
    'tip_cents': 0,
    'total_earning_cents': totalCents,
    'payment_method': 'cash',
    'distance_km': 4.0,
    'completed_at': completedAt,
  });
}

/// Mirrors Python's `ROUND_HALF_EVEN`, which `app.finance.money.apply_ratio`
/// uses for the driver's share of a shared pot.
int _bankersRound(int numerator, int denominator) {
  final quotient = numerator ~/ denominator;
  final remainder = numerator % denominator;
  final twice = remainder * 2;
  if (twice > denominator) return quotient + 1;
  if (twice < denominator) return quotient;
  return quotient.isEven ? quotient : quotient + 1;
}
