import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

/// Offers tab — replaces Search tab per article Experience 1
class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantsAsync = ref.watch(restaurantListProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Offers & Deals',
                    style: AppTextStyles.headlineMedium),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'Best deals from your favourite restaurants',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),

            // Show restaurants with promotions
            restaurantsAsync.when(
              data: (restaurants) {
                final withDeals = restaurants
                    .where((r) =>
                        r.promotions.isNotEmpty || r.deliveryFee == 0)
                    .toList();

                if (withDeals.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Lottie.asset(
                            'assets/animations/no_results.json',
                            width: 150,
                            height: 150,
                          ),
                          const SizedBox(height: 16),
                          Text('No deals right now',
                              style: AppTextStyles.titleMedium),
                          const SizedBox(height: 6),
                          Text('Check back soon for offers!',
                              style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final r = withDeals[index];
                      return Column(
                        children: [
                          // Deal badge
                          if (r.promotions.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(12)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_offer,
                                      size: 16, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      r.promotions.first,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.primaryDark,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          RestaurantCard(
                            restaurant: r,
                            onTap: () =>
                                context.push('/restaurant/${r.id}'),
                          ),
                        ],
                      );
                    },
                    childCount: withDeals.length,
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const SliverFillRemaining(
                child: Center(child: Text('Could not load offers')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
