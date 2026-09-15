import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/account/promotions_provider.dart';

/// The customer's promo wallet.
///
/// Distinct from the Offers tab on purpose: **Offers** is discovery — which
/// *restaurants* have deals on right now. This is the wallet — the actual
/// promotions, their codes, their minimum spend and when they run out. It is
/// fed by `GET /catalog/promotions`, which already filters out anything
/// expired, unstarted or fully redeemed.
class PromotionsScreen extends ConsumerWidget {
  const PromotionsScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PromotionsScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promotions = ref.watch(activePromotionsProvider);

    return ZvScreen(
      title: 'Promotions',
      subtitle: 'Codes and deals you can use right now',
      fallbackRoute: '/account',
      child: promotions.when(
        loading: () => const ZvSkeletonList.tiles(count: 4),
        error: (error, _) => ZvErrorState(
          error: error,
          title: 'We could not load your promotions',
          onRetry: () => ref.invalidate(activePromotionsProvider),
          secondaryActionLabel: 'Browse offers instead',
          onSecondaryAction: () => context.push('/offers'),
        ),
        data: (all) {
          if (all.isEmpty) {
            return ZvEmptyState(
              icon: Icons.local_offer_outlined,
              title: 'No promotions running',
              message: 'When a restaurant puts on a deal it shows up here with '
                  'its code and conditions. In the meantime, the Offers tab '
                  'has today\'s best value.',
              actionLabel: 'See today\'s offers',
              onAction: () => context.push('/offers'),
            );
          }

          final withCode = all.where((p) => p.code != null).toList();
          final automatic = all.where((p) => p.code == null).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(activePromotionsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                if (withCode.isNotEmpty) ...[
                  const ZvSectionHeader(
                    title: 'Your codes',
                    subtitle: 'Copy one and paste it at checkout.',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ZvStaggeredList(
                    children: withCode
                        .map((p) => _PromotionCard(promotion: p))
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
                if (automatic.isNotEmpty) ...[
                  const ZvSectionHeader(
                    title: 'Applied automatically',
                    subtitle: 'No code needed — these come off at checkout.',
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ZvStaggeredList(
                    startIndex: withCode.length,
                    children: automatic
                        .map((p) => _PromotionCard(promotion: p))
                        .toList(),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                ZvButton.secondary(
                  label: 'Browse restaurants with deals',
                  icon: Icons.storefront_outlined,
                  onPressed: () => context.push('/offers'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({required this.promotion});

  final Promotion promotion;

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: promotion.code!));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${promotion.code} copied — paste it at checkout'),
        action: SnackBarAction(
          label: 'Go to cart',
          onPressed: () => context.push('/cart'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expiry = promotion.expiryLine;

    return ZvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.dealSurface,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(_icon(promotion.iconHint),
                    color: AppColors.deal, size: 24),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(promotion.title, style: AppTextStyles.h3),
                    if (promotion.subtitle.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxxs),
                      Text(
                        promotion.subtitle,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              ZvBadge.deal(label: promotion.valueLabel),
            ],
          ),
          if (promotion.description != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              promotion.description!,
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              ZvStatusChip(
                label: promotion.conditionsLine,
                icon: Icons.info_outline_rounded,
                compact: true,
                uppercase: false,
              ),
              if (expiry != null)
                ZvStatusChip(
                  label: expiry,
                  tone: promotion.endingSoon ? ZvTone.warning : ZvTone.neutral,
                  icon: Icons.schedule_rounded,
                  compact: true,
                  uppercase: false,
                ),
            ],
          ),
          if (promotion.code != null) ...[
            const SizedBox(height: AppSpacing.md),
            ZvTapScale(
              onTap: () => _copyCode(context),
              semanticLabel: 'Copy promo code ${promotion.code}',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: AppColors.neutral300,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        promotion.code!,
                        style: AppTextStyles.tabular(AppTextStyles.h3),
                      ),
                    ),
                    const Icon(Icons.copy_rounded,
                        size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Copy',
                      style: AppTextStyles.button
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (promotion.restaurantId != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ZvButton.tertiary(
              label: 'Open the restaurant',
              trailingIcon: Icons.arrow_forward_rounded,
              onPressed: () =>
                  context.push('/restaurant/${promotion.restaurantId}'),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _icon(String hint) => switch (hint) {
        'delivery_dining' => Icons.delivery_dining_rounded,
        'percent' => Icons.percent_rounded,
        'card_giftcard' => Icons.card_giftcard_rounded,
        _ => Icons.local_offer_rounded,
      };
}
