// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$exchangeRatesHash() => r'd5d4ad0d65705dd5ae0a69fc29f01cbaf0f362b4';

/// Live exchange rates, used to show what a USD total costs in ZIG or ZAR.
///
/// Copied from [exchangeRates].
@ProviderFor(exchangeRates)
final exchangeRatesProvider =
    AutoDisposeFutureProvider<Map<String, double>>.internal(
  exchangeRates,
  name: r'exchangeRatesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$exchangeRatesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef ExchangeRatesRef = AutoDisposeFutureProviderRef<Map<String, double>>;
String _$paymentHash() => r'52f5d9796aa9c70c68f0c3bb043daada5f83d5c8';

/// See also [Payment].
@ProviderFor(Payment)
final paymentProvider = NotifierProvider<Payment, PaymentSession>.internal(
  Payment.new,
  name: r'paymentProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$paymentHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Payment = Notifier<PaymentSession>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
