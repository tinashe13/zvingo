import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import 'auth_provider.dart';

/// One of the three shifts the schedule grid is built from.
///
/// The **backend owns these windows** (`SLOT_WINDOWS` in
/// `backend/app/driver/router.py`) and returns them on every `GET`/`PUT` as
/// `slot_windows`, so the app never hard-codes shift times that operations can
/// change. [ShiftSlot.fallbacks] exists only so the grid still renders before
/// the first response lands.
class ShiftSlot {
  final int id;
  final String label;

  /// `HH:MM` local wall-clock, in [ScheduleState.timezone].
  final String start;
  final String end;

  const ShiftSlot({
    required this.id,
    required this.label,
    required this.start,
    required this.end,
  });

  /// What the server sends today. Used only until the first load completes.
  static const List<ShiftSlot> fallbacks = [
    ShiftSlot(id: 0, label: 'Morning', start: '06:00', end: '12:00'),
    ShiftSlot(id: 1, label: 'Afternoon', start: '12:00', end: '17:00'),
    ShiftSlot(id: 2, label: 'Evening', start: '17:00', end: '23:00'),
  ];

  /// `6am – 12pm`, which reads faster on a phone held at arm's length than
  /// `06:00–12:00`.
  String get window => '${_friendly(start)} – ${_friendly(end)}';

  static String _friendly(String hhmm) {
    final parts = hhmm.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final suffix = hour >= 12 ? 'pm' : 'am';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return minute == 0
        ? '$display$suffix'
        : '$display:${minute.toString().padLeft(2, '0')}$suffix';
  }
}

/// Why a schedule read or write failed.
enum ScheduleFailure { noSession, network, rejected, unknown }

/// Schedule screen state.
class ScheduleState {
  /// `{weekday index 0=Mon … 6=Sun : set of slot ids}`.
  final Map<int, Set<int>> selected;

  /// Shift definitions as the server described them.
  final List<ShiftSlot> slots;

  /// Short weekday labels, server-supplied so they stay in step with `day`
  /// indices (0 = Mon).
  final List<String> dayLabels;

  /// IANA zone the stored times are wall-clock in. Zvingo operates in one
  /// zone; the server echoes it so the app never assumes.
  final String timezone;

  /// First load in flight.
  final bool loading;

  /// A write is in flight. The grid stays interactive — the optimistic state
  /// is already applied — but the screen says it is saving.
  final bool saving;

  /// True once every queued change has been acknowledged by the server.
  final bool savedRecently;

  final ScheduleFailure? failure;

  const ScheduleState({
    this.selected = const {},
    this.slots = ShiftSlot.fallbacks,
    this.dayLabels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    this.timezone = 'Africa/Harare',
    this.loading = false,
    this.saving = false,
    this.savedRecently = false,
    this.failure,
  });

  bool isSelected(int day, int slot) => selected[day]?.contains(slot) ?? false;

  /// How many shifts the driver has committed to across the week.
  int get totalShifts =>
      selected.values.fold(0, (running, slots) => running + slots.length);

  int get daysWithShifts =>
      selected.values.where((slots) => slots.isNotEmpty).length;

  bool get isEmpty => totalShifts == 0;

  /// Total hours a week, derived from the server's own slot windows rather
  /// than from assumed shift lengths.
  double get weeklyHours {
    var minutes = 0;
    for (final entry in selected.entries) {
      for (final slotId in entry.value) {
        final slot = slotFor(slotId);
        if (slot == null) continue;
        minutes += _minutesOf(slot.end) - _minutesOf(slot.start);
      }
    }
    return minutes / 60;
  }

  ShiftSlot? slotFor(int id) {
    for (final slot in slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }

  static int _minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    return (int.tryParse(parts.first) ?? 0) * 60 +
        (parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0);
  }

  /// Zvingo's operating zone is UTC+2 all year (Africa/Harare has no DST).
  static const Duration harareOffset = Duration(hours: 2);

  /// True when the phone is set to a different zone from the one the schedule
  /// is stored in — a driver travelling, or a phone with the wrong region.
  /// The screen then says which clock the times refer to instead of letting
  /// them silently mean something else.
  bool get deviceClockDiffers =>
      DateTime.now().timeZoneOffset != harareOffset;

