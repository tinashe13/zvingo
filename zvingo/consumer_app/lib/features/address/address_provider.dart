import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/saved_address.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'address_provider.g.dart';

@Riverpod(keepAlive: true)
class SavedAddresses extends _$SavedAddresses {
  late Box<SavedAddress> _box;

  @override
  List<SavedAddress> build() {
    _box = Hive.box<SavedAddress>('addresses');
    return _box.values.toList();
  }

  Future<void> addAddress(SavedAddress address) async {
    // If this is marked as default, clear default from others
    if (address.isDefault) {
      await _clearDefaults();
    }
    await _box.put(address.id, address);
    state = _box.values.toList();
  }

  Future<void> updateAddress(SavedAddress address) async {
    if (address.isDefault) {
      await _clearDefaults();
    }
    await _box.put(address.id, address);
    state = _box.values.toList();
  }

  Future<void> deleteAddress(String id) async {
    await _box.delete(id);
    state = _box.values.toList();
  }

  Future<void> setDefault(String id) async {
    await _clearDefaults();
    final address = _box.get(id);
    if (address != null) {
      final updated = address.copyWith(isDefault: true);
      await _box.put(id, updated);
    }
    state = _box.values.toList();
  }

  Future<void> _clearDefaults() async {
    for (final entry in _box.toMap().entries) {
      if (entry.value.isDefault) {
        await _box.put(entry.key, entry.value.copyWith(isDefault: false));
      }
    }
  }

  SavedAddress? get defaultAddress {
    try {
      return state.firstWhere((a) => a.isDefault);
    } catch (_) {
      return state.isNotEmpty ? state.first : null;
    }
  }

  /// Select an address and update the delivery location provider
  void selectAddress(SavedAddress address) {
    ref.read(deliveryLocationNotifierProvider.notifier).setLocation(
          address.lat,
          address.lng,
          address.address,
        );
  }
}

/// Runs once when the authenticated shell mounts.
/// Sets the delivery location from the saved default address, or falls back
/// to the device's current GPS position — all in the background.
@Riverpod(keepAlive: true)
Future<void> locationStartup(Ref ref) async {
  // 1. Use a saved default address (or the first saved address).
  final addresses = ref.read(savedAddressesProvider);
  final defaultAddr = addresses.where((a) => a.isDefault).firstOrNull ??
      (addresses.isNotEmpty ? addresses.first : null);

  if (defaultAddr != null) {
    ref.read(deliveryLocationNotifierProvider.notifier).setLocation(
          defaultAddr.lat,
          defaultAddr.lng,
          defaultAddr.address,
        );
    return;
  }

  // 2. No saved address — pre-fetch current GPS in the background.
  try {
    final current = await ref.read(currentLocationAddressProvider.future);
    if (ref.read(deliveryLocationNotifierProvider) == null) {
      ref.read(deliveryLocationNotifierProvider.notifier).setLocation(
            current.lat,
            current.lng,
            current.address,
          );
    }
  } catch (_) {
    // Permission denied or GPS unavailable — leave delivery location as null.
  }
}

/// Gets the user's current location and reverse geocodes it
@riverpod
Future<SavedAddress> currentLocationAddress(Ref ref) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Location services are disabled');
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied');
    }
  }
  if (permission == LocationPermission.deniedForever) {
    throw Exception('Location permissions are permanently denied');
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 10),
    ),
  );

  String displayAddress =
      '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
  try {
    final placemarks =
        await placemarkFromCoordinates(position.latitude, position.longitude);
    if (placemarks.isNotEmpty) {
      final p = placemarks.first;
      final parts = <String>[
        if (p.street != null && p.street!.isNotEmpty) p.street!,
        if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
        if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty)
          p.administrativeArea!,
      ];
      if (parts.isNotEmpty) {
        displayAddress = parts.join(', ');
      }
    }
  } catch (e) {
    debugPrint('Reverse geocoding failed: $e');
  }

  return SavedAddress(
    id: 'current_location',
    label: 'Current Location',
    address: displayAddress,
    lat: position.latitude,
    lng: position.longitude,
  );
}
