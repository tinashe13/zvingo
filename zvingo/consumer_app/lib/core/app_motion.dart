import 'package:flutter/material.dart';

/// Zvingo motion tokens — the Flutter binding of §4 of
/// `docs/DESIGN_SYSTEM.md`.
///
/// Motion explains, it never decorates. Every animation must communicate
/// causality, continuity or state; if it does not, delete it.
///
/// Always resolve a duration through [AppMotion.duration] (or
/// [MotionContext]) so reduced-motion users get a plain cross-fade instead of
/// movement:
///
/// ```dart
/// AnimatedContainer(
///   duration: AppMotion.duration(context, AppMotion.base),
///   curve: AppMotion.enter,
///   ...
/// )
/// ```
class AppMotion {
  AppMotion._();

  // ───────────────────────────────────────────────────────────────────────
  // §4.1 Duration
  // ───────────────────────────────────────────────────────────────────────

  /// 100ms — tap feedback, checkbox, toggle thumb.
  static const Duration instant = Duration(milliseconds: 100);

  /// 180ms — hover, colour change, chip select, icon swap. Also the
  /// replacement duration used when motion is reduced.
  static const Duration fast = Duration(milliseconds: 180);

  /// 260ms — card enter, list stagger item, sheet snap.
  static const Duration base = Duration(milliseconds: 260);

  /// 400ms — page transition, sheet open/close, hero expand.
  static const Duration slow = Duration(milliseconds: 400);

  /// 700ms — status-step progression, success celebration.
  static const Duration deliberate = Duration(milliseconds: 700);

  // ───────────────────────────────────────────────────────────────────────
  // §4.2 Easing
  // ───────────────────────────────────────────────────────────────────────

  /// `cubic-bezier(0.2, 0, 0, 1)` — the default for everything.
  static const Curve standard = Curves.easeOutCubic;

  /// `cubic-bezier(0.05, 0.7, 0.1, 1)` — elements entering the screen.
  static const Curve enter = Curves.easeOutQuint;

  /// `cubic-bezier(0.3, 0, 1, 1)` — elements leaving the screen.
  static const Curve exit = Curves.easeInCubic;

  /// Playful confirmations only (added-to-cart, order placed).
  static const Curve spring = Curves.easeOutBack;

  // ───────────────────────────────────────────────────────────────────────
  // §4.3 List entrance
  // ───────────────────────────────────────────────────────────────────────

  /// Delay added per list item during an entrance stagger.
  static const Duration staggerStep = Duration(milliseconds: 40);

  /// The stagger stops accumulating after this many items — item 8 and every
  /// item after it animate together.
  static const int staggerCap = 8;

  /// Vertical distance an entering list item rises through.
  static const double entranceRise = 12;

  /// The delay for the [index]-th item of a staggered list entrance.
  /// Capped at [staggerCap] items (§4.3).
  static Duration staggerDelay(int index) {
    final capped = index < 0 ? 0 : (index > staggerCap ? staggerCap : index);
    return staggerStep * capped;
  }

  // ───────────────────────────────────────────────────────────────────────
  // §4.4 Accessibility
  // ───────────────────────────────────────────────────────────────────────

  /// True when the platform asks for reduced motion
  /// (`MediaQuery.disableAnimations`).
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Resolves [preferred] against the user's reduced-motion preference.
  ///
  /// With reduced motion on, movement is replaced by a plain cross-fade at
  /// [fast]; durations already at or below [fast] are left alone so tap
  /// feedback stays crisp.
  static Duration duration(BuildContext context, Duration preferred) {
    if (!reduced(context)) return preferred;
    return preferred <= fast ? preferred : fast;
  }

  /// Resolves an offset/scale/slide distance. Returns 0 under reduced motion
  /// so the transition degrades to a cross-fade with no movement.
  static double distance(BuildContext context, double preferred) =>
      reduced(context) ? 0 : preferred;

  /// Resolves a curve. Under reduced motion every curve flattens to
  /// [Curves.linear] so the cross-fade reads as neutral.
  static Curve curve(BuildContext context, Curve preferred) =>
      reduced(context) ? Curves.linear : preferred;

  /// The stagger delay for [index], or [Duration.zero] under reduced motion
  /// (every item cross-fades together).
  static Duration stagger(BuildContext context, int index) =>
      reduced(context) ? Duration.zero : staggerDelay(index);
}

