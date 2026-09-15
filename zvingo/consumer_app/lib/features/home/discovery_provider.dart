import 'dart:math' as math;

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Discovery data layer for home / search / offers / pickup.
///
/// `GET /catalog/restaurants` and `GET /catalog/search` return more than the
/// shared [Restaurant] model parses today: every payload carries an
/// `availability` block (open/closed and *why*) and search/rank responses carry
/// a `discovery` block (`score`, `relevance`, `distance_km`,
/// `matched_menu_items`). [DiscoveryRestaurant] pairs the parsed [Restaurant]
/// with those two blocks so discovery surfaces can show a real closed state and
/// a real distance.
///
/// Every field is read defensively — an older backend that sends none of this
/// degrades to "assume open, distance computed client-side", never to a crash.

// ── Availability ──────────────────────────────────────────────────────────

/// Mirror of `app/catalog/hours.py :: compute_availability`.
enum StoreStatus {
  open,
  closed,
  closedByMerchant,
  paused,
  unlisted,

  /// Backend did not tell us. Treated as open, never rendered as "closed".
  unknown;

  static StoreStatus parse(Object? raw) {
    switch (raw?.toString()) {
      case 'open':
        return StoreStatus.open;
      case 'closed':
        return StoreStatus.closed;
      case 'closed_by_merchant':
        return StoreStatus.closedByMerchant;
      case 'paused':
        return StoreStatus.paused;
      case 'unlisted':
        return StoreStatus.unlisted;
      default:
        return StoreStatus.unknown;
    }
  }
}

/// Live open/closed state for one store.
class StoreAvailability {
  const StoreAvailability({
    required this.isOpen,
    required this.status,
    this.reason,
    this.opensAt,
    this.closesAt,
    this.acceptsScheduled = false,
    this.scheduleSummary,
  });

  /// What we assume when the backend says nothing at all: a store we cannot
  /// prove is closed is shown as orderable rather than wrongly greyed out.
  static const StoreAvailability unknown = StoreAvailability(
    isOpen: true,
    status: StoreStatus.unknown,
  );

  final bool isOpen;
  final StoreStatus status;

  /// Short human sentence from the backend, e.g. "Opens at 08:00".
  final String? reason;

  /// Local wall-clock time the store next opens.
  final DateTime? opensAt;

  /// Local wall-clock time the current opening window ends.
  final DateTime? closesAt;

  /// A pre-order may still be placed while closed.
  final bool acceptsScheduled;

  /// Human weekly summary (`operating_hours`), e.g. "Mon-Fri 08:00-22:00".
  final String? scheduleSummary;

  /// True only when the backend actually told us the store is shut.
  bool get isKnownClosed => !isOpen && status != StoreStatus.unknown;

  /// Badge copy for a closed card. Always says *something* actionable.
  String get closedLabel {
    if (status == StoreStatus.unlisted) return 'Unavailable';
    if (status == StoreStatus.paused) return reason ?? 'Paused';
    final opening = opensAt;
    if (opening != null) {
      final time = _hhmm(opening);
      final now = DateTime.now();
      final sameDay = opening.year == now.year &&
          opening.month == now.month &&
          opening.day == now.day;
      return sameDay ? 'Opens $time' : 'Opens ${_weekday(opening)} $time';
    }
    return reason?.isNotEmpty == true ? reason! : 'Closed';
  }

  /// Copy for a store that is open but closing soon (within 60 minutes).
  String? get closingSoonLabel {
    final closing = closesAt;
    if (!isOpen || closing == null) return null;
    final minutes = closing.difference(DateTime.now()).inMinutes;
    if (minutes <= 0 || minutes > 60) return null;
    return 'Closes ${_hhmm(closing)}';
  }

