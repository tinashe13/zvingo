import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';

/// The meaning a [StatusChip] carries. Each value picks a colour *and* an
/// icon, because §1.5 forbids communicating state by colour alone.
enum StatusTone {
  /// Delivered, paid, online, confirmed.
  success,

  /// Waiting, delayed, action needed soon.
  warning,

  /// Failed, cancelled, rejected.
  error,

  /// Neutral informational.
  info,

  /// Inert / offline / not applicable.
  neutral,
}

/// A small labelled state pill: semantic colour + icon + text.
///
/// Use it anywhere a driver needs to read a status at a glance — order state,
/// payout state, shift state, connection state. Never use a bare coloured dot:
/// roughly 8% of men cannot tell the ramp apart, and sunlight flattens
/// saturation further.
///
/// ```dart
/// StatusChip(label: 'Online', tone: StatusTone.success)
/// StatusChip(label: 'Cash order', tone: StatusTone.warning, icon: Icons.payments)
/// ```
class StatusChip extends StatelessWidget {
  /// The status text. Rendered uppercase in `overline` by default.
  final String label;

  /// Semantic tone, driving colour and the default icon.
  final StatusTone tone;

  /// Overrides the tone's default icon.
  final IconData? icon;

  /// Renders the label as written instead of upper-casing it. Use for
  /// proper nouns and money.
  final bool preserveCase;

  /// Renders a filled pill in the tone colour rather than a tinted one. Use
  /// sparingly — at most one per card.
  final bool emphasized;

  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
    this.preserveCase = false,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = _foreground(context);
    final bg = emphasized ? fg : _surface(context);
    final labelColor = emphasized ? _onEmphasis(context) : fg;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppSpacing.brSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? _defaultIcon, size: 14, color: labelColor),
          const SizedBox(width: AppSpacing.xs + 2),
          Flexible(
            child: Text(
              preserveCase ? label : label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (preserveCase
                      ? AppTextStyles.caption
                      : AppTextStyles.overline)
                  .copyWith(color: labelColor),
            ),
          ),
        ],
      ),
    );
  }

  IconData get _defaultIcon => switch (tone) {
        StatusTone.success => Icons.check_circle_rounded,
        StatusTone.warning => Icons.schedule_rounded,
        StatusTone.error => Icons.error_rounded,
        StatusTone.info => Icons.info_rounded,
        StatusTone.neutral => Icons.circle_outlined,
      };

  Color _foreground(BuildContext context) => switch (tone) {
        StatusTone.success => AppColors.successOf(context),
        StatusTone.warning => AppColors.warningOf(context),
        StatusTone.error => AppColors.errorOf(context),
        StatusTone.info => AppColors.infoOf(context),
        StatusTone.neutral =>
          Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkTextSecondary
              : AppColors.textSecondary,
      };

  Color _surface(BuildContext context) => switch (tone) {
        StatusTone.success => AppColors.successSurfaceOf(context),
        StatusTone.warning => AppColors.warningSurfaceOf(context),
        StatusTone.error => AppColors.errorSurfaceOf(context),
        StatusTone.info => AppColors.infoSurfaceOf(context),
        StatusTone.neutral => AppColors.surfaceMutedOf(context),
      };

  Color _onEmphasis(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.neutral900
          : AppColors.textOnDark;
}
