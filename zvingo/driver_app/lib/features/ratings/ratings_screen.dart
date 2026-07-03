import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_colors.dart';
import '../../providers/ratings_provider.dart';

/// RatingsScreen — overall rating, metrics, feedback.
/// Port of RatingsScreen.kt.
class RatingsScreen extends ConsumerWidget {
  const RatingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratings = ref.watch(ratingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ratings')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ratingsProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Overall Rating Card ─────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryHover],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    ratings.overallRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      return Icon(
                        i < ratings.overallRating.round()
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.white,
                        size: 24,
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${ratings.lifetimeDeliveries} lifetime deliveries',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Metric Cards Grid ───────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _MetricCard(
                  label: 'Acceptance Rate',
                  value: '${ratings.acceptanceRate.toStringAsFixed(0)}%',
                  icon: Icons.check_circle_outline,
                  color: AppColors.success,
                ),
                _MetricCard(
                  label: 'Completion Rate',
                  value: '${ratings.completionRate.toStringAsFixed(0)}%',
                  icon: Icons.verified_outlined,
                  color: AppColors.info,
                ),
                _MetricCard(
                  label: 'On-time Rate',
                  value: '${ratings.onTimeRate.toStringAsFixed(0)}%',
                  icon: Icons.schedule,
                  color: AppColors.warning,
                ),
                _MetricCard(
                  label: 'Deliveries',
                  value: '${ratings.lifetimeDeliveries}',
                  icon: Icons.local_shipping_outlined,
                  color: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Recent Feedback ─────────────────────────
            Text(
              'Recent Feedback',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            ...ratings.recentFeedback.map((fb) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            fb.customerName,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(5, (i) {
                              return Icon(
                                i < fb.rating.round()
                                    ? Icons.star
                                    : Icons.star_border,
                                color: AppColors.warning,
                                size: 16,
                              );
                            }),
                          ),
                        ],
                      ),
                      if (fb.comment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          fb.comment,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        fb.date,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
