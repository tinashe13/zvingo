import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_motion.dart';

/// Wraps any tappable surface with the §4.3 press feedback: a scale to 0.985
/// over `motion/instant`.
///
/// The design system says *every* tappable surface does this, no exceptions,
/// so prefer `TapScale` over a bare `GestureDetector` or `InkWell` whenever the
/// thing being tapped is a card, tile, chip or custom control. Buttons in this
/// library already wrap themselves.
///
/// It also enforces the 48×48 minimum touch target and honours reduced motion
/// (the scale collapses to 1.0, the tap still works).
///
/// ```dart
/// TapScale(
///   onTap: () => context.push('/earnings/history'),
///   child: EarningsRow(record: record),
/// )
/// ```
class TapScale extends StatefulWidget {
  /// The surface to animate. Rendered as-is.
  final Widget child;

  /// Called on tap. When null the widget is inert and does not animate.
  final VoidCallback? onTap;

  /// Called on long press. Optional.
  final VoidCallback? onLongPress;

  /// Scale applied while pressed. Defaults to `AppMotion.tapScale` (0.985).
  final double pressedScale;

  /// Fires a selection click on tap down. On by default because the driver is
  /// often looking at the road, not the screen.
  final bool haptic;

  /// Enforces a 48×48 minimum hit area around [child] (§5.1).
  final bool enforceMinTarget;

  /// Semantic label announced by screen readers.
  final String? semanticLabel;

  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = AppMotion.tapScale,
    this.haptic = true,
    this.enforceMinTarget = true,
    this.semanticLabel,
  });

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final scale = _pressed && !reduced ? widget.pressedScale : 1.0;

    Widget content = AnimatedScale(
      scale: scale,
      duration: AppMotion.durationOf(context, AppMotion.instant),
      curve: AppMotion.standard,
      child: widget.child,
    );

    if (widget.enforceMinTarget) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: content,
      );
    }

    return Semantics(
      button: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapUp: _enabled ? (_) => _setPressed(false) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: content,
      ),
    );
  }
}
