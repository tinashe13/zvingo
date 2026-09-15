/// Domain models for the order feature.
///
/// Everything here is parsed defensively from the backend's JSON. The backend
/// serves two slightly different shapes for an order — the rich dict from
/// `GET /orders/{id}` (which carries live driver coordinates) and the
/// `OrderResponse` model used by the list endpoints — so [TrackedOrder.fromJson]
/// accepts both and simply leaves the missing fields null.
///
/// Fields the backend does **not** send yet (fee breakdown, driver phone,
/// vehicle, photo, server-side ETA) are parsed optionally. The moment the API
/// starts sending them the UI lights up with no client change; until then the
/// UI degrades honestly rather than inventing a number.
library;

import 'package:latlong2/latlong.dart';

/// Currency symbol used when the backend does not state one.
///
/// Zimbabwe is multi-currency (USD/ZIG/ZAR) and money is never rendered bare,
/// so an explicit symbol is always attached. USD is the platform's primary.
const String kDefaultCurrencySymbol = r'US$';

/// Maps an ISO currency code onto the symbol the app renders.
String currencySymbolFor(Object? code) {
  switch (code?.toString().toUpperCase()) {
    case 'ZIG':
    case 'ZWG':
      return 'ZiG';
    case 'ZAR':
      return 'R';
    case 'USD':
      return kDefaultCurrencySymbol;
    default:
      return kDefaultCurrencySymbol;
  }
}

/// Normalises an order state onto its canonical wire spelling.
///
/// Historic documents were written with the enum's `repr`
/// (`"OrderState.CREATED"`), so that spelling is accepted too — this mirrors
/// `coerce_state` in `backend/app/order/state_machine.py`.
String normaliseOrderState(Object? raw) {
  final text = (raw ?? 'CREATED').toString().trim();
  final stripped = text.startsWith('OrderState.')
      ? text.substring('OrderState.'.length)
      : text;
  return stripped.toUpperCase();
}

/// How far through the journey each backend state is.
///
/// Derived from `backend/app/order/state_machine.py`. Two states share a rank
/// when the customer cannot meaningfully tell them apart (`CREATED`/`OFFERED`
/// are both "we have your order, finding a courier";
/// `ARRIVED_AT_MERCHANT`/`READY_FOR_PICKUP` are both "the kitchen stage").
const Map<String, int> kOrderStateRank = <String, int>{
  'CREATED': 0,
  'OFFERED': 0,
  'ACCEPTED': 1,
  'ARRIVED_AT_MERCHANT': 2,
  'READY_FOR_PICKUP': 2,
  'PICKED_UP': 3,
  'ARRIVED_AT_CUSTOMER': 4,
  'DELIVERED': 5,
};

/// Rank of [state], or `-1` for `CANCELLED` / anything unrecognised.
int orderStateRank(String state) => kOrderStateRank[state] ?? -1;

/// True while the order is still moving (not delivered, not cancelled).
bool isActiveOrderState(String state) =>
    kOrderStateRank.containsKey(state) && state != 'DELIVERED';

/// True once the order can never change again.
bool isTerminalOrderState(String state) =>
    state == 'DELIVERED' || state == 'CANCELLED';

/// States a consumer may still self-service cancel from.
///
/// Mirrors `CANCELLABLE_STATES` minus the two the router rejects with an
/// explicit "contact support" message once the courier physically holds the
/// food (`PICKED_UP`, `ARRIVED_AT_CUSTOMER`).
const Set<String> kConsumerCancellableStates = <String>{
  'CREATED',
  'OFFERED',
  'ACCEPTED',
  'ARRIVED_AT_MERCHANT',
  'READY_FOR_PICKUP',
};

/// States in which the consumer may confirm they have the food.
///
/// Mirrors `allowed_states` in `POST /orders/{id}/confirm-delivery`.
const Set<String> kConfirmableStates = <String>{
  'PICKED_UP',
  'ARRIVED_AT_CUSTOMER',
};

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _toInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _toText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _toDate(Object? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString());
  return parsed?.toLocal();
}

