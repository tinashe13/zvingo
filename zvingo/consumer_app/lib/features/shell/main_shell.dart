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
      body: Stack(
        children: [
          widget.child,
          // Order Status Overlay with Slide Animation
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
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
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.currentIndex,
        onDestinationSelected: widget.onTabChanged,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag_rounded),
            label: 'Pickup',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_offer_outlined),
            selectedIcon: Icon(Icons.local_offer_rounded),
            label: 'Offers',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
