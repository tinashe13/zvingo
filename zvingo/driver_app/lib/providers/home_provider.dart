import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../core/api_client.dart';

/// Home screen state.
class HomeState {
  final bool isDashing;
  final int todayEarningsCents;
  final int todayTrips;
  final String selectedZone;
  final List<ZoneStatus> zones;

  const HomeState({
    this.isDashing = false,
    this.todayEarningsCents = 0,
    this.todayTrips = 0,
    this.selectedZone = 'Harare CBD',
    this.zones = const [],
  });

  HomeState copyWith({
    bool? isDashing,
    int? todayEarningsCents,
    int? todayTrips,
    String? selectedZone,
    List<ZoneStatus>? zones,
  }) {
    return HomeState(
      isDashing: isDashing ?? this.isDashing,
      todayEarningsCents: todayEarningsCents ?? this.todayEarningsCents,
      todayTrips: todayTrips ?? this.todayTrips,
      selectedZone: selectedZone ?? this.selectedZone,
      zones: zones ?? this.zones,
    );
  }

  String get formattedEarnings =>
      '\$${(todayEarningsCents / 100).toStringAsFixed(2)}';
}

/// Zone busy status.
class ZoneStatus {
  final String name;
  final String status; // 'busy', 'moderate', 'quiet'
  final double lat;
  final double lng;

  const ZoneStatus({
    required this.name,
    required this.status,
    this.lat = 0,
    this.lng = 0,
  });
}

/// Home provider — mirrors HomeViewModel functionality.
class HomeNotifier extends StateNotifier<HomeState> {
  final ApiClient _apiClient;

  HomeNotifier(this._apiClient)
      : super(const HomeState(
          zones: [
            ZoneStatus(name: 'Harare CBD', status: 'busy', lat: -17.829, lng: 31.054),
            ZoneStatus(name: 'Avondale', status: 'moderate', lat: -17.794, lng: 31.033),
            ZoneStatus(name: 'Borrowdale', status: 'quiet', lat: -17.766, lng: 31.087),
            ZoneStatus(name: 'Mt Pleasant', status: 'moderate', lat: -17.782, lng: 31.051),
          ],
        ));

  /// Mirror the real shift state.
  ///
  /// This used to be `toggleDashing()`, which flipped a local boolean whether
  /// or not the shift actually started. A driver whose `goOnline` failed — no
  /// signal, location denied — saw "You're online" and sat waiting for offers
  /// that were never coming. The truth lives in `deliveryProvider.isOnline`;
  /// this only reflects it.
  void setDashing(bool isDashing) {
    if (state.isDashing == isDashing) return;
    state = state.copyWith(isDashing: isDashing);
  }

  void selectZone(String zone) {
    state = state.copyWith(selectedZone: zone);
  }

  void updateEarnings({required int cents, required int trips}) {
    state = state.copyWith(
      todayEarningsCents: cents,
      todayTrips: trips,
    );
  }

  /// Fetch today's earnings from the backend and update the home screen totals.
  Future<void> refreshEarnings() async {
    String? driverId;
    try {
      final box = Hive.box('settings');
      driverId = box.get('user_id') as String?;
    } catch (_) {}
    if (driverId == null) return;

    try {
      final response = await _apiClient.getDriverEarnings(driverId);
      final data = response.data;
      state = state.copyWith(
        todayEarningsCents: data['today_earnings_cents'] ?? 0,
        todayTrips: data['today_deliveries'] ?? 0,
      );
    } catch (e) {
      debugPrint('HomeNotifier: refreshEarnings failed: $e');
    }
  }
}

/// Global home provider.
final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>((ref) {
  return HomeNotifier(ref.read(apiClientProvider));
});
