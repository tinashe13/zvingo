import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_spacing.dart';
import 'tap_scale.dart';

/// Circular icon control that floats over a map.
///
/// Sized 52 rather than the 44 of §5.1's icon button: it is tapped one-handed,
/// with a thumb, on a moving vehicle, and it has no label to aim at. It uses
/// `shadow/md` so it stays legible over both a pale basemap and a dark one.
///
/// [tooltip] is strongly recommended — an icon-only control with no accessible
/// name is unusable with a screen reader.
///
/// ```dart
/// FloatingMapButton(
///   icon: Icons.my_location,
///   tooltip: 'Centre on my location',
///   onPressed: _recentre,
/// )
/// ```
class FloatingMapButton extends StatelessWidget {
  /// The glyph.
  final IconData icon;

  /// Tap handler. Null renders the control disabled rather than hiding it.
  final VoidCallback? onPressed;

  /// Diameter. Defaults to 52.
  final double size;

  /// Accessible name and long-press tooltip.
  final String? tooltip;

  /// Renders the button in the accent colour to mark it as active — e.g. a
  /// map layer currently switched on.
  final bool isActive;

  const FloatingMapButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 52,
    this.tooltip,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null;

    final background = isActive
        ? AppColors.actionOf(context)
        : AppColors.surfaceOf(context);
    final foreground = !enabled
        ? AppColors.neutral400
        : isActive
            ? AppColors.onActionOf(context)
            : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary);

    final button = TapScale(
      onTap: onPressed,
      enforceMinTarget: false,
      semanticLabel: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderOf(context)),
          boxShadow: AppSpacing.shadowMdOf(context),
        ),
        child: Icon(icon, size: size * 0.44, color: foreground),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
