import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/core/api_client.dart';

part 'notification_settings_provider.g.dart';

/// The caller's notification settings, mirroring
/// `NotificationPreferenceUpdate` in `backend/app/notification/router.py`.
///
/// `driver_offers` exists in the contract but is a driver-app concern, so the
/// consumer settings screen does not show it — it is carried through unchanged
/// so a partial update never clears it.
class NotificationPreferences {
  const NotificationPreferences({
    this.pushEnabled = true,
    this.smsEnabled = true,
    this.orderUpdates = true,
    this.chatMessages = true,
    this.promotions = true,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.timezone,
  });

  final bool pushEnabled;
  final bool smsEnabled;
  final bool orderUpdates;
  final bool chatMessages;
  final bool promotions;

  /// `HH:MM`, or null when quiet hours are off.
  final String? quietHoursStart;
  final String? quietHoursEnd;
  final String? timezone;

  bool get quietHoursOn => quietHoursStart != null && quietHoursEnd != null;

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    String? time(Object? value) {
      final text = value?.toString();
      return (text == null || text.isEmpty) ? null : text;
    }

    return NotificationPreferences(
      pushEnabled: json['push_enabled'] ?? true,
      smsEnabled: json['sms_enabled'] ?? true,
      orderUpdates: json['order_updates'] ?? true,
      chatMessages: json['chat_messages'] ?? true,
      promotions: json['promotions'] ?? true,
      quietHoursStart: time(json['quiet_hours_start']),
      quietHoursEnd: time(json['quiet_hours_end']),
      timezone: time(json['timezone']),
    );
  }

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? smsEnabled,
    bool? orderUpdates,
    bool? chatMessages,
    bool? promotions,
    String? quietHoursStart,
    String? quietHoursEnd,
    bool clearQuietHours = false,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      orderUpdates: orderUpdates ?? this.orderUpdates,
      chatMessages: chatMessages ?? this.chatMessages,
      promotions: promotions ?? this.promotions,
      quietHoursStart:
          clearQuietHours ? null : (quietHoursStart ?? this.quietHoursStart),
      quietHoursEnd:
          clearQuietHours ? null : (quietHoursEnd ?? this.quietHoursEnd),
      timezone: timezone,
    );
  }
}

/// Whether push delivery is configured on the server at all.
///
/// `GET /notification/push/status` exists so a client can say "push is off on
/// the server" rather than leaving someone waiting for notifications that will
/// never arrive. Note finding X6: no Flutter app currently registers an FCM
/// token, so push is dead end-to-end whatever this returns.
@riverpod
Future<bool> pushConfigured(Ref ref) async {
  try {
    final response =
        await ref.watch(apiClientProvider).get<dynamic>('/notification/push/status');
    final data = response.data;
    if (data is Map) {
      // The endpoint reports a small status map; treat any explicit
      // "configured"/"enabled" false as off, and anything unreadable as on
      // rather than scaring the user with a warning we are not sure about.
      final value = data['configured'] ?? data['enabled'] ?? data['ready'];
      if (value is bool) return value;
    }
    return true;
  } catch (_) {
    return true;
  }
}

/// Reads and writes `/notification/preferences`.
@riverpod
class NotificationSettings extends _$NotificationSettings {
  @override
  Future<NotificationPreferences> build() async {
    final response = await ref
        .watch(apiClientProvider)
        .get<dynamic>('/notification/preferences');
    return NotificationPreferences.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  /// Applies a partial change optimistically, then persists it.
  ///
  /// `PUT /notification/preferences` takes only the fields that are sent, so a
  /// single toggle is a single-field body. On failure the previous value is put
  /// back — a switch that stays flipped after a failed save is a lie about what
  /// the server will actually do.
  Future<bool> apply(
    NotificationPreferences Function(NotificationPreferences) change,
    Map<String, dynamic> payload,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return false;

    state = AsyncValue.data(change(current));
    try {
      final response = await ref
          .read(apiClientProvider)
          .put<dynamic>('/notification/preferences', data: payload);
      state = AsyncValue.data(
        NotificationPreferences.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        ),
      );
      return true;
    } catch (_) {
      state = AsyncValue.data(current);
      return false;
    }
  }
}
