import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'restaurant_provider.g.dart';

/// One selectable choice inside a [MenuOptionGroup], e.g. "Large (+$1.50)".
@immutable
class MenuOption {
  const MenuOption({
    required this.id,
    required this.name,
    required this.priceDeltaUsd,
    this.isAvailable = true,
    this.isDefault = false,
  });

  final String id;
  final String name;

  /// Added to the item's base price when selected. May be zero or negative.
  final double priceDeltaUsd;
  final bool isAvailable;
  final bool isDefault;

  Money get priceDelta => Money.fromMajor(priceDeltaUsd);

  factory MenuOption.fromJson(Map<String, dynamic> json) => MenuOption(
        id: json['id']?.toString() ?? json['name']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        priceDeltaUsd: (json['price_delta_usd'] as num?)?.toDouble() ??
            (json['price_usd'] as num?)?.toDouble() ??
            0.0,
        isAvailable: json['is_available'] as bool? ?? true,
        isDefault: json['is_default'] as bool? ?? false,
      );
}

/// A group of choices attached to a menu item — "Choose a size" (required,
/// pick exactly one) or "Add extras" (optional, pick up to three).
@immutable
class MenuOptionGroup {
  const MenuOptionGroup({
    required this.id,
    required this.name,
    required this.options,
    this.minSelections = 0,
    this.maxSelections = 1,
  });

  final String id;
  final String name;
  final List<MenuOption> options;

  /// How many choices the customer must make. `>= 1` makes the group required.
  final int minSelections;

  /// How many choices the customer may make.
  final int maxSelections;

  bool get isRequired => minSelections > 0;
  bool get isSingleChoice => maxSelections <= 1;

  /// Short rule shown beside the group title, e.g. "Required · Choose 1".
  String get ruleLabel {
    if (isSingleChoice) return isRequired ? 'Required · Choose 1' : 'Choose 1';
    if (isRequired && minSelections == maxSelections) {
      return 'Required · Choose $minSelections';
    }
    if (isRequired) return 'Required · Choose $minSelections–$maxSelections';
    return 'Optional · Up to $maxSelections';
  }

  factory MenuOptionGroup.fromJson(Map<String, dynamic> json) {
    final options = ((json['options'] as List?) ?? const [])
        .map((e) => MenuOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final required = json['is_required'] as bool?;
    return MenuOptionGroup(
      id: json['id']?.toString() ?? json['name']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      options: options,
      minSelections: (json['min_selections'] as num?)?.toInt() ??
          (required == true ? 1 : 0),
      maxSelections: (json['max_selections'] as num?)?.toInt() ?? 1,
    );
  }
}

class MenuItem {
  final String id;
  final String name;
  final String description;
  final double price;
  final String category;
  final bool isAvailable;
  final List<String> images;
  final int? approvalPercent;
  final int? approvalCount;
  final bool isGreatPrice;

  /// Customisation groups. Empty until the catalog serves `option_groups` —
  /// the item sheet degrades to quantity + instructions when there are none.
  final List<MenuOptionGroup> optionGroups;

  MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.isAvailable,
    required this.images,
    this.approvalPercent,
    this.approvalCount,
    this.isGreatPrice = false,
    this.optionGroups = const <MenuOptionGroup>[],
  });

  String get imageUrl => images.isNotEmpty ? images.first : '';

  /// Base price as exact money. Prices are quoted in USD (`price_usd`).
  Money get basePrice => Money.fromMajor(price);

  bool get hasOptions => optionGroups.isNotEmpty;

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    var imgUrl = json['image_url'] ?? '';
    imgUrl = _fixUrl(imgUrl);

    List<String> imgs = [];
    if (json['images'] != null) {
      imgs =
          (json['images'] as List).map((e) => _fixUrl(e.toString())).toList();
    }
    // Ensure primary image is in list if not empty
    if (imgs.isEmpty && imgUrl.isNotEmpty) {
      imgs.add(imgUrl);
    }

    return MenuItem(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      price: (json['price_usd'] as num?)?.toDouble() ?? 0.0,
      category: json['category'] ?? 'Other',
      isAvailable: json['is_available'] ?? true,
      images: imgs,
      approvalPercent: json['approval_percent'] as int?,
      approvalCount: json['approval_count'] as int?,
      isGreatPrice: json['is_great_price'] ?? false,
      optionGroups: ((json['option_groups'] as List?) ?? const [])
          .map((e) =>
              MenuOptionGroup.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((g) => g.options.isNotEmpty)
          .toList(),
    );
  }
}

