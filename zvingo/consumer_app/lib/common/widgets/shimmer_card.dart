import 'package:consumer_app/core/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer placeholder for a restaurant card
class ShimmerRestaurantCard extends StatelessWidget {
  const ShimmerRestaurantCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner
            Container(
              height: 160,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 16, width: 180, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 120, color: Colors.white),
                  const SizedBox(height: 12),
                  Container(height: 12, width: 80, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer placeholder for the horizontal "Fastest Near You" cards
class ShimmerHorizontalCard extends StatelessWidget {
  const ShimmerHorizontalCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: SizedBox(
        width: 155,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120,
              width: 155,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 8),
            Container(height: 14, width: 100, color: Colors.white),
            const SizedBox(height: 4),
            Container(height: 10, width: 60, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// Shimmer loading list — renders n shimmer cards
class ShimmerRestaurantList extends StatelessWidget {
  final int count;
  const ShimmerRestaurantList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const ShimmerRestaurantCard()),
    );
  }
}

/// Shimmer for horizontal scroll row
class ShimmerHorizontalRow extends StatelessWidget {
  final int count;
  const ShimmerHorizontalRow({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => const ShimmerHorizontalCard(),
      ),
    );
  }
}
