import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'promo_banner.g.dart';

/// Fetches active promotions from the backend.
/// Returns an empty list if the endpoint is unavailable or returns no promos.
@riverpod
Future<List<PromoData>> activePromos(Ref ref) async {
  try {
    final dio = ref.read(apiClientProvider);
    final response = await dio.get('/catalog/promotions');
    final List items = response.data is List ? response.data : [];
    return items.map((json) => PromoData.fromJson(json)).toList();
  } catch (_) {
    return [];
  }
}

/// Gradient palettes per promo type
const _gradients = {
  'percentage': [Color(0xFFD7F654), Color(0xFFC8EA3B)],
  'flat': [Color(0xFF171917), Color(0xFF30332F)],
  'free_delivery': [Color(0xFFFFC86B), Color(0xFFF2A83B)],
  'free_item': [Color(0xFF0A8F5B), Color(0xFF076C45)],
};

/// Data model for a promotion received from the backend
class PromoData {
  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final String promoType;
  final double discountValue;
  final double minOrderUsd;
  final String? code;
  final List<Color> gradient;

  const PromoData({
    this.id = '',
    required this.title,
    required this.subtitle,
    this.iconName = 'local_offer',
    this.promoType = 'percentage',
    this.discountValue = 0,
    this.minOrderUsd = 0,
    this.code,
    this.gradient = const [AppColors.primary, AppColors.primaryDark],
  });

  factory PromoData.fromJson(Map<String, dynamic> json) {
    final type = json['promo_type'] ?? 'percentage';
    return PromoData(
      id: json['_id'] ?? json['promo_id'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      iconName: json['icon'] ?? 'local_offer',
      promoType: type,
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      minOrderUsd: (json['min_order_usd'] as num?)?.toDouble() ?? 0,
      code: json['code'],
      gradient: _gradients[type] ?? [AppColors.primary, AppColors.primaryDark],
    );
  }

  IconData get icon {
    switch (iconName) {
      case 'delivery_dining':
        return Icons.delivery_dining;
      case 'card_giftcard':
        return Icons.card_giftcard;
      case 'percent':
        return Icons.percent;
      default:
        return Icons.local_offer;
    }
  }

  Color get foreground => promoType == 'flat' || promoType == 'free_item'
      ? Colors.white
      : AppColors.textPrimary;
}

/// Horizontal scrolling promo/deal banner cards — fetches from backend.
class PromoBanner extends ConsumerWidget {
  const PromoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promosAsync = ref.watch(activePromosProvider);

    return promosAsync.when(
      data: (promos) {
        if (promos.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Offers', style: AppTextStyles.titleLarge),
                  const Spacer(),
                  Text(
                    '${promos.length} available',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildPromoList(promos),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildPromoList(List<PromoData> promos) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: promos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final promo = promos[index];
          return Container(
            width: 278,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: promo.gradient,
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        promo.title,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: promo.foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        promo.subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: promo.foreground.withOpacity(0.72),
                        ),
                        maxLines: 2,
                      ),
                      if (promo.code != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: promo.foreground.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            promo.code!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: promo.foreground,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: promo.foreground.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(promo.icon, color: promo.foreground, size: 26),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
