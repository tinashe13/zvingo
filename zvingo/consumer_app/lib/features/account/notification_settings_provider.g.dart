// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_settings_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$pushConfiguredHash() => r'fbf22d7592008b3c38b7d43d4bd68662f6263bfa';

/// Whether push delivery is configured on the server at all.
///
/// `GET /notification/push/status` exists so a client can say "push is off on
/// the server" rather than leaving someone waiting for notifications that will
/// never arrive. Note finding X6: no Flutter app currently registers an FCM
/// token, so push is dead end-to-end whatever this returns.
///
/// Copied from [pushConfigured].
@ProviderFor(pushConfigured)
final pushConfiguredProvider = AutoDisposeFutureProvider<bool>.internal(
  pushConfigured,
  name: r'pushConfiguredProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$pushConfiguredHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef PushConfiguredRef = AutoDisposeFutureProviderRef<bool>;
String _$notificationSettingsHash() =>
    r'bf8509d6849e62d0d28316db2664f83f6263d76b';

/// Reads and writes `/notification/preferences`.
///
/// Copied from [NotificationSettings].
@ProviderFor(NotificationSettings)
final notificationSettingsProvider = AutoDisposeAsyncNotifierProvider<
    NotificationSettings, NotificationPreferences>.internal(
  NotificationSettings.new,
  name: r'notificationSettingsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$notificationSettingsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$NotificationSettings
    = AutoDisposeAsyncNotifier<NotificationPreferences>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