String _fixUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  // If running on Android emulator, localhost needs to be 10.0.2.2
  // We can blindly replace localhost with 10.0.2.2 for this MVP
  // since real devices won't have localhost URLs anyway (they'd be literal IP or domain).
  return url.replaceFirst('localhost', '10.0.2.2');
}

/// Live open/closed state, as computed by `app/catalog/hours.py` and embedded
/// in every restaurant payload. The client never re-implements the rules.
@immutable
class RestaurantAvailability {
  const RestaurantAvailability({
    required this.isOpen,
    required this.status,
    required this.reason,
    this.timezone,
    this.localTime,
    this.opensAt,
    this.closesAt,
    this.acceptsScheduled = false,
  });

  /// Closed-by-default is the safe assumption only when the server says so;
  /// a payload with no availability block means "no schedule configured", and
  /// the restaurant is treated as open (its previous behaviour).
  factory RestaurantAvailability.unknown() => const RestaurantAvailability(
        isOpen: true,
        status: 'open',
        reason: '',
      );

  final bool isOpen;

  /// `open | closed | closed_by_merchant | paused | unlisted`.
  final String status;

  /// Short human sentence, already written for a badge.
  final String reason;
  final String? timezone;
  final String? localTime;
  final DateTime? opensAt;
  final DateTime? closesAt;

  /// Whether a pre-order may still be placed while closed.
  final bool acceptsScheduled;

  bool get isPaused => status == 'paused';
  bool get isUnlisted => status == 'unlisted';

  /// Copy for the badge, guaranteed non-empty.
  String get label {
    if (isOpen) return 'Open now';
    if (reason.isNotEmpty) return reason;
    return switch (status) {
      'paused' => 'Paused — not taking orders',
      'closed_by_merchant' => 'Closed by the restaurant',
      'unlisted' => 'Not currently on Zvingo',
      _ => 'Closed right now',
    };
  }

  factory RestaurantAvailability.fromJson(Map<String, dynamic> json) =>
      RestaurantAvailability(
        isOpen: json['is_open'] as bool? ?? true,
        status: json['status']?.toString() ?? 'open',
        reason: json['reason']?.toString() ?? '',
        timezone: json['timezone']?.toString(),
        localTime: json['local_time']?.toString(),
        opensAt: DateTime.tryParse(json['opens_at']?.toString() ?? ''),
        closesAt: DateTime.tryParse(json['closes_at']?.toString() ?? ''),
        acceptsScheduled: json['accepts_scheduled'] as bool? ?? false,
      );
}

class Restaurant {
  final String id;
  final String name;
  final String description;
  final double rating;
  final int deliveryTimeMin;
  final int deliveryTimeMax;
  final double deliveryFee;
  final String imageUrl;
  final String bannerUrl;
  final String address;
  final List<String> promotions;
  final String category;
  final List<MenuItem> menu;
  final double? distanceMi;
  final int? reviewCount;
  final int? neighborsLiked;
  final int? customerPhotosCount;
  final double? freeDeliveryThreshold;
  final bool isZvingoPlus;
  final double? latitude;
  final double? longitude;

  /// Live open/closed state (`availability` on the API payload).
  final RestaurantAvailability availability;

  /// Human-readable weekly schedule, when the merchant has set one.
  final String? operatingHours;

  /// Minimum basket value the restaurant will accept, when configured.
  final double? minimumOrderUsd;

