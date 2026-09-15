import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/auth/session_interceptor.dart';
import 'package:consumer_app/features/auth/token_store.dart';

part 'favourites_provider.g.dart';

/// How the favourite set relates to the server right now.
enum FavouritesSync {
  /// Never synced in this session — showing the Hive cache.
  idle,

  /// A `GET /auth/favourites` is in flight.
  loading,

  /// In step with the server.
  synced,

  /// The last sync failed. The local set is still correct and usable.
  failed,
}

/// Favourite restaurants, cached locally and synced with `/auth/favourites`.
///
/// The state stays a plain `Set<String>` that reads synchronously, because
/// every restaurant card in the app watches it to draw one heart — making that
/// an `AsyncValue` would put a spinner inside every card in a list.
///
/// Instead:
/// * the set is seeded from Hive the instant the app starts, so hearts are
///   correct offline and on first frame;
/// * `GET /auth/favourites` reconciles it in the background;
/// * [toggle] is **optimistic** — the heart fills immediately, the
///   `POST /auth/favourites/{id}` follows, and a failure rolls the set back to
///   exactly what it was rather than leaving a heart lying about the server.
@Riverpod(keepAlive: true)
class Favourites extends _$Favourites {
  static const String _boxName = 'favourites';
  static const String _key = 'restaurant_ids';

  @override
  Set<String> build() {
    _loadFromCache();
    // Reconcile with the server once the first frame is out of the way.
    Future.microtask(refresh);
    return {};
  }

  Dio get _dio => ref.read(apiClientProvider);

  Future<Box> get _box async =>
      Hive.isBoxOpen(_boxName) ? Hive.box(_boxName) : Hive.openBox(_boxName);

  Future<void> _loadFromCache() async {
    try {
      final box = await _box;
      final stored = box.get(_key, defaultValue: <dynamic>[]);
      final cached = Set<String>.from(stored as Iterable);
      // Don't clobber a server result that landed first.
      if (state.isEmpty && cached.isNotEmpty) state = cached;
    } catch (_) {
      // No cache yet — the server sync below fills it in.
    }
  }

  Future<void> _persist(Set<String> ids) async {
    try {
      final box = await _box;
      await box.put(_key, ids.toList());
    } catch (_) {
      // A write-through cache failing is not worth interrupting the user for.
    }
  }

  /// Pull the authoritative set from the server.
  ///
  /// Signed-out users keep whatever is cached: their hearts should not vanish
  /// just because the session ended.
  Future<void> refresh() async {
    if (!TokenStore.isSignedIn) return;
    ref.read(favouritesSyncStatusProvider.notifier).set(FavouritesSync.loading);
    try {
      ref.read(authSessionProvider);
      final response = await _dio.get<dynamic>('/auth/favourites');
      final data = response.data;
      final ids = data is Map && data['favourite_restaurant_ids'] is List
          ? (data['favourite_restaurant_ids'] as List)
              .map((e) => e.toString())
              .toSet()
          : <String>{};
      state = ids;
      await _persist(ids);
      ref.read(favouritesSyncStatusProvider.notifier).set(FavouritesSync.synced);
    } catch (_) {
      ref.read(favouritesSyncStatusProvider.notifier).set(FavouritesSync.failed);
    }
  }

  /// Add or remove a restaurant. Returns `true` if it is a favourite afterwards.
  ///
  /// Optimistic: the UI updates first. If the server refuses, the previous set
  /// is restored and [FavouritesSync.failed] is published so the screen can say
  /// so instead of silently disagreeing with the backend.
  Future<bool> toggle(String restaurantId) async {
    final previous = Set<String>.from(state);
    final next = Set<String>.from(state);
    final nowFavourite = !next.contains(restaurantId);
    if (nowFavourite) {
      next.add(restaurantId);
    } else {
      next.remove(restaurantId);
    }

    state = next;
    await _persist(next);

    if (!TokenStore.isSignedIn) return nowFavourite;

    try {
      final response =
          await _dio.post<dynamic>('/auth/favourites/$restaurantId');
      final data = response.data;
      if (data is Map && data['favourite_restaurant_ids'] is List) {
        // The server is the authority; adopt its list verbatim.
        final ids = (data['favourite_restaurant_ids'] as List)
            .map((e) => e.toString())
            .toSet();
        state = ids;
        await _persist(ids);
        ref.read(favouritesSyncStatusProvider.notifier).set(FavouritesSync.synced);
        return ids.contains(restaurantId);
      }
      return nowFavourite;
    } catch (_) {
      // Roll back rather than leave a heart that disagrees with the server.
      // No rethrow: the heart in a restaurant card is tapped with a plain
      // `onPressed`, and an unawaited throw there would surface as a framework
      // error with nothing useful for the user. The failed status is how a
      // screen learns about it.
      state = previous;
      await _persist(previous);
      ref.read(favouritesSyncStatusProvider.notifier).set(FavouritesSync.failed);
      return previous.contains(restaurantId);
    }
  }

  bool isFavourite(String restaurantId) => state.contains(restaurantId);
}

/// Sync status for the favourites screen's banner. Separate from [Favourites]
/// so that watching the status never rebuilds every restaurant card.
@Riverpod(keepAlive: true)
class FavouritesSyncStatus extends _$FavouritesSyncStatus {
  @override
  FavouritesSync build() => FavouritesSync.idle;

  void set(FavouritesSync value) => state = value;
}
