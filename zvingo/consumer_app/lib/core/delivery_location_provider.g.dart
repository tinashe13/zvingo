// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delivery_location_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$deliveryLocationNotifierHash() =>
    r'9cee78cf8d48e11957412ed7dcdc0862df89d051';

/// Manages the user's selected delivery location.
/// Must be set before checkout can proceed.
/// Initialised in the background by [locationStartupProvider].
///
/// Copied from [DeliveryLocationNotifier].
@ProviderFor(DeliveryLocationNotifier)
final deliveryLocationNotifierProvider =
    NotifierProvider<DeliveryLocationNotifier, DeliveryLocation?>.internal(
  DeliveryLocationNotifier.new,
  name: r'deliveryLocationNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$deliveryLocationNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$DeliveryLocationNotifier = Notifier<DeliveryLocation?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
