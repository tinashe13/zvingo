/// Which order the app is currently "following".
///
/// This is the id behind the shell's sticky in-progress-order banner (§5.4:
/// "an in-progress order shows a sticky top banner with live ETA that taps
/// into tracking"). Checkout sets it the moment an order is placed; on a cold
/// start it derives itself from the consumer's order list, so reopening the
/// app mid-delivery still shows the banner.
///
/// It stays a `StateProvider<String?>` deliberately: `features/shell` and
/// `features/checkout` both already read and write it in that shape, and those
/// files belong to other agents.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/features/order/order_providers.dart';

/// The order the shell banner follows, or null when nothing is in flight.
///
/// The initial value is the newest order that is neither delivered nor
/// cancelled. Writing to it (`ref.read(activeOrderProvider.notifier).state =
/// id`) pins a specific order — checkout does exactly that so the banner
/// appears before the order list has refreshed.
final activeOrderProvider = StateProvider<String?>((ref) {
  final orders = ref.watch(consumerOrdersProvider).valueOrNull;
  if (orders == null) return null;
  for (final order in orders) {
    if (order.isActive) return order.id;
  }
  return null;
});
