import 'package:consumer_app/core/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'restaurant_provider.g.dart';

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
  });

  String get imageUrl => images.isNotEmpty ? images.first : '';

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
  });

  String get deliveryTime => '$deliveryTimeMin-$deliveryTimeMax min';

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    final coordinates = location is Map ? location['coordinates'] : null;
    final longitude = coordinates is List && coordinates.length >= 2
        ? (coordinates[0] as num?)?.toDouble()
        : (json['lng'] as num?)?.toDouble();
    final latitude = coordinates is List && coordinates.length >= 2
        ? (coordinates[1] as num?)?.toDouble()
        : (json['lat'] as num?)?.toDouble();
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
