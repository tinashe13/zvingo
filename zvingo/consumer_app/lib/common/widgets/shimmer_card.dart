import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_spacing.dart';

import 'zv_skeletons.dart';

/// Legacy alias for [ZvRestaurantCardSkeleton].
///
/// **New code should use `ZvRestaurantCardSkeleton` / `ZvSkeletonList` /
/// `ZvSkeletonRail`** from `zv_skeletons.dart`.
class ShimmerRestaurantCard extends StatelessWidget {
  const ShimmerRestaurantCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: ZvRestaurantCardSkeleton(),
    );
  }
}

/// Legacy alias for [ZvCompactCardSkeleton].
class ShimmerHorizontalCard extends StatelessWidget {
  const ShimmerHorizontalCard({super.key});

  @override
  Widget build(BuildContext context) => const ZvCompactCardSkeleton();
}

/// Legacy alias for `ZvSkeletonList.restaurants`.
class ShimmerRestaurantList extends StatelessWidget {
  const ShimmerRestaurantList({super.key, this.count = 4});

  /// How many skeleton cards to draw.
  final int count;

  @override
  Widget build(BuildContext context) =>
      ZvSkeletonList.restaurants(count: count);
}

/// Legacy alias for [ZvSkeletonRail].
class ShimmerHorizontalRow extends StatelessWidget {
  const ShimmerHorizontalRow({super.key, this.count = 4});

  /// How many skeleton cards to draw.
  final int count;

  @override
  Widget build(BuildContext context) => ZvSkeletonRail(count: count);
}
