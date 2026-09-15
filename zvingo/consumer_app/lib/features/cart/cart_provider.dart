/// The cart — the middle of the revenue path.
///
/// Three rules this file exists to enforce:
///
/// 1. **Money is integer cents.** Prices arrive from the API as JSON numbers
///    and are converted once, here, through [Money.fromMajor]. Nothing
///    downstream multiplies or adds a `double`.
/// 2. **A cart belongs to one restaurant.** `/payment/initiate` is scoped to a
///    single `order_id`, so a cart spanning two restaurants would demand two
///    separate mobile-money prompts on the customer's phone. [addItem] refuses
///    the second restaurant and reports [CartAddStatus.differentRestaurant] so
///    the caller can offer "start a new cart" — the items are never dropped
///    behind the user's back.
/// 3. **Nothing is lost.** Every removal returns a [RemovedCartLine] that
///    [restoreLine] puts back at the same index (the undo snackbar), and the
///    whole cart is mirrored into Hive so a crash or a cold start does not
///    empty it.
library;

import 'dart:convert';

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/cart/money.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cart_provider.g.dart';

/// One selected choice inside a menu item's option group, with its price delta.
@immutable
class CartOptionChoice {
  const CartOptionChoice({
    required this.groupId,
    required this.groupLabel,
    required this.id,
    required this.label,
    required this.priceDelta,
  });

  final String groupId;
  final String groupLabel;
  final String id;
  final String label;

