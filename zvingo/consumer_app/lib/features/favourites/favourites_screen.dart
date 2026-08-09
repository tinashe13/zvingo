import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/favourites/favourites_provider.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favouriteIds = ref.watch(favouritesProvider);
    final allRestaurants = ref.watch(restaurantListProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        title: const Text('Favourites', style: AppTextStyles.titleLarge),
        centerTitle: true,
      ),
      body: allRestaurants.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (restaurants) {
          final favRestaurants =
              restaurants.where((r) => favouriteIds.contains(r.id)).toList();

          if (favRestaurants.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Lottie.asset(
                    'assets/animations/favourite_heart.json',
                    width: 150,
                    height: 150,
                    repeat: true,
                  ),
                  const SizedBox(height: 16),
                  const Text('No favourites yet', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 6),
                  const Text(
                    'Tap the heart on restaurants\nyou love to save them here',
                    style: AppTextStyles.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8),
            itemCount: favRestaurants.length,
            itemBuilder: (context, index) {
              final r = favRestaurants[index];
              return RestaurantCard(
                restaurant: r,
                onTap: () => context.push('/restaurant/${r.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
