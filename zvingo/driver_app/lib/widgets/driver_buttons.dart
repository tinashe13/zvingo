import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import 'tap_scale.dart';

/// Visual weight of a [DriverButton].
enum DriverButtonVariant {
  /// Filled near-black. Exactly one per screen (§0.2).
  primary,

  /// Outlined. Everything that is not *the* action on the screen.
  secondary,

  /// Filled error red. Irreversible, negative actions — "Unassign me",
  /// "Cancel delivery". Always pair with a [ConfirmSheet].
  destructive,

  /// Text only. Lowest weight, used for "Not now" / "Skip".
  tertiary,

  /// Filled brand green. Reserved for going online and other positive,
  /// non-transactional state changes.
  positive,
}

/// The one button in the driver app.
///
/// 56pt tall (see the deviation note in `theme.dart`: the driver app is used
/// one-handed, outdoors, often on a motorbike, so §5.1's 52 is raised), full
/// width by default, and built to live in the bottom third of the screen.
///
/// Behaviour that is not optional:
/// * **Loading locks the width.** The label is swapped for a spinner inside a
///   box sized to the label, so the button never resizes mid-submit (§5.1).
/// * **Disabled is visible, never hidden** — pass [disabledReason] and it is
///   rendered under the button in plain language (§5.1).
/// * **Press feedback** via [TapScale] and a selection click, because the
///   driver's eyes are often not on the screen.
///
/// Prefer the named constructors [DriverPrimaryButton], [DriverSecondaryButton]
/// and [DriverDestructiveButton] at call sites — they read better in a tree.
class DriverButton extends StatelessWidget {
  /// Button label. Kept to two or three words.
  final String label;

  /// Tap handler. Null disables the button.
  final VoidCallback? onPressed;

  /// Visual weight. Defaults to [DriverButtonVariant.primary].
  final DriverButtonVariant variant;

  /// Optional leading icon.
  final IconData? icon;

  /// Replaces the label with a spinner and blocks taps. Width is locked.
  final bool isLoading;

  /// Stretches to the parent's width. On by default — driver actions are
  /// full-bleed in a sticky footer.
  final bool expanded;

  /// Plain-language explanation shown beneath the button when it is disabled.
  /// A disabled button with no reason is a dead end (§5.1).
  final String? disabledReason;

  /// Overrides the button height. Defaults to 56.
  final double height;

  const DriverButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = DriverButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.disabledReason,
    this.height = AppSpacing.buttonHeight,
  });

  bool get _enabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = _palette(context, isDark);

    final content = AnimatedSwitcher(
      duration: AppMotion.durationOf(context, AppMotion.fast),
      child: isLoading
          ? _LockedWidthSpinner(
              key: const ValueKey('loading'),
              label: label,
              style: AppTextStyles.button,
              color: palette.foreground,
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22, color: palette.foreground),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.button
                        .copyWith(color: palette.foreground),
                  ),
                ),
              ],
            ),
    );

    final button = TapScale(
      onTap: _enabled
          ? () {
              HapticFeedback.selectionClick();
              onPressed!();
            }
          : null,
      enforceMinTarget: false,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.fast),
        curve: AppMotion.standard,
        height: height,
        width: expanded ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: AppSpacing.brMd,
          border: palette.border == null
              ? null
              : Border.all(color: palette.border!, width: 1),
        ),
        child: content,
      ),
    );

    if (_enabled || disabledReason == null) {
      return Semantics(enabled: _enabled, child: button);
    }

    // A disabled button always states why (§5.1).
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(enabled: false, child: button),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: AppColors.warningOf(context),
            ),
            const SizedBox(width: AppSpacing.xs + 2),
            Expanded(
              child: Text(
                disabledReason!,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.warningOf(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  _ButtonPalette _palette(BuildContext context, bool isDark) {
    if (!_enabled) {
      return _ButtonPalette(
        background: variant == DriverButtonVariant.tertiary ||
                variant == DriverButtonVariant.secondary
            ? Colors.transparent
            : (isDark ? AppColors.neutral800 : AppColors.actionDisabledBg),
        foreground: isDark ? AppColors.neutral500 : AppColors.actionDisabledFg,
        border: variant == DriverButtonVariant.secondary
            ? AppColors.borderOf(context)
            : null,
      );
    }

    return switch (variant) {
      DriverButtonVariant.primary => _ButtonPalette(
          background: AppColors.actionOf(context),
          foreground: AppColors.onActionOf(context),
        ),
      DriverButtonVariant.secondary => _ButtonPalette(
          background: Colors.transparent,
          foreground:
              isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          border: AppColors.borderOf(context),
        ),
      DriverButtonVariant.destructive => _ButtonPalette(
          background: AppColors.errorOf(context),
          foreground: isDark ? AppColors.neutral900 : AppColors.textOnDark,
        ),
      DriverButtonVariant.tertiary => _ButtonPalette(
          background: Colors.transparent,
          foreground:
              isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
        ),
      DriverButtonVariant.positive => _ButtonPalette(
          background: AppColors.successOf(context),
          foreground: isDark ? AppColors.neutral900 : AppColors.textOnDark,
        ),
    };
  }
}

class _ButtonPalette {
  final Color background;
  final Color foreground;
  final Color? border;

  const _ButtonPalette({
    required this.background,
    required this.foreground,
    this.border,
  });
}

/// Renders a spinner inside a box the exact width the label would occupy, so
/// switching to the loading state cannot shift the layout (§5.1).
class _LockedWidthSpinner extends StatelessWidget {
  final String label;
  final TextStyle style;
  final Color color;

  const _LockedWidthSpinner({
    super.key,
    required this.label,
    required this.style,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final labelWidth = painter.width;
    painter.dispose();

    return SizedBox(
      width: labelWidth,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ),
    );
  }
}

/// The single filled action on a screen (§0.2). 56pt, near-black.
///
/// ```dart
/// DriverPrimaryButton(
///   label: 'Go online',
///   icon: Icons.bolt,
///   onPressed: _goOnline,
///   isLoading: state.isSubmitting,
/// )
/// ```
class DriverPrimaryButton extends StatelessWidget {
  /// Button label.
  final String label;

  /// Tap handler. Null disables the button — pair with [disabledReason].
  final VoidCallback? onPressed;

  /// Optional leading icon.
  final IconData? icon;

  /// Swaps the label for a spinner without changing the button's width.
  final bool isLoading;

  /// Stretches to the parent's width. On by default.
  final bool expanded;

  /// Plain-language reason shown under the button while it is disabled.
  final String? disabledReason;

  const DriverPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) => DriverButton(
        label: label,
        onPressed: onPressed,
        icon: icon,
        isLoading: isLoading,
        expanded: expanded,
        disabledReason: disabledReason,
      );
}

/// Outlined companion action. Any number per screen, but never more than one
/// next to the primary.
class DriverSecondaryButton extends StatelessWidget {
  /// Button label.
  final String label;

  /// Tap handler. Null disables the button.
  final VoidCallback? onPressed;

  /// Optional leading icon.
  final IconData? icon;

  /// Swaps the label for a spinner without changing the button's width.
  final bool isLoading;

  /// Stretches to the parent's width. On by default.
  final bool expanded;

  /// Plain-language reason shown under the button while it is disabled.
  final String? disabledReason;

  const DriverSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) => DriverButton(
        label: label,
        onPressed: onPressed,
        variant: DriverButtonVariant.secondary,
        icon: icon,
        isLoading: isLoading,
        expanded: expanded,
        disabledReason: disabledReason,
      );
}

