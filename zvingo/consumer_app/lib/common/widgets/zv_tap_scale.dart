import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_motion.dart';

/// Wraps any child so it scales to **0.985** while pressed, over
/// `motion/instant` (§4.3: "every tappable surface scales to 0.985 — no
/// exceptions").
///
/// Two ways to use it:
///
/// 1. **It owns the tap.** Pass [onTap]; a plain surface becomes tappable.
///    ```dart
///    ZvTapScale(
///      onTap: () => context.push('/restaurant/$id'),
///      child: SomeCustomSurface(),
///    )
///    ```
/// 2. **The child owns the tap** (it already contains an `InkWell` or a
///    Material button). Pass `childHandlesTap: true` and leave [onTap] null.
///    The press is tracked with a [Listener], which never enters the gesture
///    arena, so the child's own tap recogniser still wins and the callback
///    fires exactly once.
///    ```dart
///    ZvTapScale(
///      childHandlesTap: true,
///      child: Material(child: InkWell(onTap: ..., child: ...)),
///    )
///    ```
///
/// `ZvButton`, `ZvCard`, `ZvIconButton` and the other library widgets already
/// apply it, so do not nest one inside another.
class ZvTapScale extends StatefulWidget {
  const ZvTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.childHandlesTap = false,
    this.scale = 0.985,
    this.semanticLabel,
    this.behavior = HitTestBehavior.opaque,
    this.enableFeedback = true,
  });

  /// The surface being made tappable.
  final Widget child;

  /// Tap handler. Leave null when [childHandlesTap] is true.
  final VoidCallback? onTap;

  /// Optional long-press handler.
  final VoidCallback? onLongPress;

  /// The child already recognises taps; only track the press for the scale.
  final bool childHandlesTap;

  /// Pressed scale. Leave at the token value unless you have a reason.
  final double scale;

  /// Screen-reader label describing the action.
  final String? semanticLabel;

  /// Hit-test behaviour for the tap recogniser and the press listener.
  final HitTestBehavior behavior;

  /// Whether to play the platform tap sound / haptic. Ignored when
  /// [childHandlesTap] is true — the child's ink already does it.
  final bool enableFeedback;

  @override
  State<ZvTapScale> createState() => _ZvTapScaleState();
}

class _ZvTapScaleState extends State<ZvTapScale> {
  bool _pressed = false;

  bool get _interactive =>
      widget.childHandlesTap ||
      widget.onTap != null ||
      widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed == value || !_interactive) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    Widget result = AnimatedScale(
      scale: _pressed ? widget.scale : 1.0,
      duration: context.motion(AppMotion.instant),
      curve: context.motionCurve(AppMotion.standard),
      child: widget.child,
    );

    if (!_interactive) return result;

    // Listener sits outside the gesture arena, so it never steals the tap
    // from an InkWell or button inside `child`.
    result = Listener(
      behavior: widget.behavior,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: result,
    );

    if (!widget.childHandlesTap) {
      result = GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.enableFeedback) Feedback.forTap(context);
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: result,
      );
    }

    if (!widget.childHandlesTap || widget.semanticLabel != null) {
      result = Semantics(
        button: !widget.childHandlesTap,
        label: widget.semanticLabel,
        child: result,
      );
    }

    return result;
  }
}