  static String _hhmm(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static const List<String> _weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String _weekday(DateTime value) =>
      _weekdays[(value.weekday - 1).clamp(0, 6)];

  /// Reads whatever availability shape the payload happens to carry.
  ///
  /// Preference order:
  ///   1. `availability` object (current contract)
  ///   2. `is_currently_open` / `is_open` boolean
  ///   3. `operating_hours` string only — not enough to prove closed
  factory StoreAvailability.fromRestaurantJson(Map<String, dynamic> json) {
    final summary = json['operating_hours']?.toString();

    final raw = json['availability'];
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final status = StoreStatus.parse(map['status']);
      final open = map['is_open'];
      return StoreAvailability(
        isOpen: open is bool ? open : status == StoreStatus.open,
        status: status,
        reason: map['reason']?.toString(),
        opensAt: _parseDate(map['opens_at']),
        closesAt: _parseDate(map['closes_at']),
        acceptsScheduled: map['accepts_scheduled'] == true,
        scheduleSummary: summary,
      );
    }

    final flag = json['is_currently_open'] ?? json['is_open'] ?? json['open'];
    if (flag is bool) {
      return StoreAvailability(
        isOpen: flag,
        status: flag ? StoreStatus.open : StoreStatus.closed,
        opensAt: _parseDate(json['opens_at']),
        closesAt: _parseDate(json['closes_at']),
        scheduleSummary: summary,
      );
    }

    // `is_active: false` is a listing switch, not opening hours, but a
    // de-listed store must never look orderable.
    if (json['is_active'] == false) {
      return StoreAvailability(
        isOpen: false,
        status: StoreStatus.unlisted,
        reason: 'This restaurant is not currently on Zvingo',
        scheduleSummary: summary,
      );
    }

    return summary == null
        ? StoreAvailability.unknown
        : StoreAvailability(
            isOpen: true,
            status: StoreStatus.unknown,
            scheduleSummary: summary,
          );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}

// ── Restaurant + discovery metadata ───────────────────────────────────────

/// A [Restaurant] with the discovery context a card needs to be decidable.
class DiscoveryRestaurant {
  const DiscoveryRestaurant({
    required this.restaurant,
    required this.availability,
    this.distanceKm,
    this.relevance,
    this.matchedDishes = const <String>[],
  });

  final Restaurant restaurant;
  final StoreAvailability availability;

  /// Straight-line distance from the delivery location.
  final double? distanceKm;

  /// Search relevance (`0..1`), null outside search.
  final double? relevance;

  /// Menu items that matched the query, best first (max 5 from the backend).
  final List<String> matchedDishes;

  String get id => restaurant.id;
  String get name => restaurant.name;
  bool get isOpen => availability.isOpen;
  bool get isClosed => availability.isKnownClosed;
  bool get hasPromotion => restaurant.promotions.isNotEmpty;
  bool get isFreeDelivery => restaurant.deliveryFee == 0;

  /// First promotion line, or null. Guarded — `promotions` is routinely empty.
  String? get headlinePromotion =>
      restaurant.promotions.isEmpty ? null : restaurant.promotions.first;

  /// "1.2 km" / "800 m", or null when we have no location fix.
  String? get distanceLabel {
    final km = distanceKm;
    if (km == null || km.isNaN || km.isInfinite || km < 0) return null;
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  DiscoveryRestaurant withDistance(double? km) => DiscoveryRestaurant(
        restaurant: restaurant,
        availability: availability,
        distanceKm: km ?? distanceKm,
        relevance: relevance,
        matchedDishes: matchedDishes,
      );

  factory DiscoveryRestaurant.fromJson(Map<String, dynamic> json) {
    final discovery = json['discovery'];
    double? distanceKm;
    double? relevance;
    var matched = const <String>[];
    if (discovery is Map) {
      distanceKm = (discovery['distance_km'] as num?)?.toDouble();
      relevance = (discovery['relevance'] as num?)?.toDouble();
      final items = discovery['matched_menu_items'];
      if (items is List) {
        matched = items.map((e) => e.toString()).toList(growable: false);
      }
    }
    distanceKm ??= (json['distance_km'] as num?)?.toDouble();

    return DiscoveryRestaurant(
      restaurant: Restaurant.fromJson(json),
      availability: StoreAvailability.fromRestaurantJson(json),
      distanceKm: distanceKm,
      relevance: relevance,
      matchedDishes: matched,
    );
  }
}

/// One dish result, lifted out of a restaurant's `matched_menu_items`.
class DishHit {
  const DishHit({required this.dish, required this.store});

