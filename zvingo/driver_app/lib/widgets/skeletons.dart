import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_motion.dart';
import '../core/app_spacing.dart';

/// A shimmering placeholder block.
///
/// §4.3 is explicit: any load expected to take longer than 300ms shows a
/// skeleton that matches the real content's layout. A bare
/// `CircularProgressIndicator` filling a screen is a bug — it tells the driver
/// nothing about what is coming.
///
/// Use the composed skeletons below rather than assembling boxes at call
/// sites, so the placeholder and the real widget stay the same shape when one
/// of them changes.
class SkeletonBox extends StatefulWidget {
  /// Fixed width. Null stretches to the parent, or to [widthFactor] of it.
  final double? width;

  /// Height of the block.
  final double height;

  /// Fraction of the parent's width to occupy, when [width] is null. Use it
  /// for ragged text placeholders (0.6 for a short line, 0.9 for a long one).
  final double? widthFactor;

  /// Corner radius. Defaults to `radius/sm`.
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.widthFactor,
    this.borderRadius = AppSpacing.brSm,
  });

  /// A single line of placeholder text occupying [widthFactor] of the parent.
  const SkeletonBox.line({
    super.key,
    this.widthFactor = 1,
    this.height = 14,
  })  : width = null,
        borderRadius = AppSpacing.brSm;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Nothing flashes more than 3x/second (§4.4); a 1.4s sweep is well under
    // that, and reduced motion stops it entirely.
    if (AppMotion.reduced(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.shimmerBaseOf(context);
    final highlight = AppColors.shimmerHighlightOf(context);

    Widget box = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t), 0),
              colors: [base, highlight, base],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
        );
      },
    );

    final factor = widget.widthFactor;
    if (factor != null && factor < 1) {
      box = FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: factor,
        child: box,
      );
    }

    return ExcludeSemantics(child: box);
  }
}

/// Placeholder matching the layout of an [OfferCard] while a dispatch offer is
/// being fetched or re-hydrated.
class OfferCardSkeleton extends StatelessWidget {
  const OfferCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppSpacing.brSheetTop,
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Countdown bar
          SkeletonBox(height: 6, borderRadius: AppSpacing.brFull),
          SizedBox(height: AppSpacing.xl),
          // Payout hero
          SkeletonBox(width: 190, height: 48),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 110, height: 14),
          SizedBox(height: AppSpacing.xl),
          // Distance / time row
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 56)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: SkeletonBox(height: 56)),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          // Route block
          SkeletonBox(height: 96, borderRadius: AppSpacing.brLg),
          SizedBox(height: AppSpacing.lg),
          // Accept action
          SkeletonBox(
            height: AppSpacing.slideTrackHeight,
            borderRadius: AppSpacing.brFull,
          ),
        ],
      ),
    );
  }
}

/// Placeholder for one row in the earnings list — date, trips, amount.
class EarningsRowSkeleton extends StatelessWidget {
  const EarningsRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppSpacing.brLg,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: const Row(
        children: [
          SkeletonBox(
            width: 44,
            height: 44,
            borderRadius: AppSpacing.brFull,
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 130, height: 15),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 88, height: 12),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.md),
          SkeletonBox(width: 72, height: 22),
        ],
      ),
    );
  }
}

/// Placeholder for a delivery / order history card.
class DeliveryCardSkeleton extends StatelessWidget {
  const DeliveryCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppSpacing.brLg,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 96, height: 22, borderRadius: AppSpacing.brSm),
              Spacer(),
              SkeletonBox(width: 64, height: 22),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(width: 180, height: 16),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 240, height: 13),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(width: 150, height: 13),
        ],
      ),
    );
  }
}

/// A vertical run of [count] skeletons of the same kind, spaced on the list
/// gap token. Saves every loading branch writing its own `ListView`.
///
/// ```dart
/// if (state.isLoading) const SkeletonList(count: 4, builder: EarningsRowSkeleton.new)
/// ```
class SkeletonList extends StatelessWidget {
  /// How many placeholder rows to draw.
  final int count;

  /// Builds one placeholder row.
  final Widget Function() builder;

  /// Gap between rows. Defaults to the 12pt list gap.
  final double gap;

  const SkeletonList({
    super.key,
    this.count = 3,
    required this.builder,
    this.gap = AppSpacing.listGap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) SizedBox(height: gap),
          builder(),
        ],
      ],
    );
  }
}
