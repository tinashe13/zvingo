// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'promo_banner.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$activePromosHash() => r'50777b2ce13be7e1b5f71bbf6fbf7b5d1c561a90';

/// Fetches active promotions from the backend.
/// Returns an empty list if the endpoint is unavailable or returns no promos.
///
/// Copied from [activePromos].
@ProviderFor(activePromos)
final activePromosProvider =
    AutoDisposeFutureProvider<List<PromoData>>.internal(
  activePromos,
  name: r'activePromosProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$activePromosHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ActivePromosRef = AutoDisposeFutureProviderRef<List<PromoData>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