/// A coordinate pair, or null when either half is missing or is "null island".
///
/// `(0, 0)` is what an unset location serialises to, and dropping a marker in
/// the Gulf of Guinea is worse than drawing no marker at all.
LatLng? coordinatesFrom(Object? latitude, Object? longitude) {
  final lat = _toDouble(latitude);
  final lng = _toDouble(longitude);
  if (lat == null || lng == null) return null;
  if (lat.abs() < 0.01 && lng.abs() < 0.01) return null;
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  return LatLng(lat, lng);
}

/// One line on an order.
class TrackedOrderItem {
  const TrackedOrderItem({
    required this.name,
    required this.quantity,
    required this.price,
    this.specialInstructions,
  });

  factory TrackedOrderItem.fromJson(Map<String, dynamic> json) {
    return TrackedOrderItem(
      name: _toText(json['name']) ?? 'Item',
      quantity: _toInt(json['quantity']) ?? 1,
      price: _toDouble(json['price']) ?? 0,
      specialInstructions: _toText(json['special_instructions']),
    );
  }

  final String name;
  final int quantity;
  final double price;
  final String? specialInstructions;

  /// Line total.
  double get lineTotal => price * quantity;
}

/// The courier carrying an order, as far as the backend will tell us.
///
/// `name` is the only field the API sends today; the rest are optional and
/// documented as backend gaps in the C3 report.
class TrackedDriver {
  const TrackedDriver({
    required this.id,
    this.name,
    this.phone,
    this.photoUrl,
    this.vehicle,
    this.rating,
    this.ratingCount,
  });

  final String id;
  final String? name;
  final String? phone;
  final String? photoUrl;

  /// Free-text vehicle description, e.g. "Red Honda Ace · ABC 1234".
  final String? vehicle;

  /// Average driver rating, from `GET /rating/drivers/{id}/summary`.
  final double? rating;
  final int? ratingCount;

  /// First name only — that is all a consumer needs, and all we show.
  String get firstName {
    final full = (name ?? '').trim();
    if (full.isEmpty) return 'Your courier';
    return full.split(RegExp(r'\s+')).first;
  }

  /// Single-letter avatar fallback.
  String get initial {
    final full = (name ?? '').trim();
    return full.isEmpty ? '?' : full.substring(0, 1).toUpperCase();
  }

  TrackedDriver copyWith({
    double? rating,
    int? ratingCount,
  }) {
    return TrackedDriver(
      id: id,
      name: name,
      phone: phone,
      photoUrl: photoUrl,
      vehicle: vehicle,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
    );
  }
}

/// An order, as the tracking screen understands it.
class TrackedOrder {
  const TrackedOrder({
    required this.id,
    required this.state,
    required this.totalAmount,
    required this.items,
    this.createdAt,
    this.driver,
    this.driverPosition,
    this.pickup,
    this.destination,
    this.merchantId,
    this.consumerId,
    this.deliveryInstructions,
    this.groupId,
    this.currencySymbol = kDefaultCurrencySymbol,
    this.deliveryFee,
    this.serviceFee,
    this.taxAmount,
    this.tipAmount,
    this.discountAmount,
    this.promoCode,
    this.isPickup = false,
    this.serverEtaMinutes,
  });

  factory TrackedOrder.fromJson(Map<String, dynamic> json) {
    final driverId = _toText(json['driver_id']);
    return TrackedOrder(
      id: _toText(json['id']) ?? _toText(json['_id']) ?? '',
      state: normaliseOrderState(json['state']),
      totalAmount: _toDouble(json['total_amount']) ?? 0,
      createdAt: _toDate(json['created_at']),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => TrackedOrderItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      driver: driverId == null
          ? null
          : TrackedDriver(
              id: driverId,
              name: _toText(json['driver_name']),
              phone: _toText(json['driver_phone']),
              photoUrl: _toText(json['driver_photo_url']),
              vehicle: _toText(json['driver_vehicle']),
              rating: _toDouble(json['driver_rating']),
              ratingCount: _toInt(json['driver_review_count']),
            ),
      driverPosition: coordinatesFrom(json['driver_lat'], json['driver_lng']),
      pickup: coordinatesFrom(json['pickup_lat'], json['pickup_lng']),
      destination: coordinatesFrom(json['delivery_lat'], json['delivery_lng']),
      merchantId: _toText(json['merchant_id']),
      consumerId: _toText(json['consumer_id']),
      deliveryInstructions: _toText(json['delivery_instructions']),
      groupId: _toText(json['group_id']),
      currencySymbol: currencySymbolFor(json['currency']),
      deliveryFee: _toDouble(json['delivery_fee']),
      serviceFee: _toDouble(json['service_fee']),
      taxAmount: _toDouble(json['tax_amount']),
      tipAmount: _toDouble(json['tip_amount']),
      discountAmount: _toDouble(json['discount_amount']),
      promoCode: _toText(json['promo_code']),
      isPickup: json['is_pickup'] == true,
      serverEtaMinutes: _toInt(json['eta_minutes']),
    );
  }

