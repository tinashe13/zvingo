import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_motion.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/theme.dart';

import 'zv_tap_scale.dart';

/// The five button variants of §5.1.
enum ZvButtonVariant {
  /// `action/default` fill, `neutral/0` label, no border, h52, `radius/md`.
  primary,

  /// Transparent fill, `neutral/900` label, 1px `neutral/200`, h52.
  secondary,

  /// Transparent fill, `neutral/900` label, no border, h44.
  tertiary,

  /// `error` fill, `neutral/0` label, no border, h52.
  destructive,
}

/// The standard Zvingo button (§5.1).
///
/// One filled [ZvButtonVariant.primary] per screen; everything else is
/// [ZvButtonVariant.secondary], [ZvButtonVariant.tertiary] or a [ZvIconButton].
///
/// * `loading: true` swaps the label for an inline spinner **without changing
///   the button's width** — the label is still laid out, just invisible.
/// * A disabled button is never hidden. Pass [disabledReason] and the reason
///   renders in `caption` directly beneath it (§5.1).
///
/// ```dart
/// ZvButton.primary(
///   label: 'Place order',
///   icon: Icons.lock_rounded,
///   loading: state.isSubmitting,
///   onPressed: _submit,
/// )
///
/// ZvButton.secondary(label: 'Add more items', onPressed: _browse)
/// ZvButton.tertiary(label: 'Skip for now', onPressed: _skip)
/// ZvButton.destructive(label: 'Cancel order', onPressed: _cancel)
/// ```
class ZvButton extends StatelessWidget {
  /// Creates a button with an explicit [variant].
  const ZvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ZvButtonVariant.primary,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = true,
    this.disabledReason,
    this.semanticLabel,
  });

  /// The one filled action on the screen.
  const ZvButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = true,
    this.disabledReason,
    this.semanticLabel,
  }) : variant = ZvButtonVariant.primary;

  /// Outlined alternative action.
  const ZvButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = true,
    this.disabledReason,
    this.semanticLabel,
  }) : variant = ZvButtonVariant.secondary;

  /// Low-emphasis text action.
  const ZvButton.tertiary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
    this.disabledReason,
    this.semanticLabel,
  }) : variant = ZvButtonVariant.tertiary;

  /// Irreversible action. Always pair with a `ZvConfirmSheet`.
  const ZvButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = true,
    this.disabledReason,
    this.semanticLabel,
  }) : variant = ZvButtonVariant.destructive;

  /// Button label. Say what happens, e.g. "Place order", not "Submit".
  final String label;

  /// Tap handler. `null` disables the button.
  final VoidCallback? onPressed;

  /// Which of the §5.1 variants to render.
  final ZvButtonVariant variant;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional trailing icon, e.g. a chevron on a "Continue" button.
  final IconData? trailingIcon;

  /// Shows an inline spinner and blocks taps. Width does not change.
  final bool loading;

  /// Stretch to the available width. Primary actions normally do.
  final bool fullWidth;

  /// Plain-language reason shown under a disabled button (§5.1: "disabled
  /// buttons are never hidden — they are disabled with a visible reason").
  final String? disabledReason;

  /// Overrides the screen-reader label when [label] is not descriptive alone.
  final String? semanticLabel;

  bool get _enabled => onPressed != null && !loading;

  double get _height => variant == ZvButtonVariant.tertiary
      ? AppTheme.tertiaryButtonHeight
      : AppTheme.buttonHeight;

  Color _foreground() {
    if (!_enabled && !loading) return AppColors.actionDisabledFg;
    switch (variant) {
      case ZvButtonVariant.primary:
      case ZvButtonVariant.destructive:
        return AppColors.textOnDark;
      case ZvButtonVariant.secondary:
      case ZvButtonVariant.tertiary:
        return AppColors.textPrimary;
    }
  }

  Color _background() {
    if (!_enabled && !loading) {
      return variant == ZvButtonVariant.primary ||
              variant == ZvButtonVariant.destructive
          ? AppColors.actionDisabledBg
          : Colors.transparent;
    }
    switch (variant) {
      case ZvButtonVariant.primary:
        return AppColors.actionDefault;
      case ZvButtonVariant.destructive:
        return AppColors.error;
      case ZvButtonVariant.secondary:
      case ZvButtonVariant.tertiary:
        return Colors.transparent;
    }
  }

  BoxBorder? _border() {
    if (variant != ZvButtonVariant.secondary) return null;
    return Border.all(
      color: _enabled ? AppColors.border : AppColors.actionDisabledBg,
    );
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _foreground();

    // The label stays in the layout while loading (just invisible) so the
    // button keeps its exact width — no jump when the spinner appears.
    final content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 19, color: foreground),
          const SizedBox(width: AppSpacing.xs),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.button.copyWith(color: foreground),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(trailingIcon, size: 19, color: foreground),
        ],
      ],
    );

    final body = Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: loading ? 0 : 1, child: content),
        if (loading)
          SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              strokeCap: StrokeCap.round,
              color: foreground,
            ),
          ),
      ],
    );

    final surface = AnimatedContainer(
      duration: context.motion(AppMotion.fast),
      curve: context.motionCurve(AppMotion.standard),
      height: _height,
      width: fullWidth ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal:
            variant == ZvButtonVariant.tertiary ? AppSpacing.sm : AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: _background(),
        borderRadius: AppRadius.mdAll,
        border: _border(),
      ),
      alignment: Alignment.center,
      child: body,
    );

    final tappable = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _enabled ? onPressed : null,
        borderRadius: AppRadius.mdAll,
        splashColor: foreground.withValues(alpha: 0.08),
        highlightColor: foreground.withValues(alpha: 0.04),
        child: surface,
      ),
    );

    final button = Semantics(
      button: true,
      enabled: _enabled,
      label: semanticLabel ?? label,
      child: ZvTapScale(
        childHandlesTap: true,
        behavior: HitTestBehavior.deferToChild,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTapTarget,
            minWidth: AppSpacing.minTapTarget,
          ),
          child: tappable,
        ),
      ),
    );

    if (disabledReason == null || _enabled) return button;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xxs + 2),
            Expanded(
              child: Text(disabledReason!, style: AppTextStyles.caption),
            ),
          ],
        ),
      ],
    );
  }
}

