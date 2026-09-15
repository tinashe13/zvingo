import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_motion.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';

/// One destination in the [FloatingAppDock].
class ZvDockDestination {
  const ZvDockDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badgeCount,
  });

  /// Always-visible label. Icon-only bars are banned (§5.4).
  final String label;

  /// Unselected glyph.
  final IconData icon;

  /// Selected glyph.
  final IconData selectedIcon;

  /// Optional count badge, e.g. active orders.
  final int? badgeCount;
}

/// The consumer app's bottom tab bar — the spine of the whole product (§5.4).
///
/// Rules it enforces:
/// * at most **5** destinations, every one **labelled**;
/// * selected = `action/default` icon + 700 label, unselected = `neutral/400`;
/// * every destination is at least **48×48**;
/// * a smooth animated pill slides under the selected destination;
/// * `shadow/dock` and safe-area padding, so it floats above content.
///
/// It is stateless and driven entirely by [currentIndex] / [onSelected]; the
/// shell owns per-tab navigation state.
class FloatingAppDock extends StatelessWidget {
  const FloatingAppDock({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.destinations = defaultDestinations,
  });

  /// Index of the active destination.
  final int currentIndex;

  /// Called with the tapped destination's index.
  final ValueChanged<int> onSelected;

  /// Destinations, in order. Maximum five.
  final List<ZvDockDestination> destinations;

  /// The consumer app's five tabs: Home, Nearby, Search, Orders, Account.
  static const List<ZvDockDestination> defaultDestinations =
      <ZvDockDestination>[
    ZvDockDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    ZvDockDestination(
      label: 'Nearby',
      icon: Icons.map_outlined,
      selectedIcon: Icons.map_rounded,
    ),
    ZvDockDestination(
      label: 'Search',
      icon: Icons.search_outlined,
      selectedIcon: Icons.search_rounded,
    ),
    ZvDockDestination(
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
    ),
    ZvDockDestination(
      label: 'Account',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  /// Height of the dock itself, excluding safe-area padding.
  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    assert(
      destinations.length <= 5,
      'A bottom tab bar may have at most 5 destinations (§5.4).',
    );

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.dock,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = destinations.length;
          final slot = constraints.maxWidth / count;
          final indicatorWidth = (slot - AppSpacing.xs).clamp(48.0, 96.0);
          final index = currentIndex.clamp(0, count - 1);

          return Stack(
            children: [
              AnimatedPositioned(
                duration: context.motion(AppMotion.base),
                curve: context.motionCurve(AppMotion.standard),
                left: slot * index + (slot - indicatorWidth) / 2,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
                width: indicatorWidth,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: AppRadius.mdAll,
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: _DockDestination(
                        destination: destinations[i],
                        selected: i == index,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DockDestination extends StatelessWidget {
  const _DockDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ZvDockDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.navSelected : AppColors.navUnselected;
    final badge = destination.badgeCount;

    Widget glyph = AnimatedSwitcher(
      duration: context.motion(AppMotion.fast),
      child: Icon(
        selected ? destination.selectedIcon : destination.icon,
        key: ValueKey<bool>(selected),
        size: 22,
        color: color,
      ),
    );

    if (badge != null && badge > 0) {
      glyph = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          glyph,
          Positioned(
            top: -4,
            right: -9,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.error,
                borderRadius: AppRadius.fullAll,
              ),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                style: AppTextStyles.overline.copyWith(
                  color: AppColors.textOnDark,
                  fontSize: 9,
                  letterSpacing: 0,
                  fontFeatures: AppTextStyles.tabularFigures,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        containedInkWell: false,
        highlightShape: BoxShape.rectangle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTapTarget,
            minWidth: AppSpacing.minTapTarget,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              glyph,
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: context.motion(AppMotion.fast),
                curve: context.motionCurve(AppMotion.standard),
                style: AppTextStyles.overline.copyWith(
                  color: color,
                  fontSize: 10,
                  letterSpacing: 0,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
