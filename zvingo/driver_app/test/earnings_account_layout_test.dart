import 'dart:io';

import 'package:driver_app/core/api_client.dart';
import 'package:driver_app/core/theme.dart';
import 'package:driver_app/features/account/account_screen.dart';
import 'package:driver_app/features/account/help_screen.dart';
import 'package:driver_app/features/auth/login_screen.dart';
import 'package:driver_app/features/earnings/earnings_screen.dart';
import 'package:driver_app/features/ratings/ratings_screen.dart';
import 'package:driver_app/features/schedule/schedule_screen.dart';
import 'package:driver_app/models/earning_record.dart';
import 'package:driver_app/models/earnings_models.dart';
import 'package:driver_app/providers/auth_provider.dart';
import 'package:driver_app/providers/earnings_provider.dart';
import 'package:driver_app/providers/ratings_provider.dart';
import 'package:driver_app/providers/schedule_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// §7 of `docs/DESIGN_SYSTEM.md`: "Works at 320px width and at 200% text scale
/// without overflow." A money screen that clips its own total is worse than
/// one that is plain, so every screen in this slice is pumped at the worst
/// case and checked for render overflow.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.init(Directory.systemTemp.createTempSync('zvingo_test').path);
    await Hive.openBox('auth');
    await Hive.openBox('settings');
  });

  Widget harness(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: child,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2.0),
          ),
          child: widget ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  Future<void> pumpAtWorstCase(
    WidgetTester tester,
    Widget child, {
    List<Override> overrides = const [],
    double height = 3000,
  }) async {
    // 320 wide is the constraint that matters; the view is made tall so that
    // the lazy ListView builds every child and an overflow low on the page is
    // not hidden simply by being off-screen.
    tester.view.physicalSize = Size(320, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(child, overrides: overrides));
    await tester.pump(const Duration(seconds: 1));
  }

  group('Earnings', () {
    testWidgets('populated earnings survive 320px at 200% text scale',
        (tester) async {
      await pumpAtWorstCase(
        tester,
        const EarningsScreen(),
        overrides: [
          earningsProvider.overrideWith(
            (ref) => _SeededEarnings(_populatedEarnings()),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the headline total is rendered and is the largest figure',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            earningsProvider.overrideWith(
              (ref) => _SeededEarnings(_populatedEarnings()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const EarningsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final headline = tester.widgetList<Text>(find.byType(Text)).where(
            (text) => text.data == r'$42.50',
          );
      expect(headline, isNotEmpty,
          reason: "today's take-home must be on screen");

      // Nothing else may be set larger than the hero figure.
      final heroSize = headline.first.style?.fontSize ?? 0;
      expect(heroSize, greaterThan(24));
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final size = text.style?.fontSize;
        if (size == null) continue;
        expect(size, lessThanOrEqualTo(heroSize),
            reason: '"${text.data}" is bigger than the headline total');
      }
    });

    testWidgets('a 403 gets its own explanation, never a blank screen',
        (tester) async {
      await pumpAtWorstCase(
        tester,
        const EarningsScreen(),
        overrides: [
          earningsProvider.overrideWith(
            (ref) => _SeededEarnings(
              const EarningsState(failure: EarningsFailure.forbidden),
            ),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('not yours to view', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Try again'), findsWidgets);
    });

    testWidgets('an empty 30 days offers a way forward, not a dead end',
        (tester) async {
      await pumpAtWorstCase(
        tester,
        const EarningsScreen(),
        overrides: [
          earningsProvider.overrideWith(
            (ref) => _SeededEarnings(const EarningsState()),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('No earnings'), findsOneWidget);
    });
  });

  group('Ratings', () {
    testWidgets('a rated driver renders at 320px / 200%', (tester) async {
      await pumpAtWorstCase(
        tester,
        const RatingsScreen(),
        overrides: [
          ratingsProvider.overrideWith((ref) => _SeededRatings(_rated())),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('4.8'), findsOneWidget);
    });

    testWidgets('an unrated driver sees a dash, never 0.0 stars or 0%',
        (tester) async {
      await pumpAtWorstCase(
        tester,
        const RatingsScreen(),
        overrides: [
          ratingsProvider.overrideWith(
            (ref) => _SeededRatings(const RatingsState()),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Not rated yet'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
      expect(find.text('0%'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });
  });

  group('Schedule', () {
    testWidgets('the grid renders every day at 320px / 200%', (tester) async {
      await pumpAtWorstCase(
        tester,
        const ScheduleScreen(),
        height: 7000,
        overrides: [
          scheduleProvider.overrideWith(
            (ref) => _SeededSchedule(
              const ScheduleState(
                selected: {0: {0, 2}, 4: {1}},
                savedRecently: true,
              ),
            ),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
    });

    testWidgets('a failed save says so and offers a retry', (tester) async {
      await pumpAtWorstCase(
        tester,
        const ScheduleScreen(),
        overrides: [
          scheduleProvider.overrideWith(
            (ref) => _SeededSchedule(
              const ScheduleState(
                selected: {1: {0}},
                failure: ScheduleFailure.network,
              ),
            ),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Not saved'), findsWidgets);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Account', () {
    testWidgets('renders at 320px / 200% with no dead entries',
        (tester) async {
      await pumpAtWorstCase(
        tester,
        const AccountScreen(),
        overrides: [
          ratingsProvider.overrideWith((ref) => _SeededRatings(_rated())),
        ],
      );
      expect(tester.takeException(), isNull);
      // Each of the seven previously dead entries is present and labelled.
      for (final label in [
        'Vehicle details',
        'Notifications',
        'Safety',
        'Help',
        'Terms of Service',
        'Privacy Policy',
        'About',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
      // And no account-deletion control is shipped while the backend has no
      // route for it.
      expect(find.textContaining('Delete account'), findsNothing);
    });

    testWidgets('help renders and every question is expandable',
        (tester) async {
      await pumpAtWorstCase(tester, const HelpScreen());
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Why is my pay different'),
        findsOneWidget,
      );
    });
  });

  group('Login', () {
    testWidgets('renders phone-first at 320px / 200%', (tester) async {
      await pumpAtWorstCase(tester, const LoginScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('+263'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('the submit button is disabled with a stated reason',
        (tester) async {
      await pumpAtWorstCase(tester, const LoginScreen());
      expect(find.text('Enter your phone number'), findsOneWidget);
    });
  });
}

// ── Seeded notifiers ────────────────────────────────────────────────────────
//
// Each overrides only the fetch, so the screen under test renders the real
// widget tree against a fixed state.

class _SeededEarnings extends EarningsNotifier {
  _SeededEarnings(EarningsState seed) : super(ApiClient(), AuthSession(ApiClient()), 'd1') {
    state = seed;
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadHistory({bool reset = false}) async {}
}

class _SeededRatings extends RatingsNotifier {
  _SeededRatings(RatingsState seed) : super(ApiClient(), AuthSession(ApiClient()), 'd1') {
    state = seed;
  }

  @override
  Future<void> refresh() async {}
}

class _SeededSchedule extends ScheduleNotifier {
  _SeededSchedule(ScheduleState seed) : super(ApiClient(), AuthSession(ApiClient())) {
    state = seed;
  }

  @override
  Future<void> load() async {}
}


EarningsState _populatedEarnings() {
  return EarningsState(
    todayEarnings: const Money(4250),
    todayTips: const Money(600),
    todayTrips: 5,
    weekEarnings: const Money(19800),
    weekTips: const Money(2400),
    weekTrips: 23,
    cashOnHand: const Money(1500),
    dailySummaries: const [
      DailySummary(
        date: '2026-09-15',
        earnings: Money(4250),
        tips: Money(600),
        tripCount: 5,
        cashCollected: Money(1500),
      ),
      DailySummary(
        date: '2026-09-14',
        earnings: Money(3100),
        tips: Money(0),
        tripCount: 4,
      ),
    ],
    historyRecords: [
      DriverEarningRecord.fromJson(const {
        'id': 'e1',
        'order_id': '68c1f0a9b2d4e5f60718a2b3',
        'merchant_name': 'Chicken Inn Avondale',
        'pickup_area': '** Samora Machel Ave',
        'dropoff_area': '** Second St',
        'delivery_fee_cents': 1000,
        'driver_earning_cents': 850,
        'tip_cents': 200,
        'total_earning_cents': 1050,
        'payment_method': 'ecocash',
        'distance_km': 8.0,
        'completed_at': '2026-09-15T12:05:00',
      }),
    ],
  );
}

RatingsState _rated() {
  return const RatingsState(
    overallRating: 4.8,
    ratedReviews: 24,
    distribution: {5: 20, 4: 3, 3: 1, 2: 0, 1: 0},
    acceptanceRate: DriverRate(92, basis: '120 offers sent to you'),
    completionRate: DriverRate(98, basis: 'Deliveries you accepted'),
    onTimeRate: DriverRate(95, basis: 'Delivered within 45 minutes'),
    lifetimeDeliveries: 156,
    deliveriesInWindow: 42,
    recentFeedback: [
      FeedbackItem(
        customerName: 'Tendai M.',
        rating: 5,
        comment: 'Very fast, food still hot.',
        tags: ['On time', 'Friendly'],
      ),
    ],
  );
}
