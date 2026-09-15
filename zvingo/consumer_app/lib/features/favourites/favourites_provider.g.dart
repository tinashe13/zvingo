// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favourites_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$favouritesHash() => r'fde540ff0a33b7317da85d59159320046ce993ef';

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
///
/// Copied from [Favourites].
@ProviderFor(Favourites)
final favouritesProvider = NotifierProvider<Favourites, Set<String>>.internal(
  Favourites.new,
  name: r'favouritesProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$favouritesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Favourites = Notifier<Set<String>>;
String _$favouritesSyncStatusHash() =>
    r'968cf2d4a61c639bc47c0c794769abb9db038023';

/// Sync status for the favourites screen's banner. Separate from [Favourites]
/// so that watching the status never rebuilds every restaurant card.
///
/// Copied from [FavouritesSyncStatus].
@ProviderFor(FavouritesSyncStatus)
final favouritesSyncStatusProvider =
    NotifierProvider<FavouritesSyncStatus, FavouritesSync>.internal(
  FavouritesSyncStatus.new,
  name: r'favouritesSyncStatusProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$favouritesSyncStatusHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$FavouritesSyncStatus = Notifier<FavouritesSync>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
