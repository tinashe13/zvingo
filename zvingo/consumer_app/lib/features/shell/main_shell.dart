import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/order/active_order_provider.dart';
import 'package:consumer_app/features/order/order_status_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// DoorDash-style 5-tab bottom navigation shell
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: BottomNavigationBar(
              currentIndex: widget.currentIndex,
              onTap: widget.onTabChanged,
              elevation: 0,
              backgroundColor: Colors.transparent,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppColors.navSelected,
              unselectedItemColor: AppColors.navUnselected,
              selectedFontSize: 11,
              unselectedFontSize: 11,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.directions_walk_outlined),
                  activeIcon: Icon(Icons.directions_walk),
                  label: 'Pickup',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.local_offer_outlined),
                  activeIcon: Icon(Icons.local_offer),
                  label: 'Offers',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.receipt_long_outlined),
                  activeIcon: Icon(Icons.receipt_long),
                  label: 'Orders',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'Account',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