/// Filled red action for something the driver cannot undo.
///
/// Always route it through [ConfirmSheet] first — §5.4 requires a confirm step
/// that names the consequence in plain language.
class DriverDestructiveButton extends StatelessWidget {
  /// Button label, phrased as the consequence ("Cancel this delivery").
  final String label;

  /// Tap handler. Null disables the button.
  final VoidCallback? onPressed;

  /// Optional leading icon.
  final IconData? icon;

  /// Swaps the label for a spinner without changing the button's width.
  final bool isLoading;

  /// Stretches to the parent's width. On by default.
  final bool expanded;

  /// Plain-language reason shown under the button while it is disabled.
  final String? disabledReason;

  const DriverDestructiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) => DriverButton(
        label: label,
        onPressed: onPressed,
        variant: DriverButtonVariant.destructive,
        icon: icon,
        isLoading: isLoading,
        expanded: expanded,
        disabledReason: disabledReason,
      );
}

/// Lowest-weight action — "Not now", "Skip", "Maybe later".
class DriverTextButton extends StatelessWidget {
  /// Button label.
  final String label;

  /// Tap handler. Null disables the button.
  final VoidCallback? onPressed;

  /// Optional leading icon.
  final IconData? icon;

  /// Stretches to the parent's width. Off by default.
  final bool expanded;

  const DriverTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) => DriverButton(
        label: label,
        onPressed: onPressed,
        variant: DriverButtonVariant.tertiary,
        icon: icon,
        expanded: expanded,
        height: AppSpacing.buttonHeightCompact,
      );
}

/// Circular icon affordance — 48×48, muted fill, dark glyph (§5.1).
///
/// [tooltip] doubles as the semantic label, so it is required: an icon-only
/// control with no name is unusable with a screen reader.
class DriverIconButton extends StatelessWidget {
  /// The glyph.
  final IconData icon;

  /// Tap handler. Null disables the control.
  final VoidCallback? onPressed;

  /// Accessible name and long-press tooltip. Required, not optional.
  final String tooltip;

  /// Overrides the fill. Defaults to the muted surface.
  final Color? backgroundColor;

  /// Overrides the glyph colour.
  final Color? foregroundColor;

  /// Diameter. Defaults to 48.
  final double size;

  const DriverIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.size = AppSpacing.minTouchTarget,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = enabled
        ? (foregroundColor ??
            (Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkTextPrimary
                : AppColors.textPrimary))
        : AppColors.neutral400;

    return Tooltip(
      message: tooltip,
      child: TapScale(
        onTap: onPressed,
        semanticLabel: tooltip,
        enforceMinTarget: false,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.surfaceMutedOf(context),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: size * 0.46, color: fg),
        ),
      ),
    );
  }
}

/// A sticky footer for the screen's primary action: `shadow/dock`, the surface
/// colour, and safe-area padding so the button clears the home indicator
/// (§5.1).
///
/// ```dart
/// bottomNavigationBar: DriverActionFooter(
///   child: DriverPrimaryButton(label: 'Confirm pickup', onPressed: _confirm),
/// )
/// ```
class DriverActionFooter extends StatelessWidget {
  /// Usually a single button, or a Column of a primary plus a tertiary.
  final Widget child;

  /// Optional line of context rendered above [child] — a total, a warning.
  final Widget? supporting;

  const DriverActionFooter({
    super.key,
    required this.child,
    this.supporting,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        boxShadow: AppSpacing.shadowDockOf(context),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (supporting != null) ...[
                supporting!,
                const SizedBox(height: AppSpacing.md),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}
