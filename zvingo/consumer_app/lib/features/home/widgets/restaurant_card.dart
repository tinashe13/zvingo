import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/favourites/favourites_provider.dart';
import 'package:consumer_app/features/home/discovery_provider.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The viewer's text-scale factor, clamped to the range `main.dart` allows.
///
/// Rails and carousels need an explicit height, and a hard-coded one overflows
/// the moment someone turns their system font up. Every fixed height in the
/// discovery surfaces is expressed as `chrome + text * zvTextScale(context)`.
double zvTextScale(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);

/// Height a [RestaurantRailCard] needs at the current text scale.
///
/// Constants measured against the tallest variant (promotion + closed badge)
/// and pinned by `test/discovery_contract_test.dart`, which fails if the card
/// ever outgrows them.
double restaurantRailHeight(BuildContext context, {double width = 176}) =>
    width * 9 / 16 + 40 + 78 * zvTextScale(context);

/// How a restaurant card frames its numbers.
enum RestaurantCardMode {
  /// Delivery: fee and ETA lead, distance is secondary.
  delivery,

  /// Pickup: distance leads, there is no delivery fee at all.
  pickup,
}

/// The tile every discovery surface decides on.
///
/// Shows the six things a person actually chooses between — image, name,
/// rating, delivery time, delivery fee and distance — plus any promotion and
/// an unmissable **closed** state.
///
/// Availability comes from the backend's `availability` block via
/// [DiscoveryRestaurant]; callers that only hold a bare [Restaurant] (e.g.
/// Favourites) still work and simply render without the closed state.
class RestaurantCard extends ConsumerWidget {
  const RestaurantCard({
    super.key,
    required this.restaurant,
    this.onTap,
    this.availability,
    this.distanceKm,
    this.matchedDishes = const <String>[],
    this.mode = RestaurantCardMode.delivery,
    this.margin = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.listGap,
    ),
  });

  /// Unpacks a [DiscoveryRestaurant] — the form every discovery screen has.
  RestaurantCard.discovery(
    DiscoveryRestaurant store, {
    super.key,
    this.onTap,
    this.mode = RestaurantCardMode.delivery,
    this.margin = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.listGap,
    ),
  })  : restaurant = store.restaurant,
        availability = store.availability,
        distanceKm = store.distanceKm,
        matchedDishes = store.matchedDishes;

  final Restaurant restaurant;
  final VoidCallback? onTap;

  /// Live open/closed state. Null means "not known" — never rendered as closed.
  final StoreAvailability? availability;

  /// Straight-line distance from the delivery address, in km.
  final double? distanceKm;

  /// Menu items that matched a search query, shown as "Also serves …".
  final List<String> matchedDishes;

  final RestaurantCardMode mode;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(favouritesProvider).contains(restaurant.id);
    final state = availability ?? StoreAvailability.unknown;
    final closed = state.isKnownClosed;
    final promotion =
        restaurant.promotions.isEmpty ? null : restaurant.promotions.first;
    final distance = _distanceLabel(distanceKm);

    return ZvCard(
      margin: margin,
      padding: EdgeInsets.zero,
      onTap: onTap,
      semanticLabel: _semanticLabel(state, distance, promotion),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Positioned.fill(
                child: ZvNetworkImage(
                  url: restaurant.bannerUrl.isNotEmpty
                      ? restaurant.bannerUrl
                      : restaurant.imageUrl,
                  aspectRatio: 16 / 9,
                  fallbackLabel: restaurant.name,
                  borderRadius: BorderRadius.zero,
                ),
              ),
              if (closed)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.neutral900.withValues(alpha: 0.46),
                  ),
                ),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xxs,
                              children: [
                                if (promotion != null)
                                  ZvBadge.deal(label: _shortPromo(promotion))
                                else if (restaurant.deliveryFee == 0 &&
                                    mode == RestaurantCardMode.delivery)
                                  const ZvBadge(
                                    label: 'Free delivery',
                                    tone: ZvTone.success,
                                    icon: Icons.pedal_bike_rounded,
                                  ),
                                if (restaurant.isZvingoPlus)
                                  const ZvBadge(
                                    label: 'Zvingo+',
                                    icon: Icons.verified_rounded,
                                  ),
                              ],
                            ),
                          ),
                          ZvIconButton(
                            icon: isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            tooltip: isFav
                                ? 'Remove ${restaurant.name} from favourites'
                                : 'Save ${restaurant.name} to favourites',
                            background:
                                AppColors.surface.withValues(alpha: 0.92),
                            foreground: isFav
                                ? AppColors.error
                                : AppColors.textSecondary,
                            onPressed: () => ref
                                .read(favouritesProvider.notifier)
                                .toggle(restaurant.id),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _AvailabilityChip(state: state),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        restaurant.name,
                        style: AppTextStyles.h3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _RatingPill(
                      rating: restaurant.rating,
                      reviewCount: restaurant.reviewCount,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  restaurant.category,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                RestaurantMetaLine(
                  restaurant: restaurant,
                  distanceLabel: distance,
                  mode: mode,
                ),
                if (promotion != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _PromotionLine(text: promotion),
                ],
                if (matchedDishes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Serves ${matchedDishes.take(3).join(' · ')}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _semanticLabel(
    StoreAvailability state,
    String? distance,
    String? promotion,
  ) {
    final parts = <String>[
      restaurant.name,
      '${restaurant.rating.toStringAsFixed(1)} stars',
      if (mode == RestaurantCardMode.delivery)
        restaurant.deliveryTime
      else if (distance != null)
        distance,
      if (state.isKnownClosed) state.closedLabel else 'Open',
      if (promotion != null) promotion,
    ];
    return parts.join(', ');
  }
}

/// Rating, ETA, fee and distance — the row people scan.
///
/// A [Wrap] rather than a fixed row so it reflows instead of overflowing at
/// 320px or 200% text scale.
class RestaurantMetaLine extends StatelessWidget {
  const RestaurantMetaLine({
    super.key,
    required this.restaurant,
    this.distanceLabel,
    this.mode = RestaurantCardMode.delivery,
  });

  final Restaurant restaurant;
  final String? distanceLabel;
  final RestaurantCardMode mode;

  @override
  Widget build(BuildContext context) {
    final pickup = mode == RestaurantCardMode.pickup;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (pickup) ...[
          if (distanceLabel != null)
            ZvMetaItem(
              icon: Icons.directions_walk_rounded,
              label: distanceLabel!,
            ),
          ZvMetaItem(
            icon: Icons.shopping_bag_outlined,
            label: 'Ready in ${restaurant.deliveryTimeMin} min',
          ),
          const ZvMetaItem(
            icon: Icons.savings_outlined,
            label: 'No delivery fee',
            tint: AppColors.success,
          ),
        ] else ...[
          ZvMetaItem(
            icon: Icons.schedule_rounded,
            label: restaurant.deliveryTime,
          ),
          ZvMetaItem(
            icon: Icons.pedal_bike_rounded,
            label: restaurant.deliveryFee == 0
                ? 'Free'
                : 'US\$${restaurant.deliveryFee.toStringAsFixed(2)}',
            tint: restaurant.deliveryFee == 0 ? AppColors.success : null,
          ),
          if (distanceLabel != null)
            ZvMetaItem(
              icon: Icons.place_outlined,
              label: distanceLabel!,
            ),
        ],
      ],
    );
  }
}

