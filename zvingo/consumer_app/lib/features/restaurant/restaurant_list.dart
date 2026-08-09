import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class RestaurantListView extends ConsumerWidget {
  const RestaurantListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantsAsync = ref.watch(restaurantListProvider);

    return restaurantsAsync.when(
      data: (restaurants) => restaurants.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.store,
                      size: 48, color: AppColors.primary.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  const Text('No restaurants found',
                      style: AppTextStyles.titleMedium),
                ],
              ),
            )
          : ListView.builder(
              itemCount: restaurants.length,
              padding: const EdgeInsets.only(bottom: 16),
              itemBuilder: (context, index) {
                final restaurant = restaurants[index];
                return RestaurantCard(
                  restaurant: restaurant,
                  onTap: () => context.push('/restaurant/${restaurant.id}'),
                );
              },
            ),
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, stack) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            const Text('Error loading restaurants', style: AppTextStyles.titleMedium),
            const SizedBox(height: 4),
            Text('$err',
                style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
