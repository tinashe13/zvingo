import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/core/app_colors.dart';

/// Promotions currently visible to consumers — `GET /catalog/promotions`.
///
/// The endpoint already excludes expired, unstarted, inactive and
/// usage-capped promos, so whatever comes back is redeemable today.
final activePromotionsProvider =
    FutureProvider.autoDispose<List<Promotion>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get<dynamic>('/catalog/promotions');
  final data = response.data;
  if (data is! List) return const <Promotion>[];
  return data
      .whereType<Map>()
      .map((e) => Promotion.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
});

/// Presentation rules for a promotion, keyed off `promo_type`.
extension PromotionDisplay on Promotion {
  /// Two-stop gradient per promo type. All four stops are design tokens.
  List<Color> get gradient {
    switch (promoType) {
      case 'flat':
        return const [AppColors.neutral900, AppColors.neutral700];
      case 'free_delivery':
        return const [AppColors.warning, AppColors.deal];
      case 'free_item':
        return const [AppColors.brandGreen, AppColors.brandGreenDark];
      case 'percentage':
      default:
        return const [AppColors.brandLime, AppColors.brandLimeSurface];
    }
  }

  /// Ink that meets AA on [gradient].
  Color get foreground => promoType == 'percentage'
      ? AppColors.textPrimary
      : AppColors.textOnDark;

  IconData get iconData {
    switch (icon) {
      case 'delivery_dining':
        return Icons.delivery_dining_rounded;
      case 'card_giftcard':
        return Icons.card_giftcard_rounded;
      case 'percent':
        return Icons.percent_rounded;
      default:
        switch (promoType) {
          case 'free_delivery':
            return Icons.delivery_dining_rounded;
          case 'free_item':
            return Icons.card_giftcard_rounded;
          case 'flat':
            return Icons.savings_rounded;
          default:
            return Icons.local_offer_rounded;
        }
    }
  }

  /// The headline value, e.g. "25% off" / "US$5 off" / "Free delivery".
  String get valueLabel {
    switch (promoType) {
      case 'percentage':
        return '${discountValue.toStringAsFixed(discountValue % 1 == 0 ? 0 : 1)}% off';
      case 'flat':
        return 'US\$${discountValue.toStringAsFixed(2)} off';
      case 'free_delivery':
        return 'Free delivery';
      case 'free_item':
        return 'Free item';
      default:
        return title;
    }
  }

  /// The one condition worth surfacing on a card.
  String? get conditionLabel => minOrderUsd > 0
      ? 'On orders over US\$${minOrderUsd.toStringAsFixed(2)}'
      : null;
}
