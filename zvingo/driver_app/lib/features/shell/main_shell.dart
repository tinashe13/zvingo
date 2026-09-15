import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_motion.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../core/router.dart';
import '../../models/delivery_state.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/active_delivery_bar.dart';

/// The app's navigational spine (§5.4).
///
/// Five labelled tabs, never more, never icon-only. The selected tab is
/// `action/default` with a 700 label and a sliding pill indicator; unselected
/// is `neutral/400`. Every destination is at least 48×48.
///
/// Two things make this shell specific to the driver product:
///
/// * **Per-tab state is preserved.** Each tab keeps its scroll position and
///   any in-progress input while the driver hops between them, because a
///   driver checking their earnings mid-shift should come back to exactly the
///   screen they left.
/// * **A persistent active-delivery bar.** While a delivery is live, a bar
///   sits above the navigation on *every* tab naming the current step and
///   tapping straight back into the flow. Getting lost mid-delivery is the
///   worst failure this app can have, and this is the guard against it.
class MainShell extends ConsumerWidget {
  /// The branch navigator stack from `StatefulShellRoute.indexedStack`.
  /// It owns the per-tab state; the shell only draws the chrome around it.
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  /// The tabs, in order. Max five (§5.4).
  static const List<({IconData icon, IconData activeIcon, String label, String path})>
      tabs = [
    (
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore,
      label: 'Dash',
      path: '/',
    ),
    (
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
      label: 'Schedule',
      path: '/schedule',
    ),
    (
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      label: 'Earnings',
      path: '/earnings',
    ),
    (
      icon: Icons.star_outline_rounded,
      activeIcon: Icons.star_rounded,
      label: 'Ratings',
      path: '/ratings',
    ),
    (
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Account',
      path: '/account',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = navigationShell.currentIndex;
    final delivery = ref.watch(deliveryProvider);
    final showDeliveryBar = delivery.hasActiveDelivery &&
        delivery.deliveryState != DeliveryState.offered;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Persistent context bar: appears on every tab while a delivery is
          // in progress, and taps straight back into the flow (§5.4).
          AnimatedSize(
            duration: AppMotion.durationOf(context, AppMotion.base),
            curve: AppMotion.standard,
            alignment: Alignment.bottomCenter,
            child: showDeliveryBar
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: ActiveDeliveryBar(
                      state: delivery.deliveryState,
                      orderLabel: delivery.activeOrderShortId == null
                          ? null
                          : '#${delivery.activeOrderShortId}',
                      destination: _destinationFor(delivery),
                      onTap: () =>
                          context.go(deliveryRouteFor(delivery.deliveryState)),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          _DriverNavBar(
            currentIndex: index,
            onSelected: (next) => _onTabSelected(context, next),
          ),
        ],
      ),
    );
  }

  /// Switching tab keeps the branch's own stack; re-tapping the current tab
  /// pops that branch back to its root, which is what every driver expects
  /// from a bottom bar.
  void _onTabSelected(BuildContext context, int index) {
    HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  /// Where the driver is heading right now, for the context bar's subtitle.
  String? _destinationFor(DeliveryFlowState delivery) {
    final offer = delivery.currentOffer;
    if (offer == null) return null;
    return switch (delivery.deliveryState) {
      DeliveryState.accepted ||
      DeliveryState.enRoutePickup ||
      DeliveryState.arrivedPickup ||
      DeliveryState.pickedUp =>
        offer.merchantName,
      _ => offer.customerAddress.isNotEmpty
          ? offer.customerAddress
          : offer.customerName,
    };
  }
}

/// The bottom tab bar: always labelled, 48×48+ targets, animated indicator,
/// `shadow/dock` and safe-area padding.
class _DriverNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;

  const _DriverNavBar({required this.currentIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final selected = AppColors.actionOf(context);
    final unselected = Theme.of(context).brightness == Brightness.dark
        ? AppColors.neutral500
        : AppColors.navUnselected;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
        boxShadow: AppSpacing.shadowDockOf(context),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSpacing.navBarHeight,
          child: Row(
            children: [
              for (var i = 0; i < MainShell.tabs.length; i++)
                Expanded(
                  child: _NavItem(
                    tab: MainShell.tabs[i],
                    isSelected: i == currentIndex,
                    selectedColor: selected,
                    unselectedColor: unselected,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final ({IconData icon, IconData activeIcon, String label, String path}) tab;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.tab,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? selectedColor : unselectedColor;

    return Semantics(
      selected: isSelected,
      button: true,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.brMd,
        child: SizedBox(
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The indicator is a pill that grows behind the selected icon —
              // movement between tabs reads as continuity, not a redraw.
              AnimatedContainer(
                duration: AppMotion.durationOf(context, AppMotion.fast),
                curve: AppMotion.standard,
                height: 30,
                width: isSelected ? 52 : 34,
                decoration: BoxDecoration(
                  color: isSelected
                      ? selectedColor.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: AppSpacing.brFull,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isSelected ? tab.activeIcon : tab.icon,
                  size: 24,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.overline.copyWith(
                  fontSize: 11,
                  letterSpacing: 0.1,
                  color: color,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