  final String id;
  final String state;
  final double totalAmount;
  final DateTime? createdAt;
  final List<TrackedOrderItem> items;
  final TrackedDriver? driver;

  /// Last known courier position from the order snapshot. The live stream
  /// supersedes this as soon as it delivers a fix.
  final LatLng? driverPosition;
  final LatLng? pickup;
  final LatLng? destination;
  final String? merchantId;
  final String? consumerId;
  final String? deliveryInstructions;
  final String? groupId;
  final String currencySymbol;

  // ── Fee breakdown. Null means "the API did not tell us", never "zero". ──
  final double? deliveryFee;
  final double? serviceFee;
  final double? taxAmount;
  final double? tipAmount;
  final double? discountAmount;
  final String? promoCode;
  final bool isPickup;

  /// Server-supplied ETA in minutes, if the backend ever sends one.
  final int? serverEtaMinutes;

  /// Sum of the line totals.
  double get subtotal =>
      items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  /// True when the API gave us every fee line, so a receipt can be itemised
  /// rather than summarised.
  bool get hasFeeBreakdown =>
      deliveryFee != null && serviceFee != null && taxAmount != null;

  /// Everything charged on top of the food, derived from the authoritative
  /// total when the itemised fees are missing. Never negative.
  double get derivedFees {
    final residual = totalAmount - subtotal + (discountAmount ?? 0);
    return residual > 0.005 ? residual : 0;
  }

  /// Short human reference, e.g. `#A1B2C3`.
  String get shortReference {
    if (id.length <= 6) return '#${id.toUpperCase()}';
    return '#${id.substring(id.length - 6).toUpperCase()}';
  }

  /// One-line summary of the basket, e.g. "2× Sadza · 1× Coke".
  String get itemsSummary {
    if (items.isEmpty) return 'Order $shortReference';
    return items.map((i) => '${i.quantity}× ${i.name}').join(' · ');
  }

  int get itemCount => items.fold<int>(0, (sum, item) => sum + item.quantity);

  /// Map-style field access, by the backend's JSON key names.
  ///
  /// Kept so screens outside this feature that were written against the raw
  /// `Map<String, dynamic>` order payload (e.g. the help screen's order picker)
  /// keep compiling and behaving while they migrate to this typed model.
  /// New code should use the named members.
  Object? operator [](String key) {
    switch (key) {
      case 'id':
      case '_id':
        return id;
      case 'state':
        return state;
      case 'total_amount':
        return totalAmount;
      case 'created_at':
        return createdAt?.toIso8601String();
      case 'driver_id':
        return driver?.id;
      case 'driver_name':
        return driver?.name;
      case 'merchant_id':
        return merchantId;
      case 'consumer_id':
        return consumerId;
      case 'delivery_instructions':
        return deliveryInstructions;
      case 'group_id':
        return groupId;
      case 'pickup_lat':
        return pickup?.latitude;
      case 'pickup_lng':
        return pickup?.longitude;
      case 'delivery_lat':
        return destination?.latitude;
      case 'delivery_lng':
        return destination?.longitude;
      case 'items':
        return [
          for (final item in items)
            {
              'name': item.name,
              'quantity': item.quantity,
              'price': item.price,
            },
        ];
      default:
        return null;
    }
  }

