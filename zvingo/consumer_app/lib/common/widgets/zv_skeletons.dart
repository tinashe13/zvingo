import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_spacing.dart';

/// Wraps a tree of [ZvSkeletonBox]es in the standard shimmer sweep.
///
/// §4.3: **skeletons, not spinners.** Any load expected to take more than
/// 300ms shows a shimmer skeleton that matches the real content's layout. A
/// bare `CircularProgressIndicator` filling a screen is a bug; spinners are
/// legal only inside a button during submit.
///
/// Under reduced motion the sweep is disabled and the blocks render as flat
/// placeholders.
///
/// ```dart
/// ZvShimmer(
///   child: Column(children: [ZvSkeletonBox(height: 20, width: 140)]),
/// )
/// ```
class ZvShimmer extends StatelessWidget {
  const ZvShimmer({super.key, required this.child, this.enabled = true});

  /// The skeleton layout to sweep.
  final Widget child;

  /// Set false to freeze the sweep (e.g. inside a screenshot test).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!enabled || reduceMotion) {
      return IgnorePointer(
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.transparent),
          child: child,
        ),
      );
    }
    return IgnorePointer(
      child: Shimmer.fromColors(
        baseColor: AppColors.shimmerBase,
        highlightColor: AppColors.shimmerHighlight,
        period: const Duration(milliseconds: 1400),
        child: child,
      ),
    );
  }
}

/// One grey block inside a [ZvShimmer]. Give it the same size as the real
/// content it stands in for.
class ZvSkeletonBox extends StatelessWidget {
  const ZvSkeletonBox({
    super.key,
    this.height = 14,
    this.width,
    this.radius = AppRadius.sm,
    this.margin = EdgeInsets.zero,
  });

  /// Block height.
  final double height;

  /// Block width. Null stretches to the parent's width.
  final double? width;

  /// Corner radius.
  final double radius;

  /// Outer margin.
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.shimmerBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A block of [lines] skeleton text rows, the last one short like real prose.
class ZvSkeletonText extends StatelessWidget {
  const ZvSkeletonText({
    super.key,
    this.lines = 3,
    this.lineHeight = 12,
    this.gap = AppSpacing.xs,
    this.lastLineFraction = 0.55,
  });

  /// How many rows to draw.
  final int lines;

  /// Height of each row.
  final double lineHeight;

  /// Vertical gap between rows.
  final double gap;

  /// Width of the final row as a fraction of the full width.
  final double lastLineFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double full =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 240.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(lines, (i) {
            final isLast = i == lines - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : gap),
              child: ZvSkeletonBox(
                height: lineHeight,
                width: isLast ? full * lastLineFraction : full,
              ),
            );
          }),
        );
      },
    );
  }
}

/// Layout-matched skeleton for a restaurant card (16:9 image + title + meta).
/// Mirrors `ZvImageCard` with [ZvImageCardRatio.landscape].
class ZvRestaurantCardSkeleton extends StatelessWidget {
  const ZvRestaurantCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ZvShimmer(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.shimmerBase),
                child: SizedBox.expand(),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZvSkeletonBox(height: 17, width: 180),
                  SizedBox(height: AppSpacing.xs),
                  ZvSkeletonBox(height: 13, width: 120),
                  SizedBox(height: AppSpacing.sm),
                  ZvSkeletonBox(height: 13, width: 88),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout-matched skeleton for a compact horizontal card (a "near you" rail).
class ZvCompactCardSkeleton extends StatelessWidget {
  const ZvCompactCardSkeleton({super.key, this.width = 160});

  /// Card width — match the real rail.
  final double width;

  @override
  Widget build(BuildContext context) {
    return ZvShimmer(
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: width,
              child: const AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.shimmerBase,
                    borderRadius: AppRadius.lgAll,
                  ),
                  child: SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const ZvSkeletonBox(height: 14, width: 110),
            const SizedBox(height: AppSpacing.xxs + 2),
            const ZvSkeletonBox(height: 11, width: 64),
          ],
        ),
      ),
    );
  }
}

/// Layout-matched skeleton for a list tile (leading square + two text rows).
class ZvListTileSkeleton extends StatelessWidget {
  const ZvListTileSkeleton({super.key, this.leadingSize = 44});

  /// Size of the square leading block.
  final double leadingSize;

