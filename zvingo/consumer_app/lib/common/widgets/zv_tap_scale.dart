import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_motion.dart';

/// Wraps any child so it scales to **0.985** while pressed, over
/// `motion/instant` (§4.3: "every tappable surface scales to 0.985 — no
/// exceptions").
///
/// Use it around cards, tiles and custom tappable surfaces. `ZvButton` and the
/// other library widgets already apply it, so do not nest one inside another.
///
/// ```dart
/// ZvTapScale(
///   onTap: () => context.push('/restaurant/$id'),
///   child: ZvCard(child: ...),
/// )
/// ```
class ZvTapScale extends StatefulWidget {
  const ZvTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.985,
    this.semanticLabel,
    this.behavior = HitTestBehavior.opaque,
    this.enableFeedback = true,
  });

  /// The surface being made tappable.
  final Widget child;

  /// Tap handler. When null the child renders but does not react.
  final VoidCallback? onTap;

  /// Optional long-press handler.
  final VoidCallback? onLongPress;

  /// Pressed scale. Leave at the token value unless you have a reason.
  final double scale;

  /// Screen-reader label describing the action.
  final String? semanticLabel;

  /// Hit-test behaviour passed to the underlying [GestureDetector].
  final HitTestBehavior behavior;

  /// Whether to play the platform tap sound / haptic.
  final bool enableFeedback;

  @override
  State<ZvTapScale> createState() => _ZvTapScaleState();
}

class _ZvTapScaleState extends State<ZvTapScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final target = _pressed ? widget.scale : 1.0;

    Widget result = AnimatedScale(
      scale: interactive ? target : 1.0,
      duration: context.motion(AppMotion.instant),
      curve: context.motionCurve(AppMotion.standard),
      child: widget.child,
    );

    if (interactive) {
      result = GestureDetector(
        behavior: widget.behavior,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.enableFeedback) Feedback.forTap(context);
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: result,
      );
      result = Semantics(
        button: true,
        label: widget.semanticLabel,
        child: result,
      );
    }

    return result;
  }
}
