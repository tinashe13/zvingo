// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_deletion_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$inFlightOrderCountHash() =>
    r'bfdc75a17a194dec85f2ccc07eed8f0188d180c8';

/// Orders that would be abandoned by deleting the account right now.
///
/// Deleting mid-delivery would strand a driver and an unrefunded payment, so
/// the UI blocks on this instead of finding out server-side.
///
/// Copied from [inFlightOrderCount].
@ProviderFor(inFlightOrderCount)
final inFlightOrderCountProvider = AutoDisposeFutureProvider<int>.internal(
  inFlightOrderCount,
  name: r'inFlightOrderCountProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$inFlightOrderCountHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef InFlightOrderCountRef = AutoDisposeFutureProviderRef<int>;
String _$accountDeletionHash() => r'4da229638bf95f5da7a463201b15c1a241153def';

/// Sends the deletion request.
///
/// **Contract this expects** (not yet implemented server-side):
/// `DELETE /auth/me` with `{"reason": "<optional free text>"}`, authenticated
/// as the account being deleted, answering `204` on success.
///
/// Copied from [AccountDeletion].
@ProviderFor(AccountDeletion)
final accountDeletionProvider =
    AutoDisposeAsyncNotifierProvider<AccountDeletion, void>.internal(
  AccountDeletion.new,
  name: r'accountDeletionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$accountDeletionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$AccountDeletion = AutoDisposeAsyncNotifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