  /// Whether the merchant takes pre-orders at all (`accepts_scheduled_orders`).
  /// Distinct from [RestaurantAvailability.acceptsScheduled], which is only
  /// true while the restaurant is *closed*.
  final bool acceptsScheduledOrders;

  Restaurant({
    required this.id,
    required this.name,
    required this.description,
    required this.rating,
    required this.deliveryTimeMin,
    required this.deliveryTimeMax,
    required this.deliveryFee,
    required this.imageUrl,
    required this.bannerUrl,
    required this.category,
    required this.menu,
    required this.address,
    required this.promotions,
    this.distanceMi,
    this.reviewCount,
    this.neighborsLiked,
    this.customerPhotosCount,
    this.freeDeliveryThreshold,
    this.isZvingoPlus = false,
    this.latitude,
    this.longitude,
    RestaurantAvailability? availability,
    this.operatingHours,
    this.minimumOrderUsd,
    this.acceptsScheduledOrders = true,
  }) : availability = availability ?? const RestaurantAvailability(
              isOpen: true,
              status: 'open',
              reason: '',
            );

  String get deliveryTime => '$deliveryTimeMin-$deliveryTimeMax min';

  /// Can this restaurant take an order right now?
  bool get isOpen => availability.isOpen;

  /// Delivery fee as exact money.
  Money get deliveryFeeMoney => Money.fromMajor(deliveryFee);

  /// Minimum basket, when the restaurant sets one.
  Money? get minimumOrder =>
      minimumOrderUsd == null ? null : Money.fromMajor(minimumOrderUsd!);

  /// Distinct menu categories in menu order, de-duplicated.
  List<String> get menuCategories {
    final seen = <String>{};
    final ordered = <String>[];
    for (final item in menu) {
      if (seen.add(item.category)) ordered.add(item.category);
    }
    return ordered;
  }

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    final coordinates = location is Map ? location['coordinates'] : null;
    final longitude = coordinates is List && coordinates.length >= 2
        ? (coordinates[0] as num?)?.toDouble()
        : (json['lng'] as num?)?.toDouble();
    final latitude = coordinates is List && coordinates.length >= 2
        ? (coordinates[1] as num?)?.toDouble()
        : (json['lat'] as num?)?.toDouble();
    final availabilityJson = json['availability'];
    return Restaurant(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      deliveryTimeMin: json['delivery_time_min'] ?? 0,
      deliveryTimeMax: json['delivery_time_max'] ?? 0,
      deliveryFee: (json['delivery_fee_usd'] as num?)?.toDouble() ?? 0.0,
      imageUrl: _fixUrl(json['image_url']),
      bannerUrl: _fixUrl(json['banner_url']),
      category:
          json['categories'] != null && (json['categories'] as List).isNotEmpty
              ? (json['categories'] as List).join(', ')
              : json['category'] ?? 'Restaurant',
      menu:
          (json['menu'] as List?)?.map((e) => MenuItem.fromJson(e)).toList() ??
              [],
      address: json['address'] ?? '',
      promotions:
          (json['promotions'] as List?)?.map((e) => e.toString()).toList() ??
              [],
      distanceMi: (json['distance_mi'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int?,
      neighborsLiked: json['neighbors_liked'] as int?,
      customerPhotosCount: json['customer_photos_count'] as int?,
      freeDeliveryThreshold:
          (json['free_delivery_threshold'] as num?)?.toDouble(),
      isZvingoPlus: json['is_zvingo_plus'] ?? false,
      latitude: latitude,
      longitude: longitude,
      availability: availabilityJson is Map
          ? RestaurantAvailability.fromJson(
              Map<String, dynamic>.from(availabilityJson))
          : RestaurantAvailability.unknown(),
      operatingHours: json['operating_hours']?.toString(),
      minimumOrderUsd: (json['minimum_order_usd'] as num?)?.toDouble(),
      acceptsScheduledOrders:
          json['accepts_scheduled_orders'] as bool? ?? true,
    );
  }
}

@riverpod
Future<List<Restaurant>> restaurantList(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/catalog/restaurants');

  return (response.data as List).map((e) => Restaurant.fromJson(e)).toList();
}

final nearbyRestaurantsProvider = FutureProvider.autoDispose
    .family<List<Restaurant>, ({double lat, double lng})>((ref, point) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get(
    '/catalog/restaurants',
    queryParameters: {
      'lat': point.lat,
      'lon': point.lng,
      'radius_km': 25,
    },
  );
  return (response.data as List)
      .map((item) => Restaurant.fromJson(item))
      .toList();
});

