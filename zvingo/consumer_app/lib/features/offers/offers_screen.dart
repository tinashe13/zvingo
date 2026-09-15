import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/filter/filter_provider.dart';
import 'package:consumer_app/features/home/discovery_provider.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart';
import 'package:consumer_app/features/offers/offers_provider.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Everything you can save money on right now: live promo codes plus the
/// restaurants running a deal or delivering for free.
class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(deliveryLocationNotifierProvider);
    final query = DiscoveryQuery.from(
      const FilterState(offersOnly: true),
      location,
    );
    final promos = ref.watch(activePromotionsProvider);
    final feed = ref.watch(discoveryFeedProvider(query));

    return ZvScreen(
      title: 'Offers',
      subtitle: 'Deals, free delivery and promo codes',
      child: RefreshIndicator(
        color: AppColors.actionDefault,
        onRefresh: () async {
          ref.invalidate(activePromotionsProvider);
          ref.invalidate(discoveryFeedProvider(query));
          await Future.wait<void>([
            ref.read(activePromotionsProvider.future),
            ref.read(discoveryFeedProvider(query).future),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ..._promoSection(context, ref, promos),
            ..._restaurantSection(context, ref, feed, query, promos),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  List<Widget> _promoSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Promotion>> promos,
  ) {
    return promos.when(
      loading: () => const [
        SliverToBoxAdapter(
          child: Column(
            children: [
              ZvSectionHeader(title: 'Promo codes'),
              ZvSkeletonList(count: 2, itemBuilder: _promoSkeletonItem),
            ],
          ),
        ),
      ],
      error: (error, _) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ZvErrorState(
              error: error,
              compact: true,
              title: 'Promo codes did not load',
              onRetry: () => ref.invalidate(activePromotionsProvider),
            ),
          ),
        ),
      ],
      data: (list) {
        if (list.isEmpty) return const <Widget>[];
        return [
          SliverToBoxAdapter(
            child: ZvSectionHeader(
              title: 'Promo codes',
              subtitle: list.length == 1
                  ? '1 code you can use today'
                  : '${list.length} codes you can use today',
            ),
          ),
          ZvStaggeredSliverList(
            itemCount: list.length,
            gap: 0,
            itemBuilder: (context, index) => _PromoCodeCard(
              promo: list[index],
              onOpenRestaurant: list[index].restaurantId == null
                  ? null
                  : () =>
                      context.push('/restaurant/${list[index].restaurantId}'),
            ),
          ),
        ];
      },
    );
  }

  List<Widget> _restaurantSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<DiscoveryRestaurant>> feed,
    DiscoveryQuery query,
    AsyncValue<List<Promotion>> promos,
  ) {
    return feed.when(
      loading: () => const [
        SliverToBoxAdapter(
          child: Column(
            children: [
              ZvSectionHeader(title: 'Restaurants with a deal'),
              ZvSkeletonList.restaurants(count: 3),
            ],
          ),
        ),
      ],
      error: (error, _) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ZvErrorState(
            error: error,
            onRetry: () => ref.invalidate(discoveryFeedProvider(query)),
          ),
        ),
      ],
      data: (stores) {
        // `has_promotions=true` is applied server-side; free delivery is the
        // other thing people count as an offer, so fold it in here.
        final deals =
            stores.where((s) => s.hasPromotion || s.isFreeDelivery).toList()
              ..sort((a, b) {
                if (a.isClosed != b.isClosed) return a.isClosed ? 1 : -1;
                if (a.hasPromotion != b.hasPromotion) {
                  return a.hasPromotion ? -1 : 1;
                }
                return b.restaurant.rating.compareTo(a.restaurant.rating);
              });

        if (deals.isEmpty) {
          final noCodes = promos.valueOrNull?.isEmpty ?? true;
          if (!noCodes) return const <Widget>[];
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: ZvEmptyState(
                icon: Icons.local_offer_outlined,
                title: 'No offers right now',
                message:
                    'Restaurant promotions and free-delivery deals show up here as soon as they go live. In the meantime, the full menu is one tap away.',
                actionLabel: 'Browse restaurants',
                onAction: () => context.go('/home'),
              ),
            ),
          ];
        }

        return [
          SliverToBoxAdapter(
            child: ZvSectionHeader(
              title: 'Restaurants with a deal',
              subtitle: deals.length == 1
                  ? '1 restaurant'
                  : '${deals.length} restaurants',
            ),
          ),
          ZvStaggeredSliverList(
            itemCount: deals.length,
            gap: 0,
            itemBuilder: (context, index) => RestaurantCard.discovery(
              deals[index],
              onTap: () => context.push('/restaurant/${deals[index].id}'),
            ),
          ),
        ];
      },
    );
  }
}

Widget _promoSkeletonItem(BuildContext context, int index) {
  return const ZvShimmer(
    child: ZvSkeletonBox(height: 96, radius: AppRadius.lg),
  );
}

class _PromoCodeCard extends StatelessWidget {
  const _PromoCodeCard({required this.promo, this.onOpenRestaurant});

  final Promotion promo;
  final VoidCallback? onOpenRestaurant;

  Future<void> _copy(BuildContext context) async {
    final code = promo.code;
    if (code == null) {
      onOpenRestaurant?.call();
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Promo code $code copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final condition = promo.conditionLabel;
    return ZvCard(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.listGap,
      ),
      onTap: () => _copy(context),
      semanticLabel: '${promo.title}. ${promo.valueLabel}.'
          '${promo.code != null ? ' Code ${promo.code}, tap to copy.' : ''}',
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: promo.gradient,
              ),
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(promo.iconData, color: promo.foreground, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        promo.title,
                        style: AppTextStyles.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    ZvBadge.deal(label: promo.valueLabel),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  promo.subtitle.isNotEmpty
                      ? promo.subtitle
                      : promo.description ?? 'Applies at checkout',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (condition != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    condition,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
                if (promo.code != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: AppRadius.smAll,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          promo.code!,
                          style: AppTextStyles.overline,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Tap to copy',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
