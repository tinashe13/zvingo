// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_interceptor.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$authSessionHash() => r'b07833e2a448ba4dce582c7d67262480df93e572';

/// Installs [ZvSessionInterceptor] on the app's shared Dio, exactly once.
///
/// It is inserted at index 0 so it sees a 401 *before*
/// `core/api_client.dart`'s handler deletes the access token — a refresh that
/// succeeds leaves the session intact instead of bouncing the user to sign-in
/// in the middle of an order.
///
/// Read from [Auth], from [userProfile] and from `locationStartup` (which the
/// app shell watches on mount), so it is live before the first tab fetches
/// anything.
///
/// Copied from [authSession].
@ProviderFor(authSession)
final authSessionProvider = Provider<ZvSessionInterceptor>.internal(
  authSession,
  name: r'authSessionProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$authSessionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AuthSessionRef = ProviderRef<ZvSessionInterceptor>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
