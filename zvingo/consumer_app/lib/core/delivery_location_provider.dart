import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'delivery_location_provider.g.dart';

/// Represents the user's delivery address with coordinates.
class DeliveryLocation {
  final double lat;
  final double lng;
  final String displayName;

  const DeliveryLocation({
    required this.lat,
    required this.lng,
    required this.displayName,
  });
}

/// Manages the user's selected delivery location.
/// Must be set before checkout can proceed.
/// Initialised in the background by [locationStartupProvider].
@Riverpod(keepAlive: true)
class DeliveryLocationNotifier extends _$DeliveryLocationNotifier {
  @override
  DeliveryLocation? build() {
    return null; // locationStartupProvider sets this on app start.
  }

  void setLocation(double lat, double lng, String displayName) {
    state = DeliveryLocation(lat: lat, lng: lng, displayName: displayName);
  }

  void clear() {
    state = null;
  }
}
