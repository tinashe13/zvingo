import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';
import '../core/app_text_styles.dart';
import '../models/delivery_state.dart';

/// Where the driver is in the delivery, as a progress rail.
///
/// This is the §4.3 "status progression" pattern: when the state advances the
/// connector between the previous node and the new one *fills* over
/// `motion/deliberate`, and the new node *scales in* behind it. The driver
/// sees the causal link between the action they just confirmed and the
/// progress they earned, rather than a diagram that silently redraws.
///
/// The connectors flex, so all seven steps survive a 320px screen; labels
/// truncate to one line rather than reflowing the rail at large text scales.
///
/// ```dart
/// DeliveryStepIndicator(currentState: delivery.deliveryState)
/// ```
class DeliveryStepIndicator extends StatefulWidget {
  /// The step the driver is on right now.
  final DeliveryState currentState;

  /// Renders labels under each node. Off gives a compact rail for tight
  /// headers.
  final bool showLabels;

  const DeliveryStepIndicator({
    super.key,
    required this.currentState,
    this.showLabels = true,
  });

  /// The ordered steps the rail renders.
  static const List<(String, DeliveryState)> steps = [
    ('Accept', DeliveryState.accepted),
    ('Pickup', DeliveryState.enRoutePickup),
    ('At store', DeliveryState.arrivedPickup),
    ('Collected', DeliveryState.pickedUp),
    ('Deliver', DeliveryState.enRouteDelivery),
    ('Arrived', DeliveryState.arrivedDelivery),
    ('Done', DeliveryState.delivered),
  ];

  /// Index of [state] on the rail, clamped into range.
  static int indexOf(DeliveryState state) {
    final index = steps.indexWhere((s) => s.$2 == state);
    if (index >= 0) return index;
    // `completed` sits past the end of the rail; everything else before it.
    return state == DeliveryState.completed ? steps.length - 1 : 0;
  }

  @override
  State<DeliveryStepIndicator> createState() => _DeliveryStepIndicatorState();
}

class _DeliveryStepIndicatorState extends State<DeliveryStepIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.deliberate,
  );

  late int _from = DeliveryStepIndicator.indexOf(widget.currentState);
  late int _to = _from;

  @override
  void initState() {
    super.initState();
    // The rail arrives already filled to the current step — only *changes*
    // animate, so re-entering a screen does not replay the whole history.
    _controller.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration =
        AppMotion.durationOf(context, AppMotion.deliberate);
  }

  @override
  void didUpdateWidget(covariant DeliveryStepIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = DeliveryStepIndicator.indexOf(widget.currentState);
    if (next != _to) {
      setState(() {
        _from = _to;
        _to = next;
      });
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const steps = DeliveryStepIndicator.steps;
    final done = AppColors.successOf(context);
    final pending = AppColors.borderOf(context);
    final current = AppColors.actionOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Semantics(
      label: 'Delivery progress: step ${_to + 1} of ${steps.length}, '
          '${steps[_to].$1}',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            // Curve applied by value, not by wrapping in a CurvedAnimation:
            // this builder runs every frame and a fresh animation object each
            // time would leak.
            final curve = AppMotion.curveOf(context, AppMotion.standard)
                .transform(_controller.value);
            // Fractional position of the "filled" head of the rail.
            final head = _from + (_to - _from) * curve;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The rail itself. Nodes are fixed and small; the connectors
                // take all remaining width, so the row cannot overflow at any
                // screen size or text scale.
                Row(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0)
                        Expanded(
                          child: _Connector(
                            // Connector i-1→i fills as `head` passes i.
                            fill: (head - (i - 1)).clamp(0.0, 1.0),
                            filledColor: done,
                            trackColor: pending,
                          ),
                        ),
                      _Node(
                        state: i < _to
                            ? _NodeState.done
                            : (i == _to
                                ? _NodeState.current
                                : _NodeState.pending),
                        // A node pops in as the head reaches it.
                        scale: i <= _to
                            ? (0.6 + 0.4 * (head - (i - 1)).clamp(0.0, 1.0))
                                .clamp(0.6, 1.0)
                            : 1.0,
                        doneColor: done,
                        currentColor: current,
                        pendingColor: pending,
                      ),
                    ],
                  ],
                ),
                // One readable line beats seven truncated ones. A driver
                // glancing at this for a second gets the step name at body
                // size instead of seven 10pt words fighting for 40px each.
                if (widget.showLabels) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          steps[_to].$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyStrong.copyWith(
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Step ${_to + 1} of ${steps.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: muted),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _NodeState { done, current, pending }

class _Connector extends StatelessWidget {
  final double fill;
  final Color filledColor;
  final Color trackColor;

  const _Connector({
    required this.fill,
    required this.filledColor,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: AppSpacing.brFull,
                ),
              ),
            ),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fill,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: filledColor,
                    borderRadius: AppSpacing.brFull,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  final _NodeState state;
  final double scale;
  final Color doneColor;
  final Color currentColor;
  final Color pendingColor;

  const _Node({
    required this.state,
    required this.scale,
    required this.doneColor,
    required this.currentColor,
    required this.pendingColor,
  });

  @override
  Widget build(BuildContext context) {
    final (Color color, double size, Widget? glyph) = switch (state) {
      _NodeState.done => (
          doneColor,
          20.0,
          const Icon(Icons.check_rounded, size: 13, color: Colors.white),
        ),
      _NodeState.current => (currentColor, 24.0, null),
      _NodeState.pending => (pendingColor, 14.0, null),
    };

    // A fixed 26px cell keeps the rail's node budget at 7 x 26 = 182px, so
    // the connectors always have room left even on a 320px screen.
    return SizedBox(
      width: 26,
      height: 26,
      child: Center(
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: glyph ??
                (state == _NodeState.current
                    ? Center(
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null),
          ),
        ),
      ),
    );
  }
}
