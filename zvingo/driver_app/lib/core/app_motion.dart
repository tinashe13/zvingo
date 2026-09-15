import 'package:flutter/material.dart';

/// Zvingo motion tokens — driver surface.
///
/// Normative source: `docs/DESIGN_SYSTEM.md` §4. Identifier names match
/// `consumer_app/lib/core/app_motion.dart` (§6).
///
/// Motion explains, never decorates. Every animation in this app must
/// communicate causality (this caused that), continuity (this is the same
/// object) or state (this changed). If it does none of the three, delete it.
///
/// Reduced motion is not optional: resolve every duration through
/// [durationOf] / [resolve] so that a driver who has switched animations off
/// at the OS level gets a plain cross-fade instead of movement (§4.4).
class AppMotion {
  AppMotion._();

  // ───────────────────────────────────────────────────────────────────────
  // §4.1 Duration
  // ───────────────────────────────────────────────────────────────────────

  /// 100ms — tap feedback, checkbox, toggle thumb.
  static const Duration instant = Duration(milliseconds: 100);

  /// 180ms — hover, colour change, chip select, icon swap.
  static const Duration fast = Duration(milliseconds: 180);

  /// 260ms — card enter, list stagger item, sheet snap.
  static const Duration base = Duration(milliseconds: 260);

  /// 400ms — page transition, sheet open/close, hero expand.
  static const Duration slow = Duration(milliseconds: 400);

  /// 700ms — status-step progression, success celebration.
  static const Duration deliberate = Duration(milliseconds: 700);

  /// 40ms — the per-item delay in a staggered list entrance (§4.3).
  static const Duration staggerStep = Duration(milliseconds: 40);

  /// Later items animate together rather than trailing forever (§4.3).
  static const int staggerCap = 8;

  // ───────────────────────────────────────────────────────────────────────
  // §4.2 Easing
  // ───────────────────────────────────────────────────────────────────────

  /// `cubic-bezier(0.2, 0, 0, 1)` — the default for everything.
  static const Curve standard = Curves.easeOutCubic;

  /// `cubic-bezier(0.05, 0.7, 0.1, 1)` — elements entering the screen.
  static const Curve enter = Curves.easeOutQuint;

  /// `cubic-bezier(0.3, 0, 1, 1)` — elements leaving the screen.
  static const Curve exit = Curves.easeInCubic;

  /// Playful confirmations only — offer accepted, delivery completed.
  /// Never on a routine state change.
  static const Curve spring = Curves.easeOutBack;

  /// Snap-back of a slide-to-confirm thumb that was released short of the
  /// threshold. Overshoots slightly so the control feels sprung, not dead.
  static const Curve snapBack = Curves.easeOutBack;

  // ───────────────────────────────────────────────────────────────────────
  // §4.3 Entrance geometry
  // ───────────────────────────────────────────────────────────────────────

  /// List items rise 12px as they fade in.
  static const double riseOffset = 12;

  /// A forward page slides in 24px from the right.
  static const double pageSlideOffset = 24;

  /// Every tappable surface scales to 0.985 on press (§4.3, no exceptions).
  static const double tapScale = 0.985;

  // ───────────────────────────────────────────────────────────────────────
  // §4.4 Reduced motion
  // ───────────────────────────────────────────────────────────────────────

  /// True when the platform asks for reduced motion.
  ///
  /// Callers should keep showing the *result* of an animation — never gate
  /// interaction behind one.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The duration to actually use for [duration] on this device.
  ///
  /// With reduced motion on, everything collapses to a [fast] cross-fade so
  /// the change is still perceivable but nothing travels.
  static Duration durationOf(BuildContext context, Duration duration) =>
      reduced(context) ? fast : duration;

  /// The curve to actually use for [curve] on this device.
  static Curve curveOf(BuildContext context, Curve curve) =>
      reduced(context) ? Curves.linear : curve;

  /// The translation distance to actually use on this device — zero when the
  /// driver has reduced motion enabled, which turns a slide into a fade.
  static double offsetOf(BuildContext context, double offset) =>
      reduced(context) ? 0 : offset;

  /// The scale factor for a tap, honouring reduced motion.
  static double tapScaleOf(BuildContext context) =>
      reduced(context) ? 1.0 : tapScale;

  /// Resolve a full (duration, curve, offset) triple in one call.
  static ({Duration duration, Curve curve, double offset}) resolve(
    BuildContext context, {
    Duration duration = base,
    Curve curve = standard,
    double offset = 0,
  }) {
    if (reduced(context)) {
      return (duration: fast, curve: Curves.linear, offset: 0);
    }
    return (duration: duration, curve: curve, offset: offset);
  }

  // ───────────────────────────────────────────────────────────────────────
  // Stagger helper
  // ───────────────────────────────────────────────────────────────────────

  /// Delay before item [index] of a staggered list begins animating.
  ///
  /// 40ms per item, capped at the 8th so a long list does not take a second
  /// and a half to finish appearing. Returns [Duration.zero] under reduced
  /// motion.
  static Duration staggerDelay(BuildContext context, int index) {
    if (reduced(context)) return Duration.zero;
    final clamped = index.clamp(0, staggerCap);
    return staggerStep * clamped;
  }

  /// Interval within a single controller covering item [index] of [count],
  /// for callers driving a whole list from one [AnimationController].
  static Interval staggerInterval(int index, int count) {
    if (count <= 1) return const Interval(0, 1, curve: enter);
    final capped = index.clamp(0, staggerCap);
    final span = 1 / (staggerCap + 1);
    final start = (capped * span * 0.6).clamp(0.0, 0.6);
    return Interval(start, (start + 0.4).clamp(0.0, 1.0), curve: enter);
  }
}

/// Fades and rises a child into place once, with an optional stagger delay.
///
/// This is the §4.3 "list entrance" pattern in one widget: 12px rise + fade
/// over `motion/base` with `ease/enter`, staggered 40ms per item and capped at
/// the 8th. Under reduced motion it degrades to a plain cross-fade.
///
/// ```dart
/// ListView.builder(
///   itemBuilder: (context, i) => StaggeredEntrance(
///     index: i,
///     child: OfferCard(...),
///   ),
/// )
/// ```
class StaggeredEntrance extends StatefulWidget {
  /// Position in the list; drives the stagger delay.
  final int index;

  /// The content to reveal.
  final Widget child;

  /// Override the animation duration. Defaults to `motion/base`.
  final Duration duration;

  /// Distance the child rises as it fades in. Defaults to 12px.
  final double offset;

  const StaggeredEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = AppMotion.base,
    this.offset = AppMotion.riseOffset,
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    _controller.duration = AppMotion.durationOf(context, widget.duration);
    final delay = AppMotion.staggerDelay(context, widget.index);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rise = AppMotion.offsetOf(context, widget.offset);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.curveOf(context, AppMotion.enter),
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, rise * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