/// The §5.1 icon button: `neutral/100` fill, `neutral/900` glyph, 44×44
/// visual inside a 48×48 tap target, `radius/full`.
///
/// [tooltip] is required — an icon with no accessible name is a defect.
///
/// ```dart
/// ZvIconButton(
///   icon: Icons.favorite_border_rounded,
///   tooltip: 'Save to favourites',
///   onPressed: _toggleFavourite,
/// )
/// ```
class ZvIconButton extends StatelessWidget {
  const ZvIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
    this.background = AppColors.surfaceMuted,
    this.foreground = AppColors.textPrimary,
    this.badgeCount,
  });

  /// The glyph.
  final IconData icon;

  /// Accessible name, also shown on long-press. Required.
  final String tooltip;

  /// Tap handler. `null` disables the button.
  final VoidCallback? onPressed;

  /// Replaces the glyph with an inline spinner; size is unchanged.
  final bool loading;

  /// Fill colour. Defaults to `neutral/100`.
  final Color background;

  /// Glyph colour. Defaults to `neutral/900`.
  final Color foreground;

  /// Optional count badge, e.g. items in the cart. Values above 99 show "99+".
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final fg = enabled ? foreground : AppColors.actionDisabledFg;

    Widget glyph = loading
        ? SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              strokeCap: StrokeCap.round,
              color: fg,
            ),
          )
        : Icon(icon, size: 21, color: fg);

    if (badgeCount != null && badgeCount! > 0) {
      glyph = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          glyph,
          Positioned(
            top: -6,
            right: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17),
              height: 17,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.error,
                borderRadius: AppRadius.fullAll,
              ),
              child: Text(
                badgeCount! > 99 ? '99+' : '${badgeCount!}',
                style: AppTextStyles.overline.copyWith(
                  color: AppColors.textOnDark,
                  fontSize: 10,
                  letterSpacing: 0,
                  fontFeatures: AppTextStyles.tabularFigures,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: ZvTapScale(
          childHandlesTap: true,
          behavior: HitTestBehavior.deferToChild,
          child: SizedBox(
            height: AppSpacing.minTapTarget,
            width: AppSpacing.minTapTarget,
            child: Center(
              child: Material(
                color: enabled ? background : AppColors.actionDisabledBg,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled ? onPressed : null,
                  child: SizedBox(
                    height: AppTheme.iconButtonSize,
                    width: AppTheme.iconButtonSize,
                    child: Center(child: glyph),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sticky footer holding the screen's one primary action (§5.1: "full-width
/// primary buttons live in a sticky footer with `shadow/dock` and safe-area
/// padding").
///
/// ```dart
/// Scaffold(
///   body: ...,
///   bottomNavigationBar: ZvStickyFooter(
///     child: ZvButton.primary(label: 'Continue to payment', onPressed: _go),
///   ),
/// )
/// ```
class ZvStickyFooter extends StatelessWidget {
  const ZvStickyFooter({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.sm,
    ),
  });

  /// Footer content — normally a single [ZvButton].
  final Widget child;

  /// Padding around [child], before the safe-area inset is added.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.dock,
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
