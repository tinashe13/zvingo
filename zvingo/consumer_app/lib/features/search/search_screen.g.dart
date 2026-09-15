// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$searchRestaurantsHash() => r'54cdb213719ac46d93e17fa16a5e06e08434a496';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [searchRestaurants].
@ProviderFor(searchRestaurants)
const searchRestaurantsProvider = SearchRestaurantsFamily();

/// See also [searchRestaurants].
class SearchRestaurantsFamily extends Family<AsyncValue<List<Restaurant>>> {
  /// See also [searchRestaurants].
  const SearchRestaurantsFamily();

  /// See also [searchRestaurants].
  SearchRestaurantsProvider call(
    String query,
  ) {
    return SearchRestaurantsProvider(
      query,
    );
  }

  @override
  SearchRestaurantsProvider getProviderOverride(
    covariant SearchRestaurantsProvider provider,
  ) {
    return call(
      provider.query,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'searchRestaurantsProvider';
}

/// See also [searchRestaurants].
class SearchRestaurantsProvider
    extends AutoDisposeFutureProvider<List<Restaurant>> {
  /// See also [searchRestaurants].
  SearchRestaurantsProvider(
    String query,
  ) : this._internal(
          (ref) => searchRestaurants(
            ref as SearchRestaurantsRef,
            query,
          ),
          from: searchRestaurantsProvider,
          name: r'searchRestaurantsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$searchRestaurantsHash,
          dependencies: SearchRestaurantsFamily._dependencies,
          allTransitiveDependencies:
              SearchRestaurantsFamily._allTransitiveDependencies,
          query: query,
        );

  SearchRestaurantsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.query,
  }) : super.internal();

  final String query;

  @override
  Override overrideWith(
    FutureOr<List<Restaurant>> Function(SearchRestaurantsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SearchRestaurantsProvider._internal(
        (ref) => create(ref as SearchRestaurantsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        query: query,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<Restaurant>> createElement() {
    return _SearchRestaurantsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SearchRestaurantsProvider && other.query == query;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, query.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin SearchRestaurantsRef on AutoDisposeFutureProviderRef<List<Restaurant>> {
  /// The parameter `query` of this provider.
  String get query;
}

class _SearchRestaurantsProviderElement
    extends AutoDisposeFutureProviderElement<List<Restaurant>>
    with SearchRestaurantsRef {
  _SearchRestaurantsProviderElement(super.provider);

  @override
  String get query => (origin as SearchRestaurantsProvider).query;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