  @override
  Widget build(BuildContext context) {
    return ZvShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            ZvSkeletonBox(
              height: leadingSize,
              width: leadingSize,
              radius: AppRadius.md,
            ),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ZvSkeletonBox(height: 15, width: 160),
                  SizedBox(height: AppSpacing.xs),
                  ZvSkeletonBox(height: 12, width: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout-matched skeleton for a menu-item row (text left, 1:1 thumb right).
class ZvMenuItemSkeleton extends StatelessWidget {
  const ZvMenuItemSkeleton({super.key, this.thumbSize = 84});

  /// Size of the square thumbnail block.
  final double thumbSize;

  @override
  Widget build(BuildContext context) {
    return ZvShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ZvSkeletonBox(height: 16, width: 170),
                  SizedBox(height: AppSpacing.xs),
                  ZvSkeletonBox(height: 12, width: double.infinity),
                  SizedBox(height: AppSpacing.xxs + 2),
                  ZvSkeletonBox(height: 12, width: 140),
                  SizedBox(height: AppSpacing.sm),
                  ZvSkeletonBox(height: 15, width: 62),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ZvSkeletonBox(
              height: thumbSize,
              width: thumbSize,
              radius: AppRadius.md,
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout-matched skeleton for a paragraph-style text block with a heading.
class ZvTextBlockSkeleton extends StatelessWidget {
  const ZvTextBlockSkeleton(
      {super.key, this.lines = 3, this.hasHeading = true});

  /// Number of body rows.
  final int lines;

  /// Draw a wider heading row above the body.
  final bool hasHeading;

  @override
  Widget build(BuildContext context) {
    return ZvShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeading) ...[
            const ZvSkeletonBox(height: 19, width: 150),
            const SizedBox(height: AppSpacing.sm),
          ],
          ZvSkeletonText(lines: lines),
        ],
      ),
    );
  }
}

/// Repeats a skeleton [itemBuilder] [count] times down a column, with the
/// standard 12px list gap. Use it as the `loading` branch of an `AsyncValue`.
///
/// ```dart
/// restaurants.when(
///   loading: () => const ZvSkeletonList(
///     count: 4,
///     itemBuilder: _restaurantSkeleton,
///   ),
///   ...
/// )
/// ```
class ZvSkeletonList extends StatelessWidget {
  const ZvSkeletonList({
    super.key,
    this.count = 4,
    required this.itemBuilder,
    this.gap = AppSpacing.listGap,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  });

  /// Creates a list of [ZvRestaurantCardSkeleton]s — the most common case.
  const ZvSkeletonList.restaurants({
    super.key,
    this.count = 4,
    this.gap = AppSpacing.listGap,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  }) : itemBuilder = _restaurantCard;

  /// Creates a list of [ZvListTileSkeleton]s.
  const ZvSkeletonList.tiles({
    super.key,
    this.count = 6,
    this.gap = 0,
    this.padding = EdgeInsets.zero,
  }) : itemBuilder = _listTile;

  /// Creates a list of [ZvMenuItemSkeleton]s.
  const ZvSkeletonList.menuItems({
    super.key,
    this.count = 5,
    this.gap = 0,
    this.padding = EdgeInsets.zero,
  }) : itemBuilder = _menuItem;

  /// How many skeletons to draw.
  final int count;

  /// Builds one skeleton row.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Vertical gap between rows.
  final double gap;

  /// Padding around the whole list.
  final EdgeInsets padding;

  static Widget _restaurantCard(BuildContext _, int __) =>
      const ZvRestaurantCardSkeleton();

  static Widget _listTile(BuildContext _, int __) => const ZvListTileSkeleton();

  static Widget _menuItem(BuildContext _, int __) => const ZvMenuItemSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(count, (i) {
          return Padding(
            padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : gap),
            child: itemBuilder(context, i),
          );
        }),
      ),
    );
  }
}

/// A horizontally scrolling rail of [ZvCompactCardSkeleton]s, matching a
/// "near you" / "popular" carousel.
class ZvSkeletonRail extends StatelessWidget {
  const ZvSkeletonRail({
    super.key,
    this.count = 4,
    this.cardWidth = 160,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.md),
  });

  /// Number of cards.
  final int count;

  /// Card width — match the real rail.
  final double cardWidth;

  /// Padding around the rail.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: cardWidth * 9 / 16 + 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, __) => ZvCompactCardSkeleton(width: cardWidth),
      ),
    );
  }
}
