import 'package:consumer_app/core/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cart_provider.g.dart';

class CartItem {
  final String id;
  final String name;
  final double price;
  final int quantity;
  final String? restaurantId;
  final String? restaurantName;
  final String? imageUrl;
  final String? restaurantImage;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.restaurantId,
    this.restaurantName,
    this.imageUrl,
    this.restaurantImage,
  });

  double get total => price * quantity;
}

@Riverpod(keepAlive: true)
class Cart extends _$Cart {
  @override
  List<CartItem> build() {
    return [];
  }

  void addItem(String id, String name, double price,
      {String? restaurantId,
      String? restaurantName,
      String? imageUrl,
      String? restaurantImage}) {
    final exists = state.any((item) => item.id == id);
    if (exists) {
      state = state
          .map((item) => item.id == id
              ? CartItem(
                  id: item.id,
                  name: item.name,
                  price: item.price,
                  quantity: item.quantity + 1,
                  restaurantId: item.restaurantId ?? restaurantId,
                  restaurantName: item.restaurantName ?? restaurantName,
                  imageUrl: item.imageUrl ?? imageUrl,
                  restaurantImage: item.restaurantImage ?? restaurantImage,
                )
              : item)
          .toList();
    } else {
      state = [
        ...state,
        CartItem(
          id: id,
          name: name,
          price: price,
          restaurantId: restaurantId,
          restaurantName: restaurantName,
          imageUrl: imageUrl,
          restaurantImage: restaurantImage,
        )
      ];
    }
  }

  void removeItem(String id) {
    state = state.where((item) => item.id != id).toList();
  }

  void decrementItem(String id) {
    state = state.map((item) {
      if (item.id == id && item.quantity > 1) {
        return CartItem(
          id: item.id,
          name: item.name,
          price: item.price,
          quantity: item.quantity - 1,
          restaurantId: item.restaurantId,
          restaurantName: item.restaurantName,
        );
      }
      return item;
    }).toList();
  }

  void clear() {
    state = [];
  }

  Map<String, List<CartItem>> get groupedItems {
    final map = <String, List<CartItem>>{};
    for (final item in state) {
      final key = item.restaurantId ?? 'unknown';
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  double totalForRestaurant(String restaurantId) {
    return state
        .where((item) => item.restaurantId == restaurantId)
        .fold(0, (sum, item) => sum + item.total);
  }

  // Checkout a specific restaurant, or all if restaurantId is null
  Future<List<String>> checkout(
    double dropoffLat,
    double dropoffLng, {
    String? restaurantId,
    String? deliveryInstructions,
    double tipAmount = 0.0,
    double deliveryFee = 0.0,
    double serviceFee = 0.0,
    double taxAmount = 0.0,
  }) async {
    if (state.isEmpty) return [];

    final dio = ref.read(apiClientProvider);

    // Get consumer ID
    String consumerId = 'anonymous';
    try {
      final meResponse = await dio.get('/auth/me');
      consumerId = meResponse.data['id'] ?? 'anonymous';
    } catch (_) {}

    final orderIds = <String>[];
    final cartsToCheckout = restaurantId != null
        ? {
            restaurantId:
                state.where((i) => i.restaurantId == restaurantId).toList()
          }
        : groupedItems;

    for (final entry in cartsToCheckout.entries) {
      final mid = entry.key;
      final items = entry.value;
      if (items.isEmpty) continue;

      final total = items.fold(0.0, (sum, i) => sum + i.total);

      try {
        final response = await dio.post('/orders/', data: {
          "merchant_id": mid,
          "consumer_id": consumerId,
          "items": items
              .map((i) => {
                    "name": i.name,
                    "quantity": i.quantity,
                    "price": i.price,
                  })
              .toList(),
          "total_amount":
              total + deliveryFee + serviceFee + taxAmount + tipAmount,
          "pickup_lat": 0.0, // Populated by backend from restaurant record
          "pickup_lng": 0.0,
          "dropoff_lat": dropoffLat,
          "dropoff_lng": dropoffLng,
          "delivery_instructions": deliveryInstructions,
          "tip_amount": tipAmount,
          "delivery_fee": deliveryFee,
          "service_fee": serviceFee,
          "tax_amount": taxAmount,
        });
        orderIds.add(response.data['id']);
      } catch (e) {
        debugPrint('Failed to checkout for merchant $mid: $e');
        rethrow;
      }
    }

    // Remove checked out items
    if (restaurantId != null) {
      state = state.where((i) => i.restaurantId != restaurantId).toList();
    } else {
      clear();
    }

    return orderIds;
  }
}

@riverpod
double cartTotal(Ref ref) {
  final cartItems = ref.watch(cartProvider);
  return cartItems.fold(0.0, (sum, item) => sum + item.total);
}
