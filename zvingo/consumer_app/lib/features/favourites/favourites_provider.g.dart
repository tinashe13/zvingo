// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favourites_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$favouritesHash() => r'8955a76ef89d218f83a13a1c8491335b9763383f';

/// Manages favourite restaurant IDs — persisted in Hive
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
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