  final String dish;
  final DiscoveryRestaurant store;
}

/// Search results split the way people actually think about them.
class SearchResults {
  const SearchResults({required this.stores, required this.dishes});

  static const SearchResults empty =
      SearchResults(stores: <DiscoveryRestaurant>[], dishes: <DishHit>[]);

  final List<DiscoveryRestaurant> stores;
  final List<DishHit> dishes;

  bool get isEmpty => stores.isEmpty && dishes.isEmpty;
  int get total => stores.length + dishes.length;
}

// ── Query keys ────────────────────────────────────────────────────────────

/// Immutable cache key for a discovery request. Value equality matters: it is
/// what stops a rebuild from refetching and what makes a filter change fetch
/// exactly once.
class DiscoveryQuery {
  const DiscoveryQuery({
    this.lat,
    this.lng,
    this.categories = const <String>{},
    this.dietary = const <String>{},
    this.freeDeliveryOnly = false,
    this.minRating,
    this.maxDeliveryMinutes,
    this.priceBand,
    this.openNow = false,
    this.offersOnly = false,
    this.sortBy = SortOption.recommended,
    this.radiusKm = 25,
    this.limit = 50,
  });

  /// Builds the query for the current filters + delivery location.
  factory DiscoveryQuery.from(
    FilterState filters,
    DeliveryLocation? location, {
    double radiusKm = 25,
    int limit = 50,
  }) {
    return DiscoveryQuery(
      lat: location?.lat,
      lng: location?.lng,
      categories: filters.categories,
      dietary: filters.dietaryNeeds,
      freeDeliveryOnly: filters.freeDeliveryOnly,
      minRating: filters.minRating,
      maxDeliveryMinutes: filters.maxDeliveryMinutes,
      priceBand: filters.priceBand,
      openNow: filters.openNow,
      offersOnly: filters.offersOnly,
      sortBy: filters.sortBy,
      radiusKm: radiusKm,
      limit: limit,
    );
  }

  final double? lat;
  final double? lng;
  final Set<String> categories;
  final Set<String> dietary;
  final bool freeDeliveryOnly;
  final double? minRating;
  final int? maxDeliveryMinutes;
  final int? priceBand;
  final bool openNow;
  final bool offersOnly;
  final SortOption sortBy;
  final double radiusKm;
  final int limit;

  /// `sort_by` values the backend understands. `recommended` means "let the
  /// ranker decide", so it is deliberately absent.
  String? get _sortParam {
    switch (sortBy) {
      case SortOption.rating:
        return 'rating';
      case SortOption.deliveryTime:
        return 'delivery_time';
      case SortOption.priceLowToHigh:
        return 'delivery_fee';
      case SortOption.recommended:
      case SortOption.distance:
      case SortOption.priceHighToLow:
        return null;
    }
  }

  Map<String, dynamic> toQueryParameters() {
    return <String, dynamic>{
      if (lat != null && lng != null) ...<String, dynamic>{
        'lat': lat,
        'lon': lng,
        'radius_km': radiusKm,
      },
      if (categories.isNotEmpty) 'category': categories.join(','),
      if (dietary.isNotEmpty) 'dietary': dietary.join(','),
      if (freeDeliveryOnly) 'free_delivery': true,
      if (minRating != null) 'min_rating': minRating,
      if (maxDeliveryMinutes != null)
        'max_delivery_minutes': maxDeliveryMinutes,
      if (priceBand != null) 'price_band': priceBand,
      if (openNow) 'open_now': true,
      if (offersOnly) 'has_promotions': true,
      if (_sortParam != null) 'sort_by': _sortParam,
      'limit': limit,
    };
  }