  /// Added to (or subtracted from) the item's base price. Often zero.
  final Money priceDelta;

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'group_label': groupLabel,
        'id': id,
        'label': label,
        'delta_minor': priceDelta.minor,
        'currency': priceDelta.currency,
      };

  factory CartOptionChoice.fromJson(Map<String, dynamic> json) =>
      CartOptionChoice(
        groupId: json['group_id'] as String? ?? '',
        groupLabel: json['group_label'] as String? ?? '',
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        priceDelta: Money.minorUnits(
          (json['delta_minor'] as num?)?.toInt() ?? 0,
          currency: json['currency'] as String? ?? kDefaultCurrency,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is CartOptionChoice &&
      other.groupId == groupId &&
      other.id == id &&
      other.priceDelta == priceDelta;

  @override
  int get hashCode => Object.hash(groupId, id, priceDelta);
}

/// One configured line in the cart.
///
/// Two lines of the same menu item with different options are *different*
/// lines — [lineId] folds the options and the special instructions into the
/// identity, so bumping the quantity of "Burger, no onion" never silently
/// changes "Burger, extra cheese".
@immutable
class CartItem {
  CartItem({
    required this.itemId,
    required this.name,
    required this.unitBasePrice,
    this.quantity = 1,
    this.choices = const <CartOptionChoice>[],
    this.specialInstructions,
    this.restaurantId,
    this.restaurantName,
    this.imageUrl,
    this.restaurantImage,
    String? lineId,
  }) : lineId = lineId ?? buildLineId(itemId, choices, specialInstructions);

  /// Identity of this *configuration* — the key every mutation addresses.
  final String lineId;

  /// The catalog menu-item id.
  final String itemId;
  final String name;

  /// Price before options, in the catalog currency.
  final Money unitBasePrice;

  final int quantity;
  final List<CartOptionChoice> choices;
  final String? specialInstructions;

  final String? restaurantId;
  final String? restaurantName;
  final String? imageUrl;
  final String? restaurantImage;

  String get currency => unitBasePrice.currency;

  /// Base price plus every selected option's delta.
  Money get unitPrice =>
      unitBasePrice +
      choices.map((c) => c.priceDelta).sum(currency: currency);

  /// What this line contributes to the subtotal.
  Money get lineTotal => unitPrice * quantity;

  /// Human summary of the chosen options, e.g. "Large · Extra cheese".
  String get choicesSummary => choices.map((c) => c.label).join(' · ');

  bool get isCustomised =>
      choices.isNotEmpty || (specialInstructions?.trim().isNotEmpty ?? false);

  // ── Compatibility surface ────────────────────────────────────────
  // Kept so screens outside this feature (home, store search) keep compiling.
  /// Deprecated alias for [itemId].
  String get id => itemId;

  /// Presentation-only major-unit price. Never use it for arithmetic.
  double get price => unitPrice.major;

  /// Presentation-only major-unit line total. Never use it for arithmetic.
  double get total => lineTotal.major;

  CartItem copyWith({
    int? quantity,
    String? specialInstructions,
    List<CartOptionChoice>? choices,
  }) =>
      CartItem(
        itemId: itemId,
        name: name,
        unitBasePrice: unitBasePrice,
        quantity: quantity ?? this.quantity,
        choices: choices ?? this.choices,
        specialInstructions: specialInstructions ?? this.specialInstructions,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        imageUrl: imageUrl,
        restaurantImage: restaurantImage,
        lineId: (choices == null && specialInstructions == null)
            ? lineId
            : null,
      );

  Map<String, dynamic> toJson() => {
        'line_id': lineId,
        'item_id': itemId,
        'name': name,
        'base_minor': unitBasePrice.minor,
        'currency': unitBasePrice.currency,
        'quantity': quantity,
        'choices': choices.map((c) => c.toJson()).toList(),
        'special_instructions': specialInstructions,
        'restaurant_id': restaurantId,
        'restaurant_name': restaurantName,
        'image_url': imageUrl,
        'restaurant_image': restaurantImage,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String? ?? kDefaultCurrency;
    return CartItem(
      lineId: json['line_id'] as String?,
      itemId: json['item_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      unitBasePrice: Money.minorUnits(
        (json['base_minor'] as num?)?.toInt() ?? 0,
        currency: currency,
      ),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      choices: ((json['choices'] as List?) ?? const [])
          .map((e) => CartOptionChoice.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      specialInstructions: json['special_instructions'] as String?,
      restaurantId: json['restaurant_id'] as String?,
      restaurantName: json['restaurant_name'] as String?,
      imageUrl: json['image_url'] as String?,
      restaurantImage: json['restaurant_image'] as String?,
    );
  }

  /// Stable identity for a configuration of a menu item.
  static String buildLineId(
    String itemId,
    List<CartOptionChoice> choices,
    String? instructions,
  ) {
    final ids = choices.map((c) => '${c.groupId}:${c.id}').toList()..sort();
    final note = (instructions ?? '').trim();
    final noteKey = note.isEmpty ? '' : note.hashCode.toRadixString(16);
    return '$itemId|${ids.join(',')}|$noteKey';
  }
}

/// Why an add did or did not happen.
enum CartAddStatus {
  /// The line was added, or an identical line's quantity went up.
  added,

  /// The cart already holds items from another restaurant. Nothing changed —
  /// ask the user, then call [Cart.startNewCartWith].
  differentRestaurant,
}

/// Result of [Cart.addItem]. Callers that ignore it get the safe behaviour
/// (nothing is lost), but they should surface [existingRestaurantName].
@immutable
class CartAddResult {
  const CartAddResult(this.status, {this.existingRestaurantName, this.pending});

  final CartAddStatus status;

  /// Restaurant currently in the cart, for the "start a new cart?" copy.
  final String? existingRestaurantName;

  /// The line that was refused, ready to be re-applied after confirmation.
  final CartItem? pending;

  bool get added => status == CartAddStatus.added;
  bool get isConflict => status == CartAddStatus.differentRestaurant;
}

/// A removed line plus where it sat, so undo restores the order too.
@immutable
class RemovedCartLine {
  const RemovedCartLine({required this.item, required this.index});
  final CartItem item;
  final int index;
}

/// The restaurant a cart currently belongs to.
@immutable
class CartOwner {
  const CartOwner({this.id, this.name, this.imageUrl});
  final String? id;
  final String? name;
  final String? imageUrl;

  bool get isEmpty => id == null;
}

@Riverpod(keepAlive: true)
class Cart extends _$Cart {
  static const _boxName = 'cart';
  static const _key = 'lines';

  bool _restored = false;

  @override
  List<CartItem> build() {
    _restore();
    return const <CartItem>[];
  }

  // ── Persistence ──────────────────────────────────────────────────

  Future<void> _restore() async {
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_key) as String?;
      _restored = true;
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List<dynamic>;
      final items = decoded
          .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      // Only adopt the stored cart if nothing was added while we were loading.
      if (state.isEmpty && items.isNotEmpty) state = items;
    } catch (e) {
      _restored = true;
      debugPrint('Cart restore failed: $e');
    }
  }

  Future<void> _persist() async {
    if (!_restored) _restored = true;
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(
        _key,
        jsonEncode(state.map((i) => i.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Cart persist failed: $e');
    }
  }

  void _set(List<CartItem> next) {
    state = next;
    _persist();
  }

  // ── Reads ────────────────────────────────────────────────────────

  /// The restaurant this cart belongs to (empty when the cart is empty).
  CartOwner get owner {
    if (state.isEmpty) return const CartOwner();
    final first = state.first;
    return CartOwner(
      id: first.restaurantId,
      name: first.restaurantName,
      imageUrl: first.restaurantImage,
    );
  }

  /// Sum of every line, in integer cents.
  Money get subtotal => state
      .map((i) => i.lineTotal)
      .sum(currency: state.isEmpty ? kDefaultCurrency : state.first.currency);

  /// Total number of units (not lines).
  int get unitCount => state.fold(0, (sum, i) => sum + i.quantity);

  CartItem? lineById(String lineId) {
    for (final item in state) {
      if (item.lineId == lineId) return item;
    }
    return null;
  }

  // ── Mutations ────────────────────────────────────────────────────

  /// Add a menu item.
  ///
  /// Signature is source-compatible with the original three-positional-arg
  /// form used elsewhere in the app; options, quantity and notes are optional.
  CartAddResult addItem(
    String id,
    String name,
    double price, {
    String? restaurantId,
    String? restaurantName,
    String? imageUrl,
    String? restaurantImage,
    int quantity = 1,
    List<CartOptionChoice> choices = const <CartOptionChoice>[],
    String? specialInstructions,
    String currency = kDefaultCurrency,
  }) {
    final line = CartItem(
      itemId: id,
      name: name,
      unitBasePrice: Money.fromMajor(price, currency: currency),
      quantity: quantity < 1 ? 1 : quantity,
      choices: choices,
      specialInstructions: specialInstructions,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      imageUrl: imageUrl,
      restaurantImage: restaurantImage,
    );
    return addLine(line);
  }

  /// Add an already-configured line (the customisation sheet's path).
  CartAddResult addLine(CartItem line) {
    final current = owner;
    final belongsElsewhere = current.id != null &&
        line.restaurantId != null &&
        current.id != line.restaurantId;

    if (belongsElsewhere) {
      // Refuse rather than silently wipe the basket. The caller asks the user.
      return CartAddResult(
        CartAddStatus.differentRestaurant,
        existingRestaurantName: current.name,
        pending: line,
      );
    }

    final index = state.indexWhere((i) => i.lineId == line.lineId);
    if (index >= 0) {
      final next = [...state];
      next[index] = next[index]
          .copyWith(quantity: next[index].quantity + line.quantity);
      _set(next);
    } else {
      _set([...state, line]);
    }
    return const CartAddResult(CartAddStatus.added);
  }

  /// Empty the cart and start again with [line] — the "start a new cart"
  /// branch of the different-restaurant confirmation.
  void startNewCartWith(CartItem line) => _set([line]);

  /// Set a line's quantity. Zero or less removes it (use [removeLine] when you
  /// want the undo snapshot).
  void setQuantity(String lineId, int quantity) {
    if (quantity <= 0) {
      removeLine(lineId);
      return;
    }
    final next = [
      for (final item in state)
        if (item.lineId == lineId) item.copyWith(quantity: quantity) else item
    ];
    _set(next);
  }

  /// Remove a line and hand back everything needed to undo it.
  RemovedCartLine? removeLine(String lineId) {
    final index = state.indexWhere((i) => i.lineId == lineId);
    if (index < 0) return null;
    final removed = state[index];
    _set([...state]..removeAt(index));
    return RemovedCartLine(item: removed, index: index);
  }

  /// Put a removed line back where it was.
  void restoreLine(RemovedCartLine snapshot) {
    final next = [...state];
    final at = snapshot.index.clamp(0, next.length);
    next.insert(at, snapshot.item);
    _set(next);
  }

  /// Replace a line's whole configuration (edit from the cart).
  void replaceLine(String lineId, CartItem replacement) {
    final index = state.indexWhere((i) => i.lineId == lineId);
    if (index < 0) {
      addLine(replacement);
      return;
    }
    final next = [...state];
    // Merge into an identical existing configuration if the edit created one.
    final twin = next.indexWhere(
        (i) => i.lineId == replacement.lineId && i.lineId != lineId);
    if (twin >= 0) {
      next[twin] = next[twin]
          .copyWith(quantity: next[twin].quantity + replacement.quantity);
      next.removeAt(index);
    } else {
      next[index] = replacement;
    }
    _set(next);
  }

  void clear() => _set(const <CartItem>[]);

  /// Restore a whole cart (undo of "start a new cart").
  void restoreAll(List<CartItem> items) => _set(items);

  // ── Checkout ─────────────────────────────────────────────────────

  /// Place the order via `POST /orders/checkout`.
  ///
  /// `idempotencyKey` is generated once per checkout attempt by the caller and
  /// reused on retry, so a double-tap or a retried network call can never
  /// create a second order (`OrderService.create_order` returns the existing
  /// order for a key it has already seen).
  ///
  /// **`subtotal` is what the backend calls `total_amount`: food only.** Fees,
  /// tip and discount are separate fields and the backend adds them on top in
  /// `breakdown_for_order`. Sending a fee-inclusive total here would charge the
  /// fees twice.
  Future<CheckoutResult> checkout({
    required double dropoffLat,
    required double dropoffLng,
    required String idempotencyKey,
    String? deliveryInstructions,
    Money? tip,
    Money? deliveryFee,
    Money? serviceFee,
    Money? tax,
    String? promoCode,
    DateTime? scheduledAt,
    bool isPickup = false,
    bool clearCartOnSuccess = true,
  }) async {
    if (state.isEmpty) {
      throw const CheckoutFailure('Your cart is empty.');
    }
    final merchantId = owner.id;
    if (merchantId == null || merchantId.isEmpty) {
      throw const CheckoutFailure(
        'We lost track of which restaurant this order is for. '
        'Open the restaurant again and re-add your items.',
      );
    }

    final dio = ref.read(apiClientProvider);
    final currency = state.first.currency;
    final zero = Money.zero(currency);

    final payload = <String, dynamic>{
      'baskets': [
        {
          'merchant_id': merchantId,
          'items': state
              .map((i) => {
                    'name': _lineDescription(i),
                    'quantity': i.quantity,
                    'price': i.unitPrice.major,
                    if ((i.specialInstructions ?? '').trim().isNotEmpty)
                      'special_instructions': i.specialInstructions!.trim(),
                  })
              .toList(),
          'subtotal': subtotal.major,
          'delivery_fee': (deliveryFee ?? zero).major,
          'service_fee': (serviceFee ?? zero).major,
          'tax_amount': (tax ?? zero).major,
          'is_pickup': isPickup,
        }
      ],
      'dropoff': {
        'type': 'Point',
        'coordinates': [dropoffLng, dropoffLat],
      },
      if (deliveryInstructions != null && deliveryInstructions.trim().isNotEmpty)
        'delivery_instructions': deliveryInstructions.trim(),
      'tip_amount': (tip ?? zero).major,
      if (promoCode != null && promoCode.trim().isNotEmpty)
        'promo_code': promoCode.trim().toUpperCase(),
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'idempotency_key': idempotencyKey,
    };

    try {
      final response = await dio.post('/orders/checkout', data: payload);
      final data = Map<String, dynamic>.from(response.data as Map);
      final orders = (data['orders'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (orders.isEmpty) {
        throw const CheckoutFailure(
          'The restaurant did not confirm your order. Nothing has been charged '
          '— please try again.',
        );
      }
      final result = CheckoutResult(
        groupId: data['group_id'] as String? ?? '',
        orderIds: orders.map((o) => o['id'] as String).toList(),
        discount: Money.fromMajor(
          (data['discount_total'] as num?) ?? 0,
          currency: currency,
        ),
        subtotal: Money.fromMajor(
          (data['subtotal'] as num?) ?? subtotal.major,
          currency: currency,
        ),
      );
      if (clearCartOnSuccess) clear();
      return result;
    } on DioException catch (e) {
      throw CheckoutFailure(_readableError(e));
    }
  }

  /// Fold the chosen options into the line name the merchant will read on the
  /// ticket — `OrderItem` has no options field of its own (see the report).
  String _lineDescription(CartItem item) {
    if (item.choices.isEmpty) return item.name;
    return '${item.name} (${item.choicesSummary})';
  }

  static String _readableError(DioException e) {
    final detail = e.response?.data;
    if (detail is Map && detail['detail'] is String) {
      return detail['detail'] as String;
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The request timed out. Your order was not placed — try again.';
      case DioExceptionType.connectionError:
        return 'We could not reach Zvingo. Check your connection and try again.';
      default:
        if (e.response?.statusCode == 401) {
          return 'Please sign in again to place this order.';
        }
        return 'We could not place your order. Nothing has been charged.';
    }
  }
}

/// What a successful checkout produced.
@immutable
class CheckoutResult {
  const CheckoutResult({
    required this.groupId,
    required this.orderIds,
    required this.discount,
    required this.subtotal,
  });

  final String groupId;
  final List<String> orderIds;

  /// Discount the **server** applied — the number the customer is actually
  /// getting, which the success screen echoes back.
  final Money discount;
  final Money subtotal;

  String get primaryOrderId => orderIds.first;
}

/// A checkout that failed, carrying copy that is safe to show a customer.
class CheckoutFailure implements Exception {
  const CheckoutFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

// ── Derived providers ──────────────────────────────────────────────

/// Cart subtotal in exact minor units.
@riverpod
Money cartSubtotal(Ref ref) {
  final items = ref.watch(cartProvider);
  final currency = items.isEmpty ? kDefaultCurrency : items.first.currency;
  return items.map((i) => i.lineTotal).sum(currency: currency);
}

/// Total units in the cart (a 3× burger counts as 3).
@riverpod
int cartUnitCount(Ref ref) {
  final items = ref.watch(cartProvider);
  return items.fold(0, (sum, item) => sum + item.quantity);
}

/// The restaurant the cart belongs to.
@riverpod
CartOwner cartOwner(Ref ref) {
  final items = ref.watch(cartProvider);
  if (items.isEmpty) return const CartOwner();
  final first = items.first;
  return CartOwner(
    id: first.restaurantId,
    name: first.restaurantName,
    imageUrl: first.restaurantImage,
  );
}

/// Presentation-only major-unit total. Kept for existing call sites; prefer
/// [cartSubtotalProvider].
@riverpod
double cartTotal(Ref ref) => ref.watch(cartSubtotalProvider).major;