@riverpod
Future<Restaurant> restaurantDetail(Ref ref, String id) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/catalog/restaurants/$id');
  return Restaurant.fromJson(response.data);
}

@riverpod
Future<List<MenuItem>> searchRestaurantItems(
    Ref ref, String restaurantId, String query) async {
  if (query.isEmpty) return [];
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/catalog/restaurants/$restaurantId/search',
      queryParameters: {'q': query});
  return (response.data as List).map((e) => MenuItem.fromJson(e)).toList();
}

// ── Promotion Model & Provider ────────────────────────────────

class Promotion {
  final String id;
  final String promoId;
  final String title;
  final String subtitle;
  final String? description;
  final String icon;
  final String promoType;
  final double discountValue;
  final double minOrderUsd;
  final double? maxDiscountUsd;
  final String? restaurantId;
  final String? code;
  final bool isActive;

  Promotion({
    required this.id,
    required this.promoId,
    required this.title,
    required this.subtitle,
    this.description,
    required this.icon,
    required this.promoType,
    required this.discountValue,
    required this.minOrderUsd,
    this.maxDiscountUsd,
    this.restaurantId,
    this.code,
    required this.isActive,
  });

  /// Minimum basket for this promo, as exact money.
  Money get minOrder => Money.fromMajor(minOrderUsd);

  factory Promotion.fromJson(Map<String, dynamic> json) {
    return Promotion(
      id: json['_id'] ?? json['id'] ?? '',
      promoId: json['promo_id'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      description: json['description'],
      icon: json['icon'] ?? 'local_offer',
      promoType: json['promo_type'] ?? 'percentage',
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0.0,
      minOrderUsd: (json['min_order_usd'] as num?)?.toDouble() ?? 0.0,
      maxDiscountUsd: (json['max_discount_usd'] as num?)?.toDouble(),
      restaurantId: json['restaurant_id'],
      code: json['code'],
      isActive: json['is_active'] ?? true,
    );
  }
}

@riverpod
Future<List<Promotion>> restaurantPromotions(
    Ref ref, String restaurantId) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/catalog/promotions',
      queryParameters: {'restaurant_id': restaurantId});
  return (response.data as List).map((e) => Promotion.fromJson(e)).toList();
}

// ── Reviews ───────────────────────────────────────────────────

/// One customer review of a restaurant.
@immutable
class RestaurantReview {
  const RestaurantReview({
    required this.id,
    required this.rating,
    this.comment,
    this.tags = const <String>[],
    this.createdAt,
  });

  final String id;
  final int rating;
  final String? comment;
  final List<String> tags;
  final DateTime? createdAt;

  factory RestaurantReview.fromJson(Map<String, dynamic> json) =>
      RestaurantReview(
        id: json['id']?.toString() ?? '',
        rating: (json['restaurant_rating'] as num?)?.toInt() ?? 0,
        comment: (json['comment'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['comment'] as String).trim(),
        tags: ((json['tags'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );
}

/// Reviews for one restaurant (`GET /rating/restaurants/{id}/reviews`).
///
/// Hand-written rather than generated: the pinned `riverpod_generator` emits a
/// deprecated `AutoDisposeFutureProviderRef` for every generated provider.
final restaurantReviewsProvider =
    FutureProvider.family<List<RestaurantReview>, String>((ref, id) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/rating/restaurants/$id/reviews');
  return (response.data as List)
      .map((e) => RestaurantReview.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});
