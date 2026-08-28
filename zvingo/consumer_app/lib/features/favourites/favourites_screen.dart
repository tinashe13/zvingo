import 'package:consumer_app/common/widgets/app_ui.dart';
import 'package:consumer_app/features/favourites/favourites_provider.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favouriteIds = ref.watch(favouritesProvider);
    final allRestaurants = ref.watch(restaurantListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved stores'),
      ),
      body: allRestaurants.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (restaurants) {
          final favRestaurants =
              restaurants.where((r) => favouriteIds.contains(r.id)).toList();

          if (favRestaurants.isEmpty) {
            return AppEmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'No saved stores yet',
              message: 'Tap the heart on a restaurant to keep it close.',
              action: ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Explore restaurants'),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
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
