/// Shell-level persistent context bars (§5.4: "an active cart shows a sticky
/// bottom bar on every browse screen; an in-progress order shows a sticky top
/// banner with live ETA that taps into tracking").
///
/// The shell renders the bars; **feature code supplies the data**. Any screen
/// or provider can push state in and the bar appears everywhere inside the
/// tab shell, animated in and out.
///
/// ```dart
/// // cart_provider.dart — keep the shell bar in sync with the cart
/// ref.listen(cartProvider, (_, cart) {
///   final bar = ref.read(shellCartBarProvider.notifier);
///   if (cart.isEmpty) {
///     bar.hide();
///   } else {
///     bar.show(ZvCartBarData(
///       itemCount: cart.itemCount,
///       total: cart.total,
///       currency: cart.currencySymbol,
///       restaurantName: cart.restaurantName,
///     ));
///   }
/// });
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Data backing the sticky active-cart bar.
@immutable
class ZvCartBarData {
  const ZvCartBarData({
    required this.itemCount,
    required this.total,
    required this.currency,
    this.restaurantName,
    this.route = '/cart',
    this.label = 'View cart',
  });

  /// Number of items in the cart.
  final int itemCount;

  /// Cart total in [currency].
  final double total;

  /// Currency symbol or code (USD / ZIG / ZAR all circulate — never omit it).
  final String currency;

  /// Restaurant the cart belongs to.
  final String? restaurantName;

  /// Route the bar opens.
  final String route;

  /// Call-to-action text.
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZvCartBarData &&
          other.itemCount == itemCount &&
          other.total == total &&
          other.currency == currency &&
          other.restaurantName == restaurantName &&
          other.route == route &&
          other.label == label;

  @override
  int get hashCode =>
      Object.hash(itemCount, total, currency, restaurantName, route, label);
}

/// Data backing the sticky in-progress-order banner.
@immutable
class ZvOrderBannerData {
  const ZvOrderBannerData({
    required this.orderId,
    required this.statusLabel,
    this.etaMinutes,
    this.etaText,
    this.progress,
  });

  /// Order the banner tracks. The banner routes to `/order/<orderId>`.
  final String orderId;

  /// Plain-language state, e.g. "Your order is on the way".
  final String statusLabel;

  /// Live ETA in minutes. Animates when it changes.
  final int? etaMinutes;

  /// Free-text ETA used when [etaMinutes] is null, e.g. "25–35 min".
  final String? etaText;

  /// Delivery progress 0..1. Null hides the progress line.
  final double? progress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZvOrderBannerData &&
          other.orderId == orderId &&
          other.statusLabel == statusLabel &&
          other.etaMinutes == etaMinutes &&
          other.etaText == etaText &&
          other.progress == progress;

  @override
  int get hashCode =>
      Object.hash(orderId, statusLabel, etaMinutes, etaText, progress);
}

/// Controls the sticky cart bar. Call `show` / `hide` from cart state.
class ShellCartBarController extends Notifier<ZvCartBarData?> {
  @override
  ZvCartBarData? build() => null;

  /// Shows (or updates) the cart bar.
  void show(ZvCartBarData data) => state = data;

  /// Hides the cart bar.
  void hide() => state = null;
}

/// Controls the sticky order banner. Call `show` / `hide` as the order moves.
class ShellOrderBannerController extends Notifier<ZvOrderBannerData?> {
  @override
  ZvOrderBannerData? build() => null;

  /// Shows (or updates) the order banner.
  void show(ZvOrderBannerData data) => state = data;

  /// Hides the order banner, e.g. once the order is delivered and dismissed.
  void hide() => state = null;
}

/// The sticky cart bar's state. Null hides it.
final shellCartBarProvider =
    NotifierProvider<ShellCartBarController, ZvCartBarData?>(
  ShellCartBarController.new,
);

/// The sticky order banner's state. Null hides it.
final shellOrderBannerProvider =
    NotifierProvider<ShellOrderBannerController, ZvOrderBannerData?>(
  ShellOrderBannerController.new,
);
