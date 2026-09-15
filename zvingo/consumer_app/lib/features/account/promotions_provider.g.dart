// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'promotions_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$activePromotionsHash() => r'2ab3343f39560e916ec8ba4f3cd3383c3b0de02d';

/// Every promotion currently running, newest first.
///
/// `GET /catalog/promotions` is public and already excludes promos that have
/// expired, not started, or hit their usage cap — so anything returned here is
/// something the customer could actually use today.
///
/// Copied from [activePromotions].
@ProviderFor(activePromotions)
final activePromotionsProvider =
    AutoDisposeFutureProvider<List<Promotion>>.internal(
  activePromotions,
  name: r'activePromotionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$activePromotionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ActivePromotionsRef = AutoDisposeFutureProviderRef<List<Promotion>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
