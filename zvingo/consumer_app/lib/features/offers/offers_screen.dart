import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/common/widgets/app_ui.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Offers tab — replaces Search tab per article Experience 1
class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantsAsync = ref.watch(restaurantListProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: AppPageTitle(
                eyebrow: 'Save on your next meal',
                title: 'Offers',
                subtitle: 'Fresh deals, free delivery and member-only value.',
              ),
            ),

            // Show restaurants with promotions
            restaurantsAsync.when(
              data: (restaurants) {
                final withDeals = restaurants
                    .where((r) => r.promotions.isNotEmpty || r.deliveryFee == 0)
                    .toList();

                if (withDeals.isEmpty) {
                  return const SliverFillRemaining(
                    child: AppEmptyState(
                      icon: Icons.local_offer_outlined,
                      title: 'No offers right now',
                      message: 'New restaurant promotions will appear here.',
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
                              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.accentSurface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_offer_rounded,
                                      size: 17, color: AppColors.textPrimary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      r.promotions.first,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w800,
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
                            onTap: () => context.push('/restaurant/${r.id}'),
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