  /// Search uses `lng` where the browse endpoint uses `lon`. Not a typo.
  ///
  /// `GET /catalog/search` also has no `sort_by` (it always ranks by
  /// relevance) and no `has_promotions`, so both are dropped rather than sent
  /// and silently ignored.
  Map<String, dynamic> toSearchParameters(String query) {
    final params = toQueryParameters()
      ..remove('lon')
      ..remove('sort_by')
      ..remove('has_promotions');
    return <String, dynamic>{
      'q': query,
      if (lng != null) 'lng': lng,
      ...params,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiscoveryQuery &&
        other.lat == lat &&
        other.lng == lng &&
        _setEquals(other.categories, categories) &&
        _setEquals(other.dietary, dietary) &&
        other.freeDeliveryOnly == freeDeliveryOnly &&
        other.minRating == minRating &&
        other.maxDeliveryMinutes == maxDeliveryMinutes &&
        other.priceBand == priceBand &&
        other.openNow == openNow &&
        other.offersOnly == offersOnly &&
        other.sortBy == sortBy &&
        other.radiusKm == radiusKm &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(
        lat,
        lng,
        Object.hashAllUnordered(categories),
        Object.hashAllUnordered(dietary),
        freeDeliveryOnly,
        minRating,
        maxDeliveryMinutes,
        priceBand,
        openNow,
        offersOnly,
        sortBy,
        radiusKm,
        limit,
      );

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

/// Cache key for a search request: the text plus the filters in force.
class SearchQuery {
  const SearchQuery({required this.text, required this.discovery});

  final String text;
  final DiscoveryQuery discovery;

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.text == text &&
      other.discovery == discovery;

  @override
  int get hashCode => Object.hash(text, discovery);
}

// ── Providers ─────────────────────────────────────────────────────────────

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  double toRad(double deg) => deg * math.pi / 180.0;
  final dLat = toRad(lat2 - lat1);
  final dLng = toRad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(toRad(lat1)) *
          math.cos(toRad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return earthRadiusKm * 2 * math.asin(math.min(1, math.sqrt(a)));
}

/// Fills in `distance_km` locally when the backend did not rank by distance.
List<DiscoveryRestaurant> _withLocalDistances(
  List<DiscoveryRestaurant> stores,
  double? lat,
  double? lng,
) {
  if (lat == null || lng == null) return stores;
  return stores.map((store) {
    if (store.distanceKm != null) return store;
    final rLat = store.restaurant.latitude;
    final rLng = store.restaurant.longitude;
    if (rLat == null || rLng == null) return store;
    return store.withDistance(_haversineKm(lat, lng, rLat, rLng));
  }).toList(growable: false);
}

List<DiscoveryRestaurant> _parseList(Object? data) {
  if (data is! List) return const <DiscoveryRestaurant>[];
  return data
      .whereType<Map>()
      .map((e) => DiscoveryRestaurant.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}

/// The browse feed behind home, offers and pickup.
final discoveryFeedProvider = FutureProvider.autoDispose
    .family<List<DiscoveryRestaurant>, DiscoveryQuery>((ref, query) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get<dynamic>(
    '/catalog/restaurants',
    queryParameters: query.toQueryParameters(),
  );
  return _withLocalDistances(_parseList(response.data), query.lat, query.lng);
});

/// Typo-tolerant catalog search, split into store hits and dish hits.
final catalogSearchProvider = FutureProvider.autoDispose
    .family<SearchResults, SearchQuery>((ref, query) async {
  final text = query.text.trim();
  // The backend rejects anything shorter, so don't spend a round trip on it.
  if (text.length < 2) return SearchResults.empty;

  final dio = ref.watch(apiClientProvider);
  final response = await dio.get<dynamic>(
    '/catalog/search',
    queryParameters: query.discovery.toSearchParameters(text),
  );
  final stores = _withLocalDistances(
    _parseList(response.data),
    query.discovery.lat,
    query.discovery.lng,
  );

  final needle = text.toLowerCase();
  final dishes = <DishHit>[];
  for (final store in stores) {
    for (final dish in store.matchedDishes) {
      dishes.add(DishHit(dish: dish, store: store));
    }
  }
  // A store whose own name matched leads with the store row; one that only
  // matched through its menu is better represented by the dish.
  bool matchedByName(DiscoveryRestaurant store) =>
      store.name.toLowerCase().contains(needle) ||
      store.restaurant.category.toLowerCase().contains(needle);

  final storeHits = stores.where(matchedByName).toList(growable: false);
  return SearchResults(
    stores: storeHits.isEmpty ? stores : storeHits,
    dishes: dishes,
  );
});