/// Compact tile for the horizontal rails on home.
class RestaurantRailCard extends StatelessWidget {
  const RestaurantRailCard({
    super.key,
    required this.store,
    required this.onTap,
    this.width = 176,
    this.mode = RestaurantCardMode.delivery,
  });

  final DiscoveryRestaurant store;
  final VoidCallback onTap;
  final double width;
  final RestaurantCardMode mode;

  @override
  Widget build(BuildContext context) {
    final restaurant = store.restaurant;
    final closed = store.isClosed;
    final promotion = store.headlinePromotion;

    return SizedBox(
      width: width,
      child: ZvCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        semanticLabel: '${restaurant.name}, '
            '${restaurant.rating.toStringAsFixed(1)} stars, '
            '${closed ? store.availability.closedLabel : restaurant.deliveryTime}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Positioned.fill(
                  child: ZvNetworkImage(
                    url: restaurant.imageUrl.isNotEmpty
                        ? restaurant.imageUrl
                        : restaurant.bannerUrl,
                    aspectRatio: 16 / 9,
                    fallbackLabel: restaurant.name,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                if (closed)
                  Positioned.fill(
                    child: ColoredBox(
                      color: AppColors.neutral900.withValues(alpha: 0.46),
                    ),
                  ),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: closed
                          ? ZvStatusChip(
                              label: store.availability.closedLabel,
                              icon: Icons.schedule_rounded,
                              compact: true,
                            )
                          : promotion != null
                              ? ZvBadge.deal(label: _shortPromo(promotion))
                              : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    style: AppTextStyles.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ZvMetaItem(
                        icon: Icons.star_rounded,
                        label: restaurant.rating.toStringAsFixed(1),
                        tint: AppColors.rating,
                      ),
                      if (mode == RestaurantCardMode.pickup &&
                          store.distanceLabel != null)
                        ZvMetaItem(
                          icon: Icons.directions_walk_rounded,
                          label: store.distanceLabel!,
                        )
                      else
                        ZvMetaItem(
                          icon: Icons.schedule_rounded,
                          label: restaurant.deliveryTime,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    mode == RestaurantCardMode.pickup
                        ? 'No delivery fee'
                        : restaurant.deliveryFee == 0
                            ? 'Free delivery'
                            : 'US\$${restaurant.deliveryFee.toStringAsFixed(2)} delivery',
                    style: AppTextStyles.caption.copyWith(
                      color: restaurant.deliveryFee == 0 ||
                              mode == RestaurantCardMode.pickup
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.state});

  final StoreAvailability state;

  @override
  Widget build(BuildContext context) {
    if (state.isKnownClosed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZvStatusChip(
            label: state.closedLabel,
            icon: Icons.schedule_rounded,
            uppercase: false,
          ),
          if (state.acceptsScheduled) ...[
            const SizedBox(width: AppSpacing.xxs),
            const ZvStatusChip(
              label: 'Pre-order',
              tone: ZvTone.info,
              icon: Icons.event_available_rounded,
              uppercase: false,
            ),
          ],
        ],
      );
    }
    final closingSoon = state.closingSoonLabel;
    if (closingSoon != null) {
      return ZvStatusChip(
        label: closingSoon,
        tone: ZvTone.warning,
        icon: Icons.timelapse_rounded,
        uppercase: false,
      );
    }
    return const SizedBox.shrink();
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating, this.reviewCount});

  final double rating;
  final int? reviewCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.fullAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: AppColors.rating),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: AppTextStyles.tabular(AppTextStyles.bodyStrong)
                .copyWith(fontSize: 13),
          ),
          if (reviewCount != null && reviewCount! > 0) ...[
            const SizedBox(width: 3),
            Text(
              '(${_compactCount(reviewCount!)})',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _PromotionLine extends StatelessWidget {
  const _PromotionLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs + 1,
      ),
      decoration: const BoxDecoration(
        color: AppColors.dealSurface,
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer_rounded, size: 13, color: AppColors.deal),
          const SizedBox(width: AppSpacing.xxs + 2),
          Flexible(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.deal,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

String? _distanceLabel(double? km) {
  if (km == null || km.isNaN || km.isInfinite || km < 0) return null;
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1)} km';
}

/// Badges hold two words; a long promo line is trimmed to its first clause.
String _shortPromo(String promotion) {
  final clause = promotion.split(RegExp(r'[.–—|]')).first.trim();
  final text = clause.isEmpty ? promotion.trim() : clause;
  return text.length <= 18 ? text : '${text.substring(0, 17)}…';
}

String _compactCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k';
  return '$value';
}
