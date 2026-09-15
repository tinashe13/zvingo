import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import 'driver_buttons.dart';

/// What the slide is about to do. Drives the track colour and the glyph.
///
/// Colour is never the only signal — each value also changes the thumb icon
/// and the label, so the control stays readable for colourblind drivers
/// (§1.5).
enum SlideAction {
  /// Neutral forward progress — "Slide to start", "Slide to continue".
  proceed,

  /// Arriving somewhere: at the merchant, at the customer.
  arrive,

  /// Taking custody of the order.
  pickup,

  /// The delivery is done. The one genuinely celebratory moment in the flow.
  deliver,

  /// Something the driver cannot undo and probably regrets — unassigning,
  /// cancelling. Red track.
  danger,
}

/// Slide-to-confirm — the driver app's high-stakes confirmation control.
///
/// Every irreversible step in the delivery flow (arrived, picked up,
/// delivered) goes through this rather than a tap, because a tap is one pocket
/// brush or one pothole away from firing by accident.
///
/// What it does:
/// * **Two haptics.** A medium impact the moment the thumb crosses the commit
///   threshold, so the driver feels "this will fire" without looking, and a
///   heavy impact on completion.
/// * **Spring snap-back.** Released short of the threshold, the thumb springs
///   home on `ease/spring` rather than teleporting.
/// * **A looping arrow hint.** Three chevrons breathe rightward under the
///   label, at a speed slow enough not to distract. It stops the moment the
///   driver starts dragging, and never runs under reduced motion.
/// * **Semantic colour.** [action] picks the track colour *and* the icon.
/// * **A visible disabled reason.** A dead, unexplained slider is the worst
///   possible dead end mid-delivery, so [disabledReason] renders beneath it.
/// * **An accessible fallback.** When the platform reports accessible
///   navigation (TalkBack / VoiceOver) a drag gesture is unusable, so the
///   control renders as a plain confirm button instead of a slider.
///
/// ```dart
/// DriverSlideToConfirm(
///   text: 'Slide to confirm delivery',
///   action: SlideAction.deliver,
///   isLoading: state.isSubmitting,
///   enabled: pinEntered,
///   disabledReason: 'Enter the 4-digit code from the customer first.',
///   onConfirm: () => ref.read(deliveryProvider.notifier).completeDelivery(),
/// )
/// ```
class DriverSlideToConfirm extends StatefulWidget {
  /// The instruction inside the track. Always starts with "Slide to…".
  final String text;

  /// Fired once, when the thumb is released past the commit threshold.
  final VoidCallback onConfirm;

  /// Semantics of the action, driving colour and glyph.
  final SlideAction action;

  /// When false the control is inert. Supply [disabledReason] with it.
  final bool enabled;

  /// Shows a spinner in the thumb and blocks dragging while a request is in
  /// flight.
  final bool isLoading;

  /// Plain-language explanation rendered under a disabled track.
  final String? disabledReason;

  /// Label shown once the slide has completed. Defaults to "Confirmed".
  final String confirmedLabel;

  /// Fraction of the track the thumb must pass to commit. Defaults to 0.82.
  final double threshold;

  const DriverSlideToConfirm({
    super.key,
    required this.text,
    required this.onConfirm,
    this.action = SlideAction.proceed,
    this.enabled = true,
    this.isLoading = false,
    this.disabledReason,
    this.confirmedLabel = 'Confirmed',
    this.threshold = 0.82,
  });

  @override
  State<DriverSlideToConfirm> createState() => _DriverSlideToConfirmState();
}

/// Backwards-compatible alias. New code should use [DriverSlideToConfirm].
typedef SlideToConfirm = DriverSlideToConfirm;

