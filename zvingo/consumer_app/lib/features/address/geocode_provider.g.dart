// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'geocode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$geocodeServiceHash() => r'299bf0e4f1e8ddc1d3341f70bb6e448945e3db9c';

/// See also [geocodeService].
@ProviderFor(geocodeService)
final geocodeServiceProvider = Provider<GeocodeService>.internal(
  geocodeService,
  name: r'geocodeServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$geocodeServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef GeocodeServiceRef = ProviderRef<GeocodeService>;
String _$geocodeSearchHash() => r'729b43495434dba1da00da144840920b1f945c38';

/// Drives the address-search sheet: debounce in, results out.
///
/// A cache hit renders synchronously with no spinner at all, which is what
/// makes back-spacing through a query feel instant instead of flickering.
///
/// Copied from [GeocodeSearch].
@ProviderFor(GeocodeSearch)
final geocodeSearchProvider =
    AutoDisposeNotifierProvider<GeocodeSearch, GeocodeSearchState>.internal(
  GeocodeSearch.new,
  name: r'geocodeSearchProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$geocodeSearchHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$GeocodeSearch = AutoDisposeNotifier<GeocodeSearchState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
