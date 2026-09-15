// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'address_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$locationStartupHash() => r'ec3433538d4b732fae82fbd62c00aff89d8e05fe';

/// Runs once when the authenticated shell mounts.
/// Sets the delivery location from the saved default address, or falls back
/// to the device's current GPS position — all in the background.
///
/// Copied from [locationStartup].
@ProviderFor(locationStartup)
final locationStartupProvider = FutureProvider<void>.internal(
  locationStartup,
  name: r'locationStartupProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$locationStartupHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef LocationStartupRef = FutureProviderRef<void>;
String _$currentLocationAddressHash() =>
    r'1e543148446a680200d1084d26fb87b9f23bfab9';

/// Gets the user's current location and reverse geocodes it
///
/// Copied from [currentLocationAddress].
@ProviderFor(currentLocationAddress)
final currentLocationAddressProvider =
    AutoDisposeFutureProvider<SavedAddress>.internal(
  currentLocationAddress,
  name: r'currentLocationAddressProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentLocationAddressHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef CurrentLocationAddressRef = AutoDisposeFutureProviderRef<SavedAddress>;
String _$savedAddressesHash() => r'94d6c00d48d7ce655f34b99b56060fbc5de5ec4c';

/// See also [SavedAddresses].
@ProviderFor(SavedAddresses)
final savedAddressesProvider =
    NotifierProvider<SavedAddresses, List<SavedAddress>>.internal(
  SavedAddresses.new,
  name: r'savedAddressesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$savedAddressesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SavedAddresses = Notifier<List<SavedAddress>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
