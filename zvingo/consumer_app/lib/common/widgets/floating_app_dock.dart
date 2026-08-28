import 'dart:ui';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:flutter/material.dart';

/// A compact floating destination dock that lets page content remain visible
/// beneath it. The translucent surface uses a real backdrop blur rather than a
/// solid bottom bar, while Search remains the primary middle action.
class FloatingAppDock extends StatelessWidget {
  const FloatingAppDock({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 66,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: AppColors.white.withOpacity(0.72),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F101211),
                        blurRadius: 28,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _DockDestination(
                        label: 'Home',
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        selected: currentIndex == 0,
                        onTap: () => onSelected(0),
                      ),
                      _DockDestination(
                        label: 'Nearby',
                        icon: Icons.map_outlined,
                        selectedIcon: Icons.map_rounded,
                        selected: currentIndex == 1,
                        onTap: () => onSelected(1),
                      ),
                      const SizedBox(width: 76),
                      _DockDestination(
                        label: 'Orders',
                        icon: Icons.receipt_long_outlined,
                        selectedIcon: Icons.receipt_long_rounded,
                        selected: currentIndex == 3,
                        onTap: () => onSelected(3),
                      ),
                      _DockDestination(
                        label: 'Account',
                        icon: Icons.person_outline_rounded,
                        selectedIcon: Icons.person_rounded,
                        selected: currentIndex == 4,
                        onTap: () => onSelected(4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: _SearchDestination(
              selected: currentIndex == 2,
              onTap: () => onSelected(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockDestination extends StatelessWidget {
  const _DockDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 29,
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 22,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: selected ? 16 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchDestination extends StatelessWidget {
  const _SearchDestination({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Search',
      child: InkResponse(
        onTap: onTap,
        customBorder: const CircleBorder(),
        radius: 36,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.selectedDark,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.white,
                  width: selected ? 3 : 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x39101211),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.search_rounded,
                color: AppColors.white,
                size: 27,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Search',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
