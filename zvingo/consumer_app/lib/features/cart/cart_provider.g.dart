// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cart_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$cartSubtotalHash() => r'56ef6b37c26471a0b28dc95b9c9108f660f8f634';

/// Cart subtotal in exact minor units.
///
/// Copied from [cartSubtotal].
@ProviderFor(cartSubtotal)
final cartSubtotalProvider = AutoDisposeProvider<Money>.internal(
  cartSubtotal,
  name: r'cartSubtotalProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$cartSubtotalHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef CartSubtotalRef = AutoDisposeProviderRef<Money>;
String _$cartUnitCountHash() => r'b856ae4f01b5294e423ada284c5856f06562a0bb';

/// Total units in the cart (a 3× burger counts as 3).
///
/// Copied from [cartUnitCount].
@ProviderFor(cartUnitCount)
final cartUnitCountProvider = AutoDisposeProvider<int>.internal(
  cartUnitCount,
  name: r'cartUnitCountProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$cartUnitCountHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef CartUnitCountRef = AutoDisposeProviderRef<int>;
String _$cartOwnerHash() => r'f4e3196f421e5f7e0980e846ef057c8498246996';

/// The restaurant the cart belongs to.
///
/// Copied from [cartOwner].
@ProviderFor(cartOwner)
final cartOwnerProvider = AutoDisposeProvider<CartOwner>.internal(
  cartOwner,
  name: r'cartOwnerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$cartOwnerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef CartOwnerRef = AutoDisposeProviderRef<CartOwner>;
String _$cartTotalHash() => r'cb841b6482a43041bea6f2f90b50473d036aea36';

/// Presentation-only major-unit total. Kept for existing call sites; prefer
/// [cartSubtotalProvider].
///
/// Copied from [cartTotal].
@ProviderFor(cartTotal)
final cartTotalProvider = AutoDisposeProvider<double>.internal(
  cartTotal,
  name: r'cartTotalProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$cartTotalHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef CartTotalRef = AutoDisposeProviderRef<double>;
String _$cartHash() => r'a83a9619a21d6b37544bf04c738c4227d3da59bf';

/// See also [Cart].
@ProviderFor(Cart)
final cartProvider = NotifierProvider<Cart, List<CartItem>>.internal(
  Cart.new,
  name: r'cartProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$cartHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Cart = Notifier<List<CartItem>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