  bool get isCancelled => state == 'CANCELLED';
  bool get isDelivered => state == 'DELIVERED';
  bool get isTerminal => isTerminalOrderState(state);
  bool get isActive => !isTerminal;

  /// True while the consumer can still cancel without contacting support.
  bool get canCancel => kConsumerCancellableStates.contains(state);

  /// True when the "I have my order" button should be offered.
  bool get canConfirmDelivery => kConfirmableStates.contains(state);

  /// Progress through the journey, 0..1. Null once terminal.
  double? get progress {
    if (isTerminal) return null;
    final rank = orderStateRank(state);
    if (rank < 0) return null;
    return (rank / 5).clamp(0.0, 1.0);
  }

  TrackedOrder copyWith({
    LatLng? driverPosition,
    TrackedDriver? driver,
  }) {
    return TrackedOrder(
      id: id,
      state: state,
      totalAmount: totalAmount,
      items: items,
      createdAt: createdAt,
      driver: driver ?? this.driver,
      driverPosition: driverPosition ?? this.driverPosition,
      pickup: pickup,
      destination: destination,
      merchantId: merchantId,
      consumerId: consumerId,
      deliveryInstructions: deliveryInstructions,
      groupId: groupId,
      currencySymbol: currencySymbol,
      deliveryFee: deliveryFee,
      serviceFee: serviceFee,
      taxAmount: taxAmount,
      tipAmount: tipAmount,
      discountAmount: discountAmount,
      promoCode: promoCode,
      isPickup: isPickup,
      serverEtaMinutes: serverEtaMinutes,
    );
  }
}

/// One entry of the order's audit trail (`GET /orders/{id}/events`).
class OrderEventEntry {
  const OrderEventEntry({required this.state, this.timestamp, this.reason});

  factory OrderEventEntry.fromJson(Map<String, dynamic> json) {
    return OrderEventEntry(
      state: normaliseOrderState(json['state']),
      timestamp: _toDate(json['timestamp']),
      reason: _toText(json['reason']),
    );
  }

  final String state;
  final DateTime? timestamp;
  final String? reason;
}

/// The consumer's review of one order (`GET /rating/orders/{id}/review`).
class OrderReview {
  const OrderReview({
    required this.id,
    required this.orderId,
    required this.restaurantRating,
    this.driverRating,
    this.comment,
    this.tags = const [],
    this.createdAt,
  });

  factory OrderReview.fromJson(Map<String, dynamic> json) {
    return OrderReview(
      id: _toText(json['id']) ?? '',
      orderId: _toText(json['order_id']) ?? '',
      restaurantRating: _toInt(json['restaurant_rating']) ?? 0,
      driverRating: _toInt(json['driver_rating']),
      comment: _toText(json['comment']),
      tags: ((json['tags'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      createdAt: _toDate(json['created_at']),
    );
  }

  final String id;
  final String orderId;
  final int restaurantRating;
  final int? driverRating;
  final String? comment;
  final List<String> tags;
  final DateTime? createdAt;
}

/// One chat message on an order thread.
class OrderChatMessage {
  const OrderChatMessage({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.senderRole,
    required this.text,
    this.createdAt,
    this.readBy = const [],
  });

  factory OrderChatMessage.fromJson(Map<String, dynamic> json) {
    return OrderChatMessage(
      id: _toText(json['id']) ?? '',
      orderId: _toText(json['order_id']) ?? '',
      senderId: _toText(json['sender_id']) ?? '',
      senderRole: _toText(json['sender_role']) ?? 'driver',
      text: _toText(json['text']) ?? '',
      createdAt: _toDate(json['created_at']),
      readBy: ((json['read_by'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }

  final String id;
  final String orderId;
  final String senderId;
  final String senderRole;
  final String text;
  final DateTime? createdAt;
  final List<String> readBy;

  /// True when this message came from the signed-in consumer.
  bool isMine(String? myUserId) => myUserId != null && senderId == myUserId;

  /// Who to label an incoming message as.
  String get senderLabel {
    switch (senderRole.toLowerCase()) {
      case 'driver':
        return 'Courier';
      case 'merchant':
        return 'Restaurant';
      case 'consumer':
        return 'You';
      default:
        return 'Support';
    }
  }
}
