import 'package:consumer_app/common/widgets/floating_app_dock.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/order/active_order_provider.dart';
import 'package:consumer_app/features/order/order_status_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Primary five-destination navigation shell.
class MainShell extends ConsumerStatefulWidget {
  final int currentIndex;
  final Widget child;
  final ValueChanged<int> onTabChanged;

  const MainShell({
    super.key,
    required this.currentIndex,
    required this.child,
    required this.onTabChanged,
  });

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  Widget build(BuildContext context) {
    // Kick off background location init as soon as the authenticated shell mounts.
    ref.watch(locationStartupProvider);
    final activeOrderId = ref.watch(activeOrderProvider);

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          widget.child,
          // Order Status Overlay with Slide Animation
          Positioned(
            left: 0,
            right: 0,
            bottom: 98 + MediaQuery.paddingOf(context).bottom,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
              child: activeOrderId != null
                  ? OrderStatusBottomSheet(
                      key: const ValueKey('orderSheet'),
                      orderId: activeOrderId,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 8 + MediaQuery.paddingOf(context).bottom,
            child: FloatingAppDock(
              currentIndex: widget.currentIndex,
              onSelected: widget.onTabChanged,
            ),
          ),
        ],
      ),
    );
  }
}
