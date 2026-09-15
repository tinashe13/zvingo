import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/widgets/floating_app_dock.dart';
import 'package:consumer_app/common/widgets/zv_sticky_bars.dart';
import 'package:consumer_app/core/app_motion.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/shell_overlays.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/order/active_order_provider.dart';
import 'package:consumer_app/features/order/order_status_bottom_sheet.dart';

/// The five-destination navigation shell — the spine of the consumer app
/// (§5.4).
///
/// Responsibilities:
/// * renders the always-labelled bottom dock and preserves each tab's own
///   navigation stack (the `StatefulShellRoute` in `router.dart` owns that
///   state; this widget only forwards the index);
/// * hosts the two persistent context bars — the sticky **active-cart bar**
///   at the bottom and the sticky **in-progress-order banner** with live ETA
///   at the top. Both are opt-in: feature code pushes state into
///   `shellCartBarProvider` / `shellOrderBannerProvider` and the bar animates
///   in on every tab.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({
    super.key,
    required this.currentIndex,
    required this.child,
    required this.onTabChanged,
  });

  /// Index of the active branch.
  final int currentIndex;

  /// The active branch's navigator.
  final Widget child;

  /// Called when a dock destination is tapped.
  final ValueChanged<int> onTabChanged;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  Widget build(BuildContext context) {
    // Kick off background location init as soon as the authenticated shell
    // mounts, so the first home render already has a delivery address.
    ref.watch(locationStartupProvider);

    final activeOrderId = ref.watch(activeOrderProvider);
    final cartBar = ref.watch(shellCartBarProvider);
    final orderBanner = ref.watch(shellOrderBannerProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Space the content must leave clear for the dock and any sticky bars.
    final dockZone = FloatingAppDock.height + AppSpacing.md + bottomInset;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // ── Tab content ────────────────────────────────────────────────
          Positioned.fill(child: widget.child),

          // ── Sticky in-progress-order banner (top) ──────────────────────
          Positioned(
            top: MediaQuery.paddingOf(context).top,
            left: 0,
            right: 0,
            child: orderBanner == null
                ? const SizedBox.shrink()
                : ZvOrderBanner(
                    statusLabel: orderBanner.statusLabel,
                    etaMinutes: orderBanner.etaMinutes,
                    etaText: orderBanner.etaText,
                    progress: orderBanner.progress,
                    onTap: () => context.push('/order/${orderBanner.orderId}'),
                  ),
          ),

          // ── Legacy order-status card, owned by the order feature ───────
          Positioned(
            left: 0,
            right: 0,
            bottom: dockZone + AppSpacing.xl,
            child: AnimatedSwitcher(
              duration: context.motion(AppMotion.slow),
              switchInCurve: context.motionCurve(AppMotion.enter),
              switchOutCurve: context.motionCurve(AppMotion.exit),
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: activeOrderId != null
                  ? OrderStatusBottomSheet(
                      key: const ValueKey('orderSheet'),
                      orderId: activeOrderId,
                    )
                  : const SizedBox.shrink(key: ValueKey('noOrderSheet')),
            ),
          ),

          // ── Sticky active-cart bar + dock (bottom) ─────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cartBar != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: ZvCartBar(
                      itemCount: cartBar.itemCount,
                      total: cartBar.total,
                      currency: cartBar.currency,
                      restaurantName: cartBar.restaurantName,
                      label: cartBar.label,
                      onTap: () => context.push(cartBar.route),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                    AppSpacing.xs + bottomInset,
                  ),
                  child: FloatingAppDock(
                    currentIndex: widget.currentIndex,
                    onSelected: widget.onTabChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
