import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';


/// MainShell — Scaffold with bottom navigation bar.
/// Mirrors ZvingoNavHost.kt. Hides bottom bar during delivery flow.
class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  static const _tabs = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', path: '/'),
    (icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: 'Schedule', path: '/schedule'),
    (icon: Icons.attach_money, activeIcon: Icons.attach_money, label: 'Earnings', path: '/earnings'),
    (icon: Icons.star_outline, activeIcon: Icons.star, label: 'Ratings', path: '/ratings'),
    (icon: Icons.person_outline, activeIcon: Icons.person, label: 'Account', path: '/account'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _tabs.indexWhere((tab) => tab.path == location);
    return index >= 0 ? index : 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => context.go(_tabs[index].path),
        items: _tabs
            .map((tab) => BottomNavigationBarItem(
                  icon: Icon(tab.icon),
                  activeIcon: Icon(tab.activeIcon),
                  label: tab.label,
                ))
            .toList(),
      ),
    );
  }
}
