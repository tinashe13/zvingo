import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/core/api_client.dart';

part 'geocode_provider.g.dart';

/// One address suggestion from `GET /location/geocode`.
class GeocodedAddress {
  const GeocodedAddress({
    required this.displayName,
    required this.lat,
    required this.lng,
    this.type = '',
  });

  final String displayName;
  final double lat;
  final double lng;

  /// Nominatim's place type (`house`, `road`, `suburb`…), used only to pick an
  /// icon. Never shown raw.
  final String type;

  /// The part before the first comma — the bit a human reads first.
  String get primaryLine {
    final comma = displayName.indexOf(',');
    return comma == -1 ? displayName : displayName.substring(0, comma).trim();
  }

  /// Everything after the first comma.
  String get secondaryLine {
    final comma = displayName.indexOf(',');
    return comma == -1 ? '' : displayName.substring(comma + 1).trim();
  }

  factory GeocodedAddress.fromJson(Map<String, dynamic> json) =>
      GeocodedAddress(
        displayName: (json['display_name'] ?? '').toString(),
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        type: (json['type'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'lat': lat,
        'lng': lng,
        'type': type,
      };
}

/// Client-side guard around the shared Nominatim quota.
///
/// **Finding X3.** `GET /location/geocode` proxies OpenStreetMap Nominatim,
/// whose usage policy is **one request per second, with caching, from an
/// identified client**. One customer typing "Samora Machel Avenue" is 21
/// keystrokes; a per-keystroke client would burn the whole platform's budget
/// and get the server's IP banned, taking address search down for every user.
/// Agent B3 is adding auth, a Redis cache and a rate limit on the server. This
/// class is the client half of the same fix and does four things:
///
/// 1. **Debounce** — nothing is sent until typing has paused for
///    [debounce] (450ms).
/// 2. **Minimum length** — a query under [minQueryLength] characters is never
///    sent; it could only return noise anyway.
/// 3. **Cache** — normalised queries are memoised in memory and mirrored into
///    the `cache` Hive box, so re-opening the sheet, editing an address or
///    deleting a character costs zero requests. Entries live [cacheTtl].
/// 4. **Throttle** — at most one request per [minInterval] (1100ms) leaves the
///    app, matching Nominatim's stated policy with headroom.
class GeocodeService {
  GeocodeService(this._dio);

  final Dio _dio;

  static const Duration debounce = Duration(milliseconds: 450);
  static const Duration minInterval = Duration(milliseconds: 1100);
  static const Duration cacheTtl = Duration(days: 7);
  static const int minQueryLength = 3;
  static const int maxCacheEntries = 120;
  static const String _cacheBoxName = 'cache';
  static const String _cacheKeyPrefix = 'geocode:';

  final Map<String, _CacheEntry> _memory = <String, _CacheEntry>{};
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Lower-cased, whitespace-collapsed key so "Samora  Machel" and
  /// "samora machel" are one cache entry.
  static String normalise(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Whether [query] is worth sending at all.
  static bool isSearchable(String query) =>
      normalise(query).length >= minQueryLength;

  /// A cached answer for [query], or null. Never touches the network.
  List<GeocodedAddress>? cached(String query) {
    final key = normalise(query);
    final entry = _memory[key] ?? _readPersisted(key);
    if (entry == null) return null;
    if (DateTime.now().difference(entry.storedAt) > cacheTtl) {
      _memory.remove(key);
      return null;
    }
    _memory[key] = entry;
    return entry.results;
  }

  /// Search, honouring the cache and the 1 req/sec throttle.
  ///
  /// Throws a [DioException] on a network failure so the caller can render
  /// `ZvErrorState` with real copy.
  Future<List<GeocodedAddress>> search(String query) async {
    final key = normalise(query);
    if (key.length < minQueryLength) return const [];

    final hit = cached(key);
    if (hit != null) return hit;

    // Space requests at least `minInterval` apart, whatever the caller does.
    final sinceLast = DateTime.now().difference(_lastRequestAt);
    if (sinceLast < minInterval) {
      await Future<void>.delayed(minInterval - sinceLast);
    }
    _lastRequestAt = DateTime.now();

    final response = await _dio.get<dynamic>(
      '/location/geocode',
      queryParameters: {'q': key, 'country': 'zw'},
    );

    final data = response.data;
    final results = data is List
        ? data
            .whereType<Map>()
            .map((e) => GeocodedAddress.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <GeocodedAddress>[];

    _store(key, results);
    return results;
  }

  void _store(String key, List<GeocodedAddress> results) {
    final entry = _CacheEntry(results: results, storedAt: DateTime.now());
    _memory[key] = entry;
    if (_memory.length > maxCacheEntries) {
      // Cheap LRU-ish eviction: drop the oldest quarter.
      final ordered = _memory.entries.toList()
        ..sort((a, b) => a.value.storedAt.compareTo(b.value.storedAt));
      for (final e in ordered.take(maxCacheEntries ~/ 4)) {
        _memory.remove(e.key);
      }
    }
    try {
      if (Hive.isBoxOpen(_cacheBoxName)) {
        Hive.box(_cacheBoxName).put(
          '$_cacheKeyPrefix$key',
          jsonEncode({
            'at': entry.storedAt.millisecondsSinceEpoch,
            'results': results.map((r) => r.toJson()).toList(),
          }),
        );
      }
    } catch (_) {
      // A cache that cannot be written is not an error worth surfacing.
    }
  }

  _CacheEntry? _readPersisted(String key) {
    try {
      if (!Hive.isBoxOpen(_cacheBoxName)) return null;
      final raw = Hive.box(_cacheBoxName).get('$_cacheKeyPrefix$key');
      if (raw is! String) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return _CacheEntry(
        storedAt:
            DateTime.fromMillisecondsSinceEpoch(decoded['at'] as int? ?? 0),
        results: (decoded['results'] as List<dynamic>)
            .map((e) => GeocodedAddress.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

class _CacheEntry {
  const _CacheEntry({required this.results, required this.storedAt});

  final List<GeocodedAddress> results;
  final DateTime storedAt;
}

@Riverpod(keepAlive: true)
GeocodeService geocodeService(Ref ref) =>
    GeocodeService(ref.watch(apiClientProvider));

/// What the search sheet is currently showing.
class GeocodeSearchState {
  const GeocodeSearchState({
    this.query = '',
    this.results = const [],
    this.loading = false,
    this.error,
    this.hasSearched = false,
  });

  final String query;
  final List<GeocodedAddress> results;
  final bool loading;
  final Object? error;

  /// True once at least one query has completed, so "no results" can be told
  /// apart from "nothing typed yet".
  final bool hasSearched;

  GeocodeSearchState copyWith({
    String? query,
    List<GeocodedAddress>? results,
    bool? loading,
    Object? error,
    bool clearError = false,
    bool? hasSearched,
  }) {
    return GeocodeSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}

/// Drives the address-search sheet: debounce in, results out.
///
/// A cache hit renders synchronously with no spinner at all, which is what
/// makes back-spacing through a query feel instant instead of flickering.
@riverpod
class GeocodeSearch extends _$GeocodeSearch {
  Timer? _debounce;
  int _generation = 0;

  @override
  GeocodeSearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const GeocodeSearchState();
  }

  void onQueryChanged(String value) {
    _debounce?.cancel();
    final generation = ++_generation;

    if (!GeocodeService.isSearchable(value)) {
      state = GeocodeSearchState(query: value);
      return;
    }

    final service = ref.read(geocodeServiceProvider);
    final cached = service.cached(value);
    if (cached != null) {
      state = state.copyWith(
        query: value,
        results: cached,
        loading: false,
        clearError: true,
        hasSearched: true,
      );
      return;
    }

    state = state.copyWith(query: value, loading: true, clearError: true);
    _debounce = Timer(GeocodeService.debounce, () {
      _run(value, generation);
    });
  }

  /// Re-runs the current query immediately — the Retry action on an error.
  Future<void> retry() => _run(state.query, ++_generation);

  Future<void> _run(String query, int generation) async {
    if (!GeocodeService.isSearchable(query)) return;
    try {
      final results = await ref.read(geocodeServiceProvider).search(query);
      if (generation != _generation) return; // a newer query superseded this one
      state = state.copyWith(
        query: query,
        results: results,
        loading: false,
        clearError: true,
        hasSearched: true,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(
        query: query,
        loading: false,
        error: error,
        hasSearched: true,
      );
    }
  }
}
