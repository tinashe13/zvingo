// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'restaurant_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$restaurantListHash() => r'2cdd0c0d1bea299234f2c41919b37b91c5ee2ab3';

/// See also [restaurantList].
@ProviderFor(restaurantList)
final restaurantListProvider =
    AutoDisposeFutureProvider<List<Restaurant>>.internal(
  restaurantList,
  name: r'restaurantListProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$restaurantListHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef RestaurantListRef = AutoDisposeFutureProviderRef<List<Restaurant>>;
String _$restaurantDetailHash() => r'7b7975cf73a505d5dd4231fb91ead0b89b8426cc';

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

/// See also [restaurantDetail].
@ProviderFor(restaurantDetail)
const restaurantDetailProvider = RestaurantDetailFamily();

/// See also [restaurantDetail].
class RestaurantDetailFamily extends Family<AsyncValue<Restaurant>> {
  /// See also [restaurantDetail].
  const RestaurantDetailFamily();

  /// See also [restaurantDetail].
  RestaurantDetailProvider call(
    String id,
  ) {
    return RestaurantDetailProvider(
      id,
    );
  }

  @override
  RestaurantDetailProvider getProviderOverride(
    covariant RestaurantDetailProvider provider,
  ) {
    return call(
      provider.id,
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
  String? get name => r'restaurantDetailProvider';
}

/// See also [restaurantDetail].
class RestaurantDetailProvider extends AutoDisposeFutureProvider<Restaurant> {
  /// See also [restaurantDetail].
  RestaurantDetailProvider(
    String id,
  ) : this._internal(
          (ref) => restaurantDetail(
            ref as RestaurantDetailRef,
            id,
          ),
          from: restaurantDetailProvider,
          name: r'restaurantDetailProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$restaurantDetailHash,
          dependencies: RestaurantDetailFamily._dependencies,
          allTransitiveDependencies:
              RestaurantDetailFamily._allTransitiveDependencies,
          id: id,
        );

  RestaurantDetailProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.id,
  }) : super.internal();

  final String id;

  @override
  Override overrideWith(
    FutureOr<Restaurant> Function(RestaurantDetailRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: RestaurantDetailProvider._internal(
        (ref) => create(ref as RestaurantDetailRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        id: id,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Restaurant> createElement() {
    return _RestaurantDetailProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is RestaurantDetailProvider && other.id == id;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, id.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin RestaurantDetailRef on AutoDisposeFutureProviderRef<Restaurant> {
  /// The parameter `id` of this provider.
  String get id;
}

class _RestaurantDetailProviderElement
    extends AutoDisposeFutureProviderElement<Restaurant>
    with RestaurantDetailRef {
  _RestaurantDetailProviderElement(super.provider);

  @override
  String get id => (origin as RestaurantDetailProvider).id;
}

String _$searchRestaurantItemsHash() =>
    r'cedc300c10234137e65a0dfd019ad4b556b9183d';

/// See also [searchRestaurantItems].
@ProviderFor(searchRestaurantItems)
const searchRestaurantItemsProvider = SearchRestaurantItemsFamily();

/// See also [searchRestaurantItems].
class SearchRestaurantItemsFamily extends Family<AsyncValue<List<MenuItem>>> {
  /// See also [searchRestaurantItems].
  const SearchRestaurantItemsFamily();

  /// See also [searchRestaurantItems].
  SearchRestaurantItemsProvider call(
    String restaurantId,
    String query,
  ) {
    return SearchRestaurantItemsProvider(
      restaurantId,
      query,
    );
  }

  @override
  SearchRestaurantItemsProvider getProviderOverride(
    covariant SearchRestaurantItemsProvider provider,
  ) {
    return call(
      provider.restaurantId,
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
  String? get name => r'searchRestaurantItemsProvider';
}

/// See also [searchRestaurantItems].
class SearchRestaurantItemsProvider
    extends AutoDisposeFutureProvider<List<MenuItem>> {
  /// See also [searchRestaurantItems].
  SearchRestaurantItemsProvider(
    String restaurantId,
    String query,
  ) : this._internal(
          (ref) => searchRestaurantItems(
            ref as SearchRestaurantItemsRef,
            restaurantId,
            query,
          ),
          from: searchRestaurantItemsProvider,
          name: r'searchRestaurantItemsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$searchRestaurantItemsHash,
          dependencies: SearchRestaurantItemsFamily._dependencies,
          allTransitiveDependencies:
              SearchRestaurantItemsFamily._allTransitiveDependencies,
          restaurantId: restaurantId,
          query: query,
        );

  SearchRestaurantItemsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.restaurantId,
    required this.query,
  }) : super.internal();

  final String restaurantId;
  final String query;

  @override
  Override overrideWith(
    FutureOr<List<MenuItem>> Function(SearchRestaurantItemsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: SearchRestaurantItemsProvider._internal(
        (ref) => create(ref as SearchRestaurantItemsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        restaurantId: restaurantId,
        query: query,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<MenuItem>> createElement() {
    return _SearchRestaurantItemsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is SearchRestaurantItemsProvider &&
        other.restaurantId == restaurantId &&
        other.query == query;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, restaurantId.hashCode);
    hash = _SystemHash.combine(hash, query.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin SearchRestaurantItemsRef on AutoDisposeFutureProviderRef<List<MenuItem>> {
  /// The parameter `restaurantId` of this provider.
  String get restaurantId;

  /// The parameter `query` of this provider.
  String get query;
}

class _SearchRestaurantItemsProviderElement
    extends AutoDisposeFutureProviderElement<List<MenuItem>>
    with SearchRestaurantItemsRef {
  _SearchRestaurantItemsProviderElement(super.provider);

  @override
  String get restaurantId =>
      (origin as SearchRestaurantItemsProvider).restaurantId;
  @override
  String get query => (origin as SearchRestaurantItemsProvider).query;
}

String _$restaurantPromotionsHash() =>
    r'f950bce83267c5f3522304b3e406f5a2b86b4665';

/// See also [restaurantPromotions].
@ProviderFor(restaurantPromotions)
const restaurantPromotionsProvider = RestaurantPromotionsFamily();

/// See also [restaurantPromotions].
class RestaurantPromotionsFamily extends Family<AsyncValue<List<Promotion>>> {
  /// See also [restaurantPromotions].
  const RestaurantPromotionsFamily();

  /// See also [restaurantPromotions].
  RestaurantPromotionsProvider call(
    String restaurantId,
  ) {
    return RestaurantPromotionsProvider(
      restaurantId,
    );
  }

  @override
  RestaurantPromotionsProvider getProviderOverride(
    covariant RestaurantPromotionsProvider provider,
  ) {
    return call(
      provider.restaurantId,
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
  String? get name => r'restaurantPromotionsProvider';
}

/// See also [restaurantPromotions].
class RestaurantPromotionsProvider
    extends AutoDisposeFutureProvider<List<Promotion>> {
  /// See also [restaurantPromotions].
  RestaurantPromotionsProvider(
    String restaurantId,
  ) : this._internal(
          (ref) => restaurantPromotions(
            ref as RestaurantPromotionsRef,
            restaurantId,
          ),
          from: restaurantPromotionsProvider,
          name: r'restaurantPromotionsProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$restaurantPromotionsHash,
          dependencies: RestaurantPromotionsFamily._dependencies,
          allTransitiveDependencies:
              RestaurantPromotionsFamily._allTransitiveDependencies,
          restaurantId: restaurantId,
        );

  RestaurantPromotionsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.restaurantId,
  }) : super.internal();

  final String restaurantId;

  @override
  Override overrideWith(
    FutureOr<List<Promotion>> Function(RestaurantPromotionsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: RestaurantPromotionsProvider._internal(
        (ref) => create(ref as RestaurantPromotionsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        restaurantId: restaurantId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<Promotion>> createElement() {
    return _RestaurantPromotionsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is RestaurantPromotionsProvider &&
        other.restaurantId == restaurantId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, restaurantId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin RestaurantPromotionsRef on AutoDisposeFutureProviderRef<List<Promotion>> {
  /// The parameter `restaurantId` of this provider.
  String get restaurantId;
}

class _RestaurantPromotionsProviderElement
    extends AutoDisposeFutureProviderElement<List<Promotion>>
    with RestaurantPromotionsRef {
  _RestaurantPromotionsProviderElement(super.provider);

  @override
  String get restaurantId =>
      (origin as RestaurantPromotionsProvider).restaurantId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
