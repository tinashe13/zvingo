import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/core/api_client.dart';

part 'promotions_provider.g.dart';

/// A live offer from `GET /catalog/promotions`.
///
/// The consumer endpoint strips `redeemed_by` and `redemptions_by_user`, so
/// this model has no idea who else has used a promo — only whether it is still
/// running.
class Promotion {
  const Promotion({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.promoType,
    required this.discountValue,
    this.description,
    this.code,
    this.minOrderUsd = 0,
    this.maxDiscountUsd,
    this.endsAt,
    this.restaurantId,
    this.firstOrderOnly = false,
    this.iconHint = 'local_offer',
  });

  final String id;
  final String title;
  final String subtitle;

  /// `percentage` | `flat` | `free_delivery` | `free_item`.
  final String promoType;
  final double discountValue;
  final String? description;

  /// Present only on code-based promos. Most promos apply automatically.
  final String? code;
  final double minOrderUsd;
  final double? maxDiscountUsd;
  final DateTime? endsAt;

  /// Set when the promo only applies at one restaurant.
  final String? restaurantId;
  final bool firstOrderOnly;
  final String iconHint;

  factory Promotion.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value)?.toLocal();
    }

    return Promotion(
      id: (json['promo_id'] ?? json['_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Offer').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      description: (json['description']?.toString().isEmpty ?? true)
          ? null
          : json['description'].toString(),
      promoType: (json['promo_type'] ?? 'percentage').toString(),
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      code: (json['code']?.toString().isEmpty ?? true)
          ? null
          : json['code'].toString(),
      minOrderUsd: (json['min_order_usd'] as num?)?.toDouble() ?? 0,
      maxDiscountUsd: (json['max_discount_usd'] as num?)?.toDouble(),
      endsAt: parseDate(json['ends_at']),
      restaurantId: (json['restaurant_id']?.toString().isEmpty ?? true)
          ? null
          : json['restaurant_id'].toString(),
      firstOrderOnly: json['first_order_only'] ?? false,
      iconHint: (json['icon'] ?? 'local_offer').toString(),
    );
  }

  /// "20% off", "US$5 off", "Free delivery", "Free item".
  String get valueLabel => switch (promoType) {
        'percentage' => '${discountValue.toStringAsFixed(0)}% off',
        'flat' => 'US\$${discountValue.toStringAsFixed(2)} off',
        'free_delivery' => 'Free delivery',
        'free_item' => 'Free item',
        _ => 'Offer',
      };

  /// The conditions, in one line, so nobody is surprised at checkout.
  String get conditionsLine {
    final parts = <String>[
      if (minOrderUsd > 0)
        'US\$${minOrderUsd.toStringAsFixed(2)} minimum order',
      if (maxDiscountUsd != null)
        'up to US\$${maxDiscountUsd!.toStringAsFixed(2)}',
      if (firstOrderOnly) 'first order only',
      if (restaurantId != null) 'one restaurant only',
    ];
    return parts.isEmpty ? 'No minimum spend' : _sentenceCase(parts.join(' · '));
  }

  /// Null when the promo has no end date.
  String? get expiryLine {
    final ends = endsAt;
    if (ends == null) return null;
    final remaining = ends.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inHours < 24) {
      return 'Ends in ${remaining.inHours}h ${remaining.inMinutes % 60}m';
    }
    return 'Ends in ${remaining.inDays} day${remaining.inDays == 1 ? '' : 's'}';
  }

  bool get endingSoon {
    final ends = endsAt;
    if (ends == null) return false;
    final remaining = ends.difference(DateTime.now());
    return !remaining.isNegative && remaining.inHours < 48;
  }

  static String _sentenceCase(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

/// Every promotion currently running, newest first.
///
/// `GET /catalog/promotions` is public and already excludes promos that have
/// expired, not started, or hit their usage cap — so anything returned here is
/// something the customer could actually use today.
@riverpod
Future<List<Promotion>> activePromotions(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get<dynamic>(
    '/catalog/promotions',
    queryParameters: const {'limit': 50},
  );
  final data = response.data;
  if (data is! List) return const [];
  return data
      .whereType<Map>()
      .map((e) => Promotion.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}
