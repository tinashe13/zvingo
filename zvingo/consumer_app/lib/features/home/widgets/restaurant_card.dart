import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:consumer_app/features/favourites/favourites_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// DoorDash-style Restaurant Card
class RestaurantCard extends ConsumerWidget {
  final Restaurant restaurant;
  final VoidCallback? onTap;

  const RestaurantCard({
    super.key,
    required this.restaurant,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(favouritesProvider).contains(restaurant.id);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Banner Image ──────────────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: (restaurant.bannerUrl.isNotEmpty ||
                            restaurant.imageUrl.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: restaurant.bannerUrl.isNotEmpty
                                ? restaurant.bannerUrl
                                : restaurant.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: AppColors.primarySurface,
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.primarySurface,
                              child: const Icon(Icons.restaurant,
                                  size: 40, color: AppColors.textHint),
                            ),
                          )
                        : Container(
                            color: AppColors.primarySurface,
                            child: const Icon(Icons.restaurant,
                                size: 40, color: AppColors.textHint),
                          ),
                  ),
                ),

                // Delivery Time Pill (Top Right)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time_filled, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          restaurant.deliveryTime,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Favourite heart (Top Left)
                Positioned(
                  top: 12,
                  left: 12,
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(favouritesProvider.notifier).toggle(restaurant.id),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        size: 18,
                        color: isFav ? AppColors.error : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),

                // Zvingo+ badge (Bottom Left)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified, size: 12, color: Colors.white),
                        const SizedBox(width: 3),
                        Text('Zvingo+',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Info Section ──────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Rating badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              restaurant.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                 fontSize: 12,
                                 fontWeight: FontWeight.bold,
                                 color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.star, size: 12, color: AppColors.rating),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Category + Distance subtitle
                  Text(
                    '${restaurant.category}${restaurant.distanceMi != null ? ' \u00B7 ${restaurant.distanceMi!.toStringAsFixed(1)} mi' : ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Delivery fee + Neighbors liked row
                  Row(
                    children: [
                      // Delivery Fee Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: restaurant.deliveryFee == 0
                              ? AppColors.primarySurface
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          restaurant.deliveryFee == 0
                              ? 'Free Delivery'
                              : '\$${restaurant.deliveryFee.toStringAsFixed(2)} Delivery',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: restaurant.deliveryFee == 0
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      // Neighbors liked
                      if (restaurant.neighborsLiked != null && restaurant.neighborsLiked! > 0) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.people_outline, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text(
                          '${restaurant.neighborsLiked} neighbors liked',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Restaurant Address
                  if (restaurant.address.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            restaurant.address,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