class _DriverSlideToConfirmState extends State<DriverSlideToConfirm>
    with TickerProviderStateMixin {
  /// Current thumb offset in logical pixels from the left edge of the track.
  double _drag = 0;

  /// Width available for the thumb to travel, measured in `build`.
  double _maxDrag = 1;

  bool _dragging = false;
  bool _confirmed = false;
  bool _pastThreshold = false;

  /// Drives the looping chevron hint.
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Drives the spring snap-back and the snap-to-end on commit.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );
  Animation<double>? _settleAnim;

  static const double _thumbInset = 4;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      final value = _settleAnim?.value;
      if (value != null && mounted) setState(() => _drag = value);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHint();
  }

  @override
  void didUpdateWidget(covariant DriverSlideToConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.isLoading != widget.isLoading) {
      _syncHint();
    }
  }

  void _syncHint() {
    final shouldRun = widget.enabled &&
        !widget.isLoading &&
        !_confirmed &&
        !_dragging &&
        !AppMotion.reduced(context);
    if (shouldRun && !_hint.isAnimating) {
      _hint.repeat();
    } else if (!shouldRun && _hint.isAnimating) {
      _hint.stop();
      _hint.value = 0;
    }
  }

  @override
  void dispose() {
    _hint.dispose();
    _settle.dispose();
    super.dispose();
  }

  bool get _interactive =>
      widget.enabled && !widget.isLoading && !_confirmed;

  void _animateTo(double target, {required Curve curve}) {
    _settleAnim = Tween<double>(begin: _drag, end: target).animate(
      CurvedAnimation(
        parent: _settle,
        curve: AppMotion.curveOf(context, curve),
      ),
    );
    _settle
      ..duration = AppMotion.durationOf(context, AppMotion.base)
      ..forward(from: 0);
  }

  void _onDragStart(DragStartDetails _) {
    _settle.stop();
    setState(() {
      _dragging = true;
      _pastThreshold = false;
    });
    _syncHint();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_drag + details.delta.dx).clamp(0.0, _maxDrag);
    final commitAt = _maxDrag * widget.threshold;

    // One medium impact the instant the slide becomes committable, and one
    // light tick if the driver backs off again — the control talks to the
    // hand, not the eye.
    if (!_pastThreshold && next >= commitAt) {
      _pastThreshold = true;
      HapticFeedback.mediumImpact();
    } else if (_pastThreshold && next < commitAt) {
      _pastThreshold = false;
      HapticFeedback.selectionClick();
    }

    setState(() => _drag = next);
  }

  void _onDragEnd(DragEndDetails _) {
    setState(() => _dragging = false);
    final commitAt = _maxDrag * widget.threshold;

    if (_drag >= commitAt) {
      setState(() => _confirmed = true);
      HapticFeedback.heavyImpact();
      _animateTo(_maxDrag, curve: AppMotion.standard);
      _syncHint();
      widget.onConfirm();
    } else {
      // Spring home. `ease/spring` overshoots slightly so the control feels
      // sprung rather than dead.
      _animateTo(0, curve: AppMotion.snapBack);
      _syncHint();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);

    // Accessible fallback: a drag target is unusable under a screen reader, so
    // swap in an ordinary button that does exactly the same thing (§4.4).
    if (MediaQuery.accessibleNavigationOf(context)) {
      return _withReason(
        context,
        DriverButton(
          label: widget.text.replaceFirst(
            RegExp(r'^slide to ', caseSensitive: false),
            'Confirm: ',
          ),
          icon: palette.icon,
          isLoading: widget.isLoading,
          onPressed: _interactive
              ? () {
                  HapticFeedback.heavyImpact();
                  setState(() => _confirmed = true);
                  widget.onConfirm();
                }
              : null,
          variant: palette.buttonVariant,
        ),
      );
    }

    final track = LayoutBuilder(
      builder: (context, constraints) {
        const thumb = AppSpacing.slideTrackHeight - _thumbInset * 2;
        _maxDrag =
            (constraints.maxWidth - thumb - _thumbInset * 2).clamp(1.0, 4000.0);
        final progress = (_drag / _maxDrag).clamp(0.0, 1.0);

        return Semantics(
          label: widget.text,
          hint: 'Slide right to confirm',
          button: true,
          enabled: _interactive,
          onTap: _interactive
              ? () {
                  setState(() => _confirmed = true);
                  widget.onConfirm();
                }
              : null,
          child: SizedBox(
            height: AppSpacing.slideTrackHeight,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // ── Track ──────────────────────────────────────────────
                AnimatedContainer(
                  duration: AppMotion.durationOf(context, AppMotion.fast),
                  height: AppSpacing.slideTrackHeight,
                  decoration: BoxDecoration(
                    color: palette.track,
                    borderRadius: AppSpacing.brFull,
                    border: Border.all(color: palette.trackBorder),
                  ),
                ),

                // ── Fill that follows the thumb ────────────────────────
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: AppSpacing.brFull,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (progress * 1.05).clamp(0.0, 1.0),
                        child: ColoredBox(color: palette.fill),
                      ),
                    ),
                  ),
                ),

                // ── Label + chevron hint ───────────────────────────────
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Opacity(
                        // The label recedes as the thumb covers it.
                        opacity: (1 - progress * 1.4).clamp(0.0, 1.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _confirmed ? widget.confirmedLabel : widget.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.slideLabel
                                    .copyWith(color: palette.label),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _ChevronHint(
                              animation: _hint,
                              color: palette.label,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Thumb ──────────────────────────────────────────────
                Positioned(
                  left: _thumbInset + _drag,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: _interactive ? _onDragStart : null,
                    onHorizontalDragUpdate: _interactive ? _onDragUpdate : null,
                    onHorizontalDragEnd: _interactive ? _onDragEnd : null,
                    child: Container(
                      width: thumb,
                      height: thumb,
                      decoration: BoxDecoration(
                        color: palette.thumb,
                        shape: BoxShape.circle,
                        boxShadow: AppSpacing.shadowSmOf(context),
                      ),
                      child: Center(
                        child: widget.isLoading
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    palette.onThumb,
                                  ),
                                ),
                              )
                            : Icon(
                                _confirmed ? Icons.check_rounded : palette.icon,
                                color: palette.onThumb,
                                size: 28,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return _withReason(context, track);
  }

  /// Renders [child] with the disabled explanation beneath it when relevant.
  Widget _withReason(BuildContext context, Widget child) {
    if (widget.enabled || widget.disabledReason == null) return child;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
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
                widget.disabledReason!,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.warningOf(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  _SlidePalette _palette(BuildContext context) {
    if (!widget.enabled) {
      return _SlidePalette(
        track: AppColors.surfaceMutedOf(context),
        trackBorder: AppColors.borderOf(context),
        fill: Colors.transparent,
        thumb: AppColors.surfaceMutedOf(context),
        onThumb: AppColors.neutral400,
        label: AppColors.neutral400,
        icon: Icons.lock_outline,
        buttonVariant: DriverButtonVariant.secondary,
      );
    }

    final (Color accent, IconData icon, DriverButtonVariant variant) =
        switch (widget.action) {
      SlideAction.proceed => (
          AppColors.actionOf(context),
          Icons.arrow_forward_rounded,
          DriverButtonVariant.primary,
        ),
      SlideAction.arrive => (
          AppColors.infoOf(context),
          Icons.place_rounded,
          DriverButtonVariant.primary,
        ),
      SlideAction.pickup => (
          AppColors.actionOf(context),
          Icons.shopping_bag_rounded,
          DriverButtonVariant.primary,
        ),
      SlideAction.deliver => (
          AppColors.successOf(context),
          Icons.check_circle_rounded,
          DriverButtonVariant.positive,
        ),
      SlideAction.danger => (
          AppColors.errorOf(context),
          Icons.warning_amber_rounded,
          DriverButtonVariant.destructive,
        ),
    };

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _SlidePalette(
      track: AppColors.surfaceMutedOf(context),
      trackBorder: AppColors.borderOf(context),
      fill: accent.withValues(alpha: isDark ? 0.28 : 0.14),
      thumb: accent,
      onThumb: _onColorFor(accent, isDark),
      label: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
      icon: icon,
      buttonVariant: variant,
    );
  }

  Color _onColorFor(Color accent, bool isDark) {
    // The dark-mode action ramp is near-white, so its label must be dark.
    if (isDark && accent == AppColors.darkAction) return AppColors.neutral900;
    if (isDark && accent == AppColors.darkSuccess) return AppColors.neutral900;
    if (isDark && accent == AppColors.darkError) return AppColors.neutral900;
    if (isDark && accent == AppColors.darkInfo) return AppColors.neutral900;
    return AppColors.textOnDark;
  }
}

class _SlidePalette {
  final Color track;
  final Color trackBorder;
  final Color fill;
  final Color thumb;
  final Color onThumb;
  final Color label;
  final IconData icon;
  final DriverButtonVariant buttonVariant;

  const _SlidePalette({
    required this.track,
    required this.trackBorder,
    required this.fill,
    required this.thumb,
    required this.onThumb,
    required this.label,
    required this.icon,
    required this.buttonVariant,
  });
}

/// Three chevrons that breathe rightward, telling the driver which way to
/// push without a word of copy. Stops entirely when [animation] is idle.
class _ChevronHint extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const _ChevronHint({required this.animation, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each chevron peaks 0.18 of a cycle after the one before it.
            final phase = (animation.value - i * 0.18) % 1.0;
            final intensity = phase < 0.5 ? (1 - phase * 2) : 0.0;
            return Opacity(
              opacity: 0.25 + 0.6 * intensity,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: color,
              ),
            );
          }),
        );
      },
    );
  }
}
