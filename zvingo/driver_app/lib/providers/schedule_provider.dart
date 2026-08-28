import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';

/// Schedule screen state.
class ScheduleState {
  final Map<int, Set<int>> selected;
  final bool loading;

  const ScheduleState({
    this.selected = const {},
    this.loading = false,
  });

  ScheduleState copyWith({
    Map<int, Set<int>>? selected,
    bool? loading,
  }) {
    return ScheduleState(
      selected: selected ?? this.selected,
      loading: loading ?? this.loading,
    );
  }
}

/// Schedule provider — persists the driver's weekly day/slot availability.
class ScheduleNotifier extends StateNotifier<ScheduleState> {
  final ApiClient _apiClient;

  ScheduleNotifier(this._apiClient) : super(const ScheduleState());

  /// Fetch the driver's saved schedule.
  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final response = await _apiClient.get('/driver/schedule');
      final data = response.data;
      final days = (data is Map && data['days'] is List)
          ? data['days'] as List
          : <dynamic>[];

      final selected = <int, Set<int>>{};
      for (final d in days) {
        if (d is! Map) continue;
        final day = d['day'];
        final slots = d['slots'];
        if (day is int && slots is List) {
          selected[day] = slots.whereType<int>().toSet();
        }
      }

      state = ScheduleState(selected: selected, loading: false);
    } catch (e) {
      debugPrint('ScheduleNotifier: load failed: $e');
      state = state.copyWith(loading: false);
    }
  }

  /// Toggle a single slot and persist the full schedule.
  Future<void> toggle(int day, int slot) async {
    // Copy the current map so the state object is treated as new.
    final next = <int, Set<int>>{};
    state.selected.forEach((k, v) => next[k] = Set<int>.from(v));

    final slots = next.putIfAbsent(day, () => <int>{});
    if (slots.contains(slot)) {
      slots.remove(slot);
    } else {
      slots.add(slot);
    }

    state = state.copyWith(selected: next);

    await _save(next);
  }

  /// Persist the given selection as the `/driver/schedule` payload.
  Future<void> _save(Map<int, Set<int>> selected) async {
    final days = selected.entries.map((entry) {
      final slots = entry.value.toList()..sort();
      return <String, dynamic>{'day': entry.key, 'slots': slots};
    }).toList();

    try {
      await _apiClient.put('/driver/schedule', data: {'days': days});
    } catch (e) {
      debugPrint('ScheduleNotifier: save failed: $e');
    }
  }
}

/// Global schedule provider.
final scheduleProvider =
    StateNotifierProvider<ScheduleNotifier, ScheduleState>((ref) {
  return ScheduleNotifier(ref.read(apiClientProvider));
});
