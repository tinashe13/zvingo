// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_preferences_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$paymentPreferencesStoreHash() =>
    r'33e5455e32c19323839d840a696da885904c0936';

/// Stores the payment preference **on this device**.
///
/// There is no server field for it: `User` in `backend/app/auth/models.py` has
/// no `preferred_payment_method` or `billing_phone`, and `PATCH /auth/me`
/// accepts only `full_name` and `email`. So this is a local convenience, and
/// the screen says so rather than implying it follows the account around.
/// Making it sync is a small backend change — it is written up in the C4
/// report.
///
/// Nothing sensitive is kept here: a mobile-money wallet choice and a phone
/// number the user already gives the driver. No PIN, no card, no token.
///
/// Copied from [PaymentPreferencesStore].
@ProviderFor(PaymentPreferencesStore)
final paymentPreferencesStoreProvider =
    NotifierProvider<PaymentPreferencesStore, PaymentPreferences>.internal(
  PaymentPreferencesStore.new,
  name: r'paymentPreferencesStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$paymentPreferencesStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$PaymentPreferencesStore = Notifier<PaymentPreferences>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