/// Sugar for reading motion tokens off a [BuildContext].
///
/// ```dart
/// AnimatedOpacity(
///   duration: context.motion(AppMotion.base),
///   curve: context.motionCurve(AppMotion.enter),
///   ...
/// )
/// ```
extension MotionContext on BuildContext {
  /// True when the platform asks for reduced motion.
  bool get reducedMotion => AppMotion.reduced(this);

  /// Reduced-motion-aware duration. See [AppMotion.duration].
  Duration motion(Duration preferred) => AppMotion.duration(this, preferred);

  /// Reduced-motion-aware curve. See [AppMotion.curve].
  Curve motionCurve(Curve preferred) => AppMotion.curve(this, preferred);

  /// Reduced-motion-aware travel distance. See [AppMotion.distance].
  double motionDistance(double preferred) =>
      AppMotion.distance(this, preferred);
}

/// Fades and rises a single child into place, staggered by its position in a
/// list (§4.3: 40ms stagger capped at 8 items, fade + 12px rise over
/// `motion/base` with `ease/enter`).
///
/// Prefer `ZvStaggeredList` from the shared widget library, which wraps a whole
/// list for you. Use this directly when the children are not a simple list —
/// for example a `CustomScrollView` whose slivers each need their own delay.
///
/// ```dart
/// ZvEntrance(index: i, child: RestaurantCard(...))
/// ```
class ZvEntrance extends StatefulWidget {
  const ZvEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.enabled = true,
    this.rise = AppMotion.entranceRise,
    this.duration = AppMotion.base,
  });

  /// The widget being animated in.
  final Widget child;

  /// Position of this item in its list — drives the stagger delay.
  final int index;

  /// Set false to render the child immediately with no animation, e.g. when
  /// re-building an already-visible list.
  final bool enabled;

  /// How far the child rises while fading in.
  final double rise;

  /// How long the entrance takes.
  final Duration duration;

  @override
  State<ZvEntrance> createState() => _ZvEntranceState();
}

class _ZvEntranceState extends State<ZvEntrance>
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
    if (!widget.enabled) {
      _controller.value = 1;
      return;
    }
    final delay = AppMotion.stagger(context, widget.index);
    _controller.duration = AppMotion.duration(context, widget.duration);
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
    final rise = AppMotion.distance(context, widget.rise);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.curve(context, AppMotion.enter),
    );
    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, rise * (1 - curved.value)),
            child: child,
          ),
        );
      },
    );
  }
}

/// The §4.3 forward page transition: the incoming page slides in from the
/// right by 24px and fades, over `motion/slow` with `ease/enter`. Back is the
/// reverse. Under reduced motion it degrades to a plain cross-fade.
///
/// Used by `router.dart` for every pushed route; you rarely need it directly.
class ZvPageTransition extends StatelessWidget {
  const ZvPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  /// The route's primary animation.
  final Animation<double> animation;

  /// The animation of the route being covered.
  final Animation<double> secondaryAnimation;

  /// The page being transitioned.
  final Widget child;

  /// How far the incoming page travels (§4.3).
  static const double slideDistance = 24;

  @override
  Widget build(BuildContext context) {
    final travel = AppMotion.distance(context, slideDistance);
    final enterCurve = AppMotion.curve(context, AppMotion.enter);
    final exitCurve = AppMotion.curve(context, AppMotion.exit);

    final fade = CurvedAnimation(parent: animation, curve: enterCurve);
    final enterSlide = Tween<Offset>(
      begin: Offset(travel, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: enterCurve));
    final exitSlide = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(-travel * 0.5, 0),
    ).animate(CurvedAnimation(parent: secondaryAnimation, curve: exitCurve));

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        return Transform.translate(
          offset: exitSlide.value,
          child: Transform.translate(
            offset: enterSlide.value,
            child: Opacity(opacity: fade.value.clamp(0.0, 1.0), child: child),
          ),
        );
      },
    );
  }
}

/// A [PageTransitionsBuilder] that applies [ZvPageTransition] to every
/// `MaterialPageRoute` so Navigator-pushed screens match go_router's.
class ZvPageTransitionsBuilder extends PageTransitionsBuilder {
  /// Creates the Zvingo page transitions builder.
  const ZvPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return ZvPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}
