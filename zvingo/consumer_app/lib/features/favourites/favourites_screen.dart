import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/favourites/favourites_provider.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';

/// The restaurants this customer has hearted.
///
/// Also reachable as "Saved stores" from the account screen — the two are the
/// same list, so there is one screen and one source of truth rather than two
/// half-built ones.
class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favouriteIds = ref.watch(favouritesProvider);
    final syncStatus = ref.watch(favouritesSyncStatusProvider);
    final restaurants = ref.watch(restaurantListProvider);

    return ZvScreen(
      title: 'Saved stores',
      subtitle: favouriteIds.isEmpty
          ? null
          : '${favouriteIds.length} saved '
              '${favouriteIds.length == 1 ? 'store' : 'stores'}',
      fallbackRoute: '/account',
      actions: [
        ZvIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh saved stores',
          loading: syncStatus == FavouritesSync.loading,
          onPressed: () => ref.read(favouritesProvider.notifier).refresh(),
        ),
      ],
      banner: syncStatus == FavouritesSync.failed
          ? const ZvOfflineBanner(
              message: 'Showing your saved stores from this device — we could '
                  'not reach Zvingo to check for changes.',
            )
          : null,
      child: restaurants.when(
        loading: () => const ZvSkeletonList.restaurants(count: 4),
        error: (error, _) => ZvErrorState(
          error: error,
          onRetry: () => ref.invalidate(restaurantListProvider),
        ),
        data: (all) {
          final saved =
              all.where((r) => favouriteIds.contains(r.id)).toList();

          if (saved.isEmpty) {
            return ZvEmptyState(
              icon: Icons.favorite_border_rounded,
              title: favouriteIds.isEmpty
                  ? 'No saved stores yet'
                  : 'Your saved stores are not delivering here',
              message: favouriteIds.isEmpty
                  ? 'Tap the heart on any restaurant and it lands here, ready '
                      'to reorder in two taps.'
                  : 'The stores you saved are not available at your current '
                      'delivery address. Try browsing what is nearby.',
              actionLabel: 'Browse restaurants',
              onAction: () => context.go('/home'),
              secondaryActionLabel: 'See today\'s offers',
              onSecondaryAction: () => context.push('/offers'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(favouritesProvider.notifier).refresh();
              ref.invalidate(restaurantListProvider);
            },
            child: ZvStaggeredListView.builder(
              itemCount: saved.length,
              gap: AppSpacing.xxs,
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.xxl,
              ),
              itemBuilder: (context, index) {
                final restaurant = saved[index];
                return _DismissibleFavourite(
                  key: ValueKey(restaurant.id),
                  restaurantId: restaurant.id,
                  restaurantName: restaurant.name,
                  child: RestaurantCard(
                    restaurant: restaurant,
                    onTap: () => context.push('/restaurant/${restaurant.id}'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Swipe a saved store away, with an Undo that really puts it back (§5.5).
class _DismissibleFavourite extends ConsumerWidget {
  const _DismissibleFavourite({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    required this.child,
  });

  final String restaurantId;
  final String restaurantName;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('dismiss-$restaurantId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: const BoxDecoration(
          color: AppColors.errorSurface,
          borderRadius: AppRadius.lgAll,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.heart_broken_rounded, color: AppColors.error),
            SizedBox(width: AppSpacing.xs),
            Text('Remove',
                style: AppTextStyles.bodyStrong,
                textAlign: TextAlign.right),
          ],
        ),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final notifier = ref.read(favouritesProvider.notifier);
        await notifier.toggle(restaurantId);
        messenger.showSnackBar(
          SnackBar(
            content: Text('$restaurantName removed from saved stores'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => notifier.toggle(restaurantId),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
