// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'promo_banner.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$activePromosHash() => r'ac89e38f0ed055e804e8c1f4043e35289eea5119';

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

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ActivePromosRef = AutoDisposeFutureProviderRef<List<PromoData>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
