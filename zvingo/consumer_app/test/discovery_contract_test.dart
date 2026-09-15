// Temporary compile + smoke check for the C1 discovery surfaces.
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/discovery_provider.dart';
import 'package:consumer_app/features/home/home_screen.dart';
import 'package:consumer_app/features/home/widgets/category_row.dart';
import 'package:consumer_app/features/home/widgets/promo_banner.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/offers/offers_provider.dart';
import 'package:consumer_app/features/offers/offers_screen.dart';
import 'package:consumer_app/features/pickup/pickup_screen.dart';
import 'package:consumer_app/features/restaurant/restaurant_list.dart';
import 'package:consumer_app/features/restaurant/restaurant_map_screen.dart';
import 'package:consumer_app/features/restaurant/store_search_screen.dart';
import 'package:consumer_app/features/search/search_screen.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('discovery surfaces compile', () {
    expect(const HomeScreen(), isNotNull);
    expect(const CategoryRow(), isNotNull);
    expect(const PromoBanner(), isNotNull);
    expect(const OffersScreen(), isNotNull);
    expect(const PickupScreen(), isNotNull);
    expect(const RestaurantListView(), isNotNull);
    expect(const RestaurantMapScreen(), isNotNull);
    expect(const SearchScreen(), isNotNull);
    expect(
      const StoreSearchScreen(restaurantId: 'r1', restaurantName: 'Kudya'),
      isNotNull,
    );
    expect(RestaurantCardMode.pickup, isNotNull);
    expect(activePromotionsProvider, isNotNull);
  });

  test('availability parses the real backend contract', () {
    final open = StoreAvailability.fromRestaurantJson(const {
      'availability': {
        'is_open': true,
        'status': 'open',
        'reason': 'Open now',
        'closes_at': null,
        'accepts_scheduled': false,
      },
    });
    expect(open.isOpen, isTrue);
    expect(open.isKnownClosed, isFalse);

    final closed = StoreAvailability.fromRestaurantJson(const {
      'availability': {
        'is_open': false,
        'status': 'closed',
        'reason': 'Opens at 08:00',
        'opens_at': '2026-09-16T08:00:00',
        'accepts_scheduled': true,
      },
      'operating_hours': 'Mon-Fri 08:00-22:00',
    });
    expect(closed.isKnownClosed, isTrue);
    expect(closed.acceptsScheduled, isTrue);
    expect(closed.closedLabel, contains('08:00'));

    // No availability block at all: never rendered as closed.
    final unknown = StoreAvailability.fromRestaurantJson(const {'name': 'X'});
    expect(unknown.isOpen, isTrue);
    expect(unknown.isKnownClosed, isFalse);

    // Legacy boolean shape.
    final legacy = StoreAvailability.fromRestaurantJson(
        const {'is_currently_open': false});
    expect(legacy.isKnownClosed, isTrue);
  });

  test('discovery restaurant guards an empty promotions list', () {
    final store = DiscoveryRestaurant.fromJson(const {
      '_id': 'r1',
      'name': 'Kudya Kitchen',
      'promotions': <String>[],
      'discovery': {
        'distance_km': 0.4,
        'matched_menu_items': ['Sadza']
      },
    });
    expect(store.headlinePromotion, isNull);
    expect(store.hasPromotion, isFalse);
    expect(store.distanceLabel, '400 m');
    expect(store.matchedDishes, ['Sadza']);
  });

  test('filter state can clear a nullable facet', () {
    var state = const FilterState();
    state =
        state.copyWith(minRating: 4.5, priceBand: 2, maxDeliveryMinutes: 30);
    expect(state.activeCount, 3);
    state = state.copyWith(minRating: null);
    expect(state.minRating, isNull);
    expect(state.activeCount, 2);
  });

  test('query parameters match the catalog router contract', () {
    const query = DiscoveryQuery(
      lat: -17.82,
      lng: 31.05,
      categories: {'Pizza'},
      openNow: true,
      offersOnly: true,
      minRating: 4,
      sortBy: SortOption.deliveryTime,
    );
    final browse = query.toQueryParameters();
    expect(browse['lat'], -17.82);
    expect(browse['lon'], 31.05);
    expect(browse['category'], 'Pizza');
    expect(browse['open_now'], isTrue);
    expect(browse['has_promotions'], isTrue);
    expect(browse['sort_by'], 'delivery_time');

    final search = query.toSearchParameters('pizza');
    expect(search['q'], 'pizza');
    expect(search['lng'], 31.05);
    expect(search.containsKey('lon'), isFalse);
    expect(search.containsKey('sort_by'), isFalse);
    expect(search.containsKey('has_promotions'), isFalse);
  });

  for (final scale in <double>[1.0, 1.5, 2.0]) {
    testWidgets(
      'rail card fits its computed height at 320px and ${scale}x text',
      (tester) async {
        final store = DiscoveryRestaurant.fromJson(const {
          '_id': 'r1',
          'name': 'Amai Rudo Home Kitchen & Grill',
          'categories': ['Zimbabwean', 'Grills'],
          'rating': 4.7,
          'delivery_time_min': 25,
          'delivery_time_max': 40,
          'delivery_fee_usd': 1.5,
          'promotions': ['20% off your first order'],
          'availability': {
            'is_open': false,
            'status': 'closed',
            'reason': 'Opens at 08:00',
            'accepts_scheduled': true,
          },
        });

        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Builder(
                builder: (context) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    height: restaurantRailHeight(context),
                    child: RestaurantRailCard(store: store, onTap: () {}),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'rail card overflowed at text scale $scale',
        );
      },
    );
  }

  group('full-width restaurant card', () {
    late Directory hiveDir;

    setUpAll(() {
      hiveDir = Directory.systemTemp.createTempSync('zv_discovery_test');
      Hive.init(hiveDir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
    });

    for (final scale in <double>[1.0, 1.5, 2.0]) {
      testWidgets('lays out at 320px and ${scale}x text', (tester) async {
        final store = DiscoveryRestaurant.fromJson(const {
          '_id': 'r2',
          'name': 'Gava\u2019s Flame Grill & Takeaway',
          'categories': ['Zimbabwean', 'Grills', 'Chicken'],
          'rating': 4.6,
          'review_count': 4213,
          'delivery_time_min': 25,
          'delivery_time_max': 40,
          'delivery_fee_usd': 1.5,
          'is_zvingo_plus': true,
          'promotions': ['Buy one get one free on all flame-grilled chicken'],
          'discovery': {'distance_km': 2.4},
          'availability': {
            'is_open': false,
            'status': 'closed',
            'reason': 'Opens at 08:00',
            'accepts_scheduled': true,
          },
        });

        tester.view.physicalSize = const Size(320, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // MaterialApp supplies the Overlay that ZvIconButton's Tooltip needs.
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topCenter,
                      child: RestaurantCard.discovery(store, onTap: () {}),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'restaurant card overflowed at text scale $scale',
        );
      });
    }
  });
}
