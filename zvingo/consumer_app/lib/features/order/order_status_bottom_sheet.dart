/// The shell's active-order hook.
///
/// ## Why this file renders nothing
///
/// There used to be **two** competing active-order affordances: this floating
/// card above the dock, and the design system's sticky top banner
/// (`shellOrderBannerProvider`, added by F1). Both could be on screen at once,
/// both polled `/orders/{id}` on their own three-second timer, and they could
/// disagree about the order's state.
///
/// The banner won — it is the §5.4 contract ("an in-progress order shows a
/// sticky top banner with live ETA that taps into tracking"), it does not
/// cover content, it is consistent with the cart bar, and it is the same
/// component on every tab. So [OrderStatusBottomSheet] is now a **headless
/// adapter**: `main_shell.dart` still mounts it for the active order id, and
/// all it does is feed the shell banner from the one shared [OrderTracker] —
/// the same live data the tracking screen uses, so the two can never disagree.
///
/// `main_shell.dart` and `checkout_screen.dart` are owned by other agents, so
/// their call sites are unchanged. Once the shell can be edited, the
/// `AnimatedSwitcher` block in `main_shell.dart` that mounts this widget can be
/// deleted outright and the shell can host the banner alone — see the C3
/// report's "requests for other teams".
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/core/shell_overlays.dart';
import 'package:consumer_app/features/order/active_order_provider.dart';
import 'package:consumer_app/features/order/order_providers.dart';
import 'package:consumer_app/features/order/order_timeline.dart';
import 'package:consumer_app/features/order/order_tracking_transport.dart';

/// Drives the shell's sticky order banner for [orderId]. Renders nothing.
class OrderStatusBottomSheet extends ConsumerStatefulWidget {
  const OrderStatusBottomSheet({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderStatusBottomSheet> createState() =>
      _OrderStatusBottomSheetState();
}

class _OrderStatusBottomSheetState
    extends ConsumerState<OrderStatusBottomSheet> {
  /// How long a finished order keeps its banner, so "Delivered" is actually
  /// seen before the banner disappears.
  static const Duration _finishedLinger = Duration(seconds: 8);

  Timer? _dismissTimer;
  OrderTrackingState? _applied;
  late final ShellOrderBannerController _banner;

  @override
  void initState() {
    super.initState();
    // Captured now so `dispose` never has to touch `ref` or `context`.
    _banner = ref.read(shellOrderBannerProvider.notifier);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    // The banner belongs to this order; leaving it behind would strand a
    // stale ETA at the top of every tab. Deferred, because writing to a
    // provider while the tree is being torn down throws.
    final banner = _banner;
    scheduleMicrotask(() {
      try {
        banner.hide();
      } catch (_) {
        // The scope itself is gone — there is no banner left to hide.
      }
    });
    super.dispose();
  }

  void _publish(OrderTrackingState state) {
    if (!mounted) return;
    final order = state.order;
    if (order == null) return;

    final headline = orderHeadline(
      order.state,
      driverFirstName: order.driver?.firstName,
    );
    final eta = state.eta;

    ref.read(shellOrderBannerProvider.notifier).show(
          ZvOrderBannerData(
            orderId: order.id,
            statusLabel: headline.title,
            // A precise estimate animates as a number; a range or "Updating…"
            // goes through as text. The banner never shows a fabricated count.
            etaMinutes:
                eta.confidence == EtaConfidence.precise ? eta.minutes : null,
            etaText: eta.confidence == EtaConfidence.precise
                ? null
                : (eta.hasValue ? eta.label : null),
            progress: order.progress,
          ),
        );

    if (order.isTerminal) {
      _dismissTimer ??= Timer(_finishedLinger, () {
        if (!mounted) return;
        ref.read(shellOrderBannerProvider.notifier).hide();
        // Stop following this order; the provider re-derives the next active
        // one from the order list if there is one.
        ref.read(activeOrderProvider.notifier).state = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderTrackingProvider(widget.orderId)).valueOrNull;

    // Providers must not be written during a build.
    if (state != null && !identical(state, _applied)) {
      _applied = state;
      WidgetsBinding.instance.addPostFrameCallback((_) => _publish(state));
    }

    return const SizedBox.shrink();
  }
}