  /// `+2` style label for the device's own offset, for that explanation.
  String get deviceOffsetLabel {
    final offset = DateTime.now().timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  ScheduleState copyWith({
    Map<int, Set<int>>? selected,
    List<ShiftSlot>? slots,
    List<String>? dayLabels,
    String? timezone,
    bool? loading,
    bool? saving,
    bool? savedRecently,
    ScheduleFailure? failure,
    bool clearFailure = false,
  }) {
    return ScheduleState(
      selected: selected ?? this.selected,
      slots: slots ?? this.slots,
      dayLabels: dayLabels ?? this.dayLabels,
      timezone: timezone ?? this.timezone,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      savedRecently: savedRecently ?? this.savedRecently,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// Schedule provider — reads and writes the driver's recurring weekly
/// availability for real.
///
/// The previous implementation toggled a map in memory and fired a `PUT` it
/// never checked, so a failed write looked identical to a successful one and
/// the grid silently reset on the next load. This one:
///
/// * applies the toggle **optimistically** so the button responds instantly
///   even on a slow link;
/// * **coalesces** rapid toggles into one `PUT` — a driver filling in a week
///   taps 10 times in 3 seconds, and 10 racing writes would let the last one
///   to land win, which is not necessarily the last one the driver made;
/// * keeps a **last-known-good snapshot** and rolls back to it when the write
///   fails, so the grid never shows a shift the server does not have;
/// * reports the failure with a **retry** instead of swallowing it.
///
/// Endpoints (`backend/app/driver/router.py`): `GET /driver/schedule` and
/// `PUT /driver/schedule`. Both act on `current_user`, so they are inherently
/// owner-scoped — there is no path parameter to tamper with.
class ScheduleNotifier extends StateNotifier<ScheduleState> {
  final ApiClient _apiClient;
  final AuthSession _session;

  /// The last selection the server confirmed. The rollback target.
  Map<int, Set<int>> _lastSaved = const {};

  Timer? _debounce;
  Future<void>? _inFlight;
  bool _dirty = false;

  /// Coalescing window. Long enough to absorb a burst of taps, short enough
  /// that a driver who backgrounds the app immediately still gets the write.
  static const Duration _coalesceWindow = Duration(milliseconds: 500);

  ScheduleNotifier(this._apiClient, this._session) : super(const ScheduleState());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Fetch the saved schedule and the server's slot definitions.
  Future<void> load() async {
    state = state.copyWith(loading: true, clearFailure: true);
    try {
      final response =
          await _session.send(() => _apiClient.get('/driver/schedule'));
      final data = response.data;
      if (data is! Map) {
        state = state.copyWith(loading: false, failure: ScheduleFailure.unknown);
        return;
      }
      final parsed = _parse(Map<String, dynamic>.from(data));
      _lastSaved = _clone(parsed.selected);
      state = parsed.copyWith(loading: false, clearFailure: true);
    } on DioException catch (e) {
      debugPrint('ScheduleNotifier: load failed: ${e.message}');
      state = state.copyWith(loading: false, failure: _classify(e));
    } catch (e) {
      debugPrint('ScheduleNotifier: load failed: $e');
      state = state.copyWith(loading: false, failure: ScheduleFailure.unknown);
    }
  }

  /// Toggle one shift. Applies immediately, persists shortly after.
  void toggle(int day, int slot) {
    final next = _clone(state.selected);
    final slots = next.putIfAbsent(day, () => <int>{});
    if (!slots.remove(slot)) slots.add(slot);
    if (slots.isEmpty) next.remove(day);

    state = state.copyWith(
      selected: next,
      saving: true,
      savedRecently: false,
      clearFailure: true,
    );
    _queueSave();
  }

  /// Clear the whole week in one move (behind a confirm sheet in the UI).
  void clearWeek() {
    state = state.copyWith(
      selected: const {},
      saving: true,
      savedRecently: false,
      clearFailure: true,
    );
    _queueSave();
  }

  /// Select every shift on the weekdays a driver most often works, as a
  /// starting point they can then trim.
  void applyPreset(Map<int, Set<int>> preset) {
    state = state.copyWith(
      selected: _clone(preset),
      saving: true,
      savedRecently: false,
      clearFailure: true,
    );
    _queueSave();
  }

  /// Retry after a failed write, from the state currently on screen.
  Future<void> retrySave() async {
    state = state.copyWith(saving: true, clearFailure: true);
    _dirty = true;
    await _flush();
  }

  /// Throw away an unsaved change and go back to what the server has.
  void discardChanges() {
    _debounce?.cancel();
    _dirty = false;
    state = state.copyWith(
      selected: _clone(_lastSaved),
      saving: false,
      clearFailure: true,
    );
  }

  void _queueSave() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(_coalesceWindow, () => unawaited(_flush()));
  }

  /// Serialises writes: one `PUT` at a time, and if more edits arrived while
  /// one was in flight, another `PUT` follows with the latest state.
  Future<void> _flush() async {
    if (_inFlight != null) return _inFlight;
    if (!_dirty) return;

    final completer = Completer<void>();
    _inFlight = completer.future;
    try {
      while (_dirty) {
        _dirty = false;
        final attempt = _clone(state.selected);
        final ok = await _put(attempt);
        if (!ok) break;
        _lastSaved = attempt;
      }
    } finally {
      _inFlight = null;
      completer.complete();
    }
  }

  Future<bool> _put(Map<int, Set<int>> selection) async {
    final days = selection.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => <String, dynamic>{
              'day': entry.key,
              'slots': entry.value.toList()..sort(),
            })
        .toList()
      ..sort((a, b) => (a['day'] as int).compareTo(b['day'] as int));

    try {
      final response = await _session.send(
        () => _apiClient.put('/driver/schedule', data: {'days': days}),
      );
      // The server echoes the stored schedule back. Adopting the echo rather
      // than assuming success is what makes this real persistence: if the
      // server normalised or dropped anything, the grid shows what was
      // actually stored.
      final data = response.data;
      if (data is Map) {
        final confirmed = _parse(Map<String, dynamic>.from(data));
        state = confirmed.copyWith(
          saving: _dirty,
          savedRecently: !_dirty,
          clearFailure: true,
        );
        return true;
      }
      state = state.copyWith(saving: _dirty, savedRecently: !_dirty);
      return true;
    } on DioException catch (e) {
      debugPrint('ScheduleNotifier: save failed: ${e.message}');
      _rollback(_classify(e));
      return false;
    } catch (e) {
      debugPrint('ScheduleNotifier: save failed: $e');
      _rollback(ScheduleFailure.unknown);
      return false;
    }
  }

  /// Put the grid back to the last thing the server confirmed, so what the
  /// driver sees is always what Zvingo will dispatch against.
  void _rollback(ScheduleFailure failure) {
    _dirty = false;
    state = state.copyWith(
      selected: _clone(_lastSaved),
      saving: false,
      savedRecently: false,
      failure: failure,
    );
  }

  ScheduleState _parse(Map<String, dynamic> data) {
    final selected = <int, Set<int>>{};
    for (final entry in (data['days'] as List? ?? const [])) {
      if (entry is! Map) continue;
      final day = entry['day'];
      if (day is! int) continue;
      final slots = <int>{};
      for (final slot in (entry['slots'] as List? ?? const [])) {
        if (slot is int) slots.add(slot);
      }
      // A client that sent explicit `windows` instead of `slots` still gets
      // its slot ids back, because the server reconciles the two.
      for (final window in (entry['windows'] as List? ?? const [])) {
        if (window is Map && window['slot'] is int) {
          slots.add(window['slot'] as int);
        }
      }
      if (slots.isNotEmpty) selected[day] = slots;
    }

    final slots = <ShiftSlot>[];
    final rawWindows = data['slot_windows'];
    if (rawWindows is Map) {
      rawWindows.forEach((key, value) {
        final id = int.tryParse(key.toString());
        if (id == null || value is! Map) return;
        slots.add(ShiftSlot(
          id: id,
          label: (value['label'] as String?) ?? 'Shift ${id + 1}',
          start: (value['start'] as String?) ?? '00:00',
          end: (value['end'] as String?) ?? '00:00',
        ));
      });
      slots.sort((a, b) => a.id.compareTo(b.id));
    }

    final labels = (data['day_labels'] as List? ?? const [])
        .whereType<String>()
        .toList();

    return state.copyWith(
      selected: selected,
      slots: slots.isEmpty ? ShiftSlot.fallbacks : slots,
      dayLabels: labels.length == 7 ? labels : null,
      timezone: (data['timezone'] as String?) ?? state.timezone,
    );
  }

  static Map<int, Set<int>> _clone(Map<int, Set<int>> source) {
    final copy = <int, Set<int>>{};
    source.forEach((day, slots) => copy[day] = Set<int>.from(slots));
    return copy;
  }

  ScheduleFailure _classify(DioException e) {
    final status = e.response?.statusCode;
    if (status == 400 || status == 422) return ScheduleFailure.rejected;
    if (status == 401 || status == 403) return ScheduleFailure.noSession;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return ScheduleFailure.network;
      default:
        return ScheduleFailure.unknown;
    }
  }
}

/// Global schedule provider.
final scheduleProvider =
    StateNotifierProvider<ScheduleNotifier, ScheduleState>((ref) {
  return ScheduleNotifier(
    ref.read(apiClientProvider),
    ref.read(authSessionProvider),
  );
});
