// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$userProfileHash() => r'fddead59e002e862323ed297cf148e10ffdc283c';

/// The signed-in user's profile.
///
/// Errors propagate: a screen showing a fabricated "User" profile because the
/// request failed is worse than one showing [ZvErrorState] with a Retry.
///
/// Copied from [userProfile].
@ProviderFor(userProfile)
final userProfileProvider = AutoDisposeFutureProvider<ZvUserProfile>.internal(
  userProfile,
  name: r'userProfileProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$userProfileHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef UserProfileRef = AutoDisposeFutureProviderRef<ZvUserProfile>;
String _$authHash() => r'6611c27520535f3e1db08efd7d2b70e864967616';

/// Every authentication action in the consumer app.
///
/// The notifier's `AsyncValue` state drives the submit button's spinner;
/// failures are surfaced as an [AuthFailure] the caller renders inline, never
/// as a raw exception or an HTTP status (§5.5).
///
/// Copied from [Auth].
@ProviderFor(Auth)
final authProvider = AutoDisposeAsyncNotifierProvider<Auth, void>.internal(
  Auth.new,
  name: r'authProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$authHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Auth = AutoDisposeAsyncNotifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
