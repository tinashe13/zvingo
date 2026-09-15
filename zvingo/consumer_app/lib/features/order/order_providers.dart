/// Riverpod wiring for the order feature.
///
/// Deliberately hand-written rather than generated: the feature needs a
/// long-lived object with its own timers and sockets ([OrderTracker]) shared
/// between several widgets, which is a `Provider.autoDispose.family` returning
/// a plain object — not something `@riverpod` expresses more clearly. It also
/// keeps the pinned `riverpod_generator` from emitting more deprecated
/// `AutoDisposeProviderRef` typedefs into `*.g.dart`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/order/order_models.dart';
import 'package:consumer_app/features/order/order_tracking_transport.dart';

/// The signed-in consumer's user id, used to tell "my" chat messages apart.
///
/// Cached for the session — it never changes while a user is signed in.
final currentUserIdProvider = FutureProvider<String?>((ref) async {
  final dio = ref.watch(apiClientProvider);
  if (Hive.box('settings').get('access_token') == null) return null;
  try {
    final response = await dio.get<dynamic>('/auth/me');
    final data = response.data;
    if (data is Map) return data['id']?.toString();
  } catch (_) {
    // Not fatal: chat still renders, it just cannot mark a bubble as ours
    // until the next successful call.
  }
  return null;
});

/// The live tracker for one order.
///
/// `autoDispose` means the sockets and timers die with the last listener, and
/// the `family` means two widgets watching the same order share one connection.
final orderTrackerProvider =
    Provider.autoDispose.family<OrderTracker, String>((ref, orderId) {
  final tracker = OrderTracker(dio: ref.watch(apiClientProvider), orderId: orderId);
  ref.onDispose(tracker.dispose);
  tracker.start();
  return tracker;
});

/// The live state of one order: snapshot, courier position, ETA, connection.
final orderTrackingProvider = StreamProvider.autoDispose
    .family<OrderTrackingState, String>((ref, orderId) {
  return ref.watch(orderTrackerProvider(orderId)).stream;
});

/// The order's audit trail, used to timestamp the timeline nodes.
final orderEventsProvider = FutureProvider.autoDispose
    .family<List<OrderEventEntry>, String>((ref, orderId) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get<dynamic>('/orders/$orderId/events');
  final data = response.data;
  if (data is! List) return const [];
  return data
      .whereType<Map>()
      .map((e) => OrderEventEntry.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
});

/// The consumer's own review of an order, or null when they have not left one.
///
/// Backed by `GET /rating/orders/{id}/review`, so the app can say "You rated
/// this 5★" instead of prompting twice. One review per order is enforced by a
/// unique index server-side; this is the client half of that contract.
final orderReviewProvider =
    FutureProvider.autoDispose.family<OrderReview?, String>((ref, orderId) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final response = await dio.get<dynamic>('/rating/orders/$orderId/review');
    final data = response.data;
    if (data is Map && data.isNotEmpty) {
      return OrderReview.fromJson(Map<String, dynamic>.from(data));
    }
  } on DioException catch (error) {
    // A 404 here means "no such order for you", not "no review" — either way
    // the caller treats it as "nothing to show".
    if (error.response?.statusCode != 404) rethrow;
  }
  return null;
});

/// A courier's public rating, from `GET /rating/drivers/{id}/summary`.
@immutable
class DriverRatingSummary {
  const DriverRatingSummary({this.rating, this.reviewCount});

  final double? rating;
  final int? reviewCount;

  bool get hasRating => rating != null && rating! > 0;
}

/// Public rating summary for a courier. Never throws — a missing rating is a
/// cosmetic gap, not an error worth breaking the tracking screen over.
final driverRatingProvider = FutureProvider.autoDispose
    .family<DriverRatingSummary, String>((ref, driverId) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final response = await dio.get<dynamic>('/rating/drivers/$driverId/summary');
    final data = response.data;
    if (data is Map) {
      final rating = data['driver_rating'];
      final count = data['driver_review_count'];
      return DriverRatingSummary(
        rating: rating is num ? rating.toDouble() : null,
        reviewCount: count is num ? count.toInt() : null,
      );
    }
  } catch (_) {
    // Fall through to the empty summary.
  }
  return const DriverRatingSummary();
});

/// The restaurant behind an order — name, photo and address for the tracking
/// header and the receipt.
@immutable
class OrderRestaurant {
  const OrderRestaurant({
    required this.id,
    required this.name,
    this.imageUrl,
    this.address,
    this.rating,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final String? address;
  final double? rating;
}

/// Restaurant lookup by merchant id. Returns null rather than throwing when
/// the restaurant has been removed — the order still has to render.
final orderRestaurantProvider = FutureProvider.autoDispose
    .family<OrderRestaurant?, String>((ref, merchantId) async {
  if (merchantId.isEmpty) return null;
  final dio = ref.watch(apiClientProvider);
  try {
    final response = await dio.get<dynamic>('/catalog/restaurants/$merchantId');
    final data = response.data;
    if (data is! Map) return null;
    final rating = data['rating'];
    final address = data['address']?.toString().trim();
    return OrderRestaurant(
      id: merchantId,
      name: (data['name'] ?? 'Restaurant').toString(),
      imageUrl: (data['image_url'] ?? data['banner_url'])?.toString(),
      address: (address == null || address.isEmpty) ? null : address,
      rating: rating is num ? rating.toDouble() : null,
    );
  } catch (_) {
    return null;
  }
});

/// Every order the signed-in consumer has placed, newest first.
final consumerOrdersProvider =
    FutureProvider.autoDispose<List<TrackedOrder>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  if (Hive.box('settings').get('access_token') == null) return const [];
  final me = await dio.get<dynamic>('/auth/me');
  final userId = (me.data as Map)['id'];
  final response = await dio.get<dynamic>('/orders/consumer/$userId');
  final data = response.data;
  if (data is! List) return const [];
  return data
      .whereType<Map>()
      .map((e) => TrackedOrder.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
});

/// Orders still in flight, newest first.
final activeConsumerOrdersProvider =
    Provider.autoDispose<AsyncValue<List<TrackedOrder>>>((ref) {
  return ref.watch(consumerOrdersProvider).whenData(
        (orders) => orders.where((o) => o.isActive).toList(growable: false),
      );
});

/// Delivered and cancelled orders, newest first.
final pastConsumerOrdersProvider =
    Provider.autoDispose<AsyncValue<List<TrackedOrder>>>((ref) {
  return ref.watch(consumerOrdersProvider).whenData(
        (orders) => orders.where((o) => o.isTerminal).toList(growable: false),
      );
});

// ── Chat ──────────────────────────────────────────────────────────────────

/// The state of one order's chat thread.
@immutable
class OrderChatState {
  const OrderChatState({
    this.messages = const [],
    this.loading = true,
    this.live = false,
    this.error,
  });

  final List<OrderChatMessage> messages;
  final bool loading;

  /// True when the SSE stream is connected. False means polling only — the
  /// composer still works, messages just land a little later.
  final bool live;
  final Object? error;

  int unreadFor(String? userId) {
    if (userId == null) return 0;
    return messages
        .where((m) => m.senderId != userId && !m.readBy.contains(userId))
        .length;
  }

  OrderChatState copyWith({
    List<OrderChatMessage>? messages,
    bool? loading,
    bool? live,
    Object? error,
    bool clearError = false,
  }) {
    return OrderChatState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      live: live ?? this.live,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns one order's chat thread: history, live stream, polling fallback and
/// sending.
///
/// Contract (`backend/app/chat/router.py`):
/// * `GET  /chat/orders/{id}/messages?offset&limit` — history, oldest first
/// * `POST /chat/orders/{id}/messages` `{"text": "..."}` — send (409 once the
///   order is delivered or cancelled: the thread becomes read-only)
/// * `GET  /chat/orders/{id}/stream` — SSE: `connected`, `message`, `ping`
/// * `POST /chat/orders/{id}/messages/read` — mark the thread read
class OrderChatController extends StateNotifier<OrderChatState> {
  OrderChatController({required Dio dio, required this.orderId})
      : _dio = dio,
        super(const OrderChatState()) {
    _load();
    _openStream();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!state.live) unawaited(_load(silent: true));
    });
  }

  final Dio _dio;
  final String orderId;

  SseConnection? _stream;
  Timer? _poll;
  Timer? _retry;
  int _attempt = 0;
  bool _closed = false;

  Future<void> _load({bool silent = false}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/chat/orders/$orderId/messages',
        queryParameters: const {'limit': 200},
      );
      final data = response.data;
      if (_closed) return;
      final messages = (data is List)
          ? data
              .whereType<Map>()
              .map((e) => OrderChatMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <OrderChatMessage>[];
      state = state.copyWith(
        messages: messages,
        loading: false,
        clearError: true,
      );
    } catch (error) {
      if (_closed) return;
      state = state.copyWith(
        loading: false,
        error: silent && state.messages.isNotEmpty ? null : error,
      );
    }
  }

  void _openStream() {
    if (_closed) return;
    unawaited(
      SseConnection.connect(
        _dio,
        '/chat/orders/$orderId/stream',
        onEvent: _onEvent,
        onError: (_) => _onStreamLost(),
        onDone: _onStreamLost,
      ).then((connection) {
        if (_closed) {
          unawaited(connection.close());
          return;
        }
        _stream = connection;
        _attempt = 0;
        state = state.copyWith(live: true);
      }).catchError((Object _) => _onStreamLost()),
    );
  }

  void _onEvent(String event, String data) {
    if (_closed || event == 'ping' || event == 'connected') return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      if (decoded['event'] == 'read') return;
      final message =
          OrderChatMessage.fromJson(Map<String, dynamic>.from(decoded));
      if (message.id.isEmpty) return;
      if (state.messages.any((m) => m.id == message.id)) return;
      state = state.copyWith(
        messages: [...state.messages, message],
        loading: false,
        clearError: true,
      );
    } catch (_) {
      // A malformed frame must not break the thread — the poll will catch up.
    }
  }

  void _onStreamLost() {
    if (_closed) return;
    unawaited(_stream?.close());
    _stream = null;
    state = state.copyWith(live: false);
    unawaited(_load(silent: true));
    _retry?.cancel();
    _retry = Timer(
      Duration(seconds: [1, 2, 4, 8, 15, 30][_attempt.clamp(0, 5)]),
      () {
        _attempt++;
        _openStream();
      },
    );
  }

  /// Sends a message. Throws so the composer can surface a real failure.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final response = await _dio.post<dynamic>(
      '/chat/orders/$orderId/messages',
      data: {'text': trimmed},
    );
    final data = response.data;
    if (_closed || data is! Map) return;
    final message = OrderChatMessage.fromJson(Map<String, dynamic>.from(data));
    if (state.messages.any((m) => m.id == message.id)) return;
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// Marks every incoming message as read. Idempotent server-side.
  Future<void> markRead() async {
    try {
      await _dio.post<dynamic>('/chat/orders/$orderId/messages/read');
      if (_closed) return;
      await _load(silent: true);
    } catch (_) {
      // Read receipts are best-effort.
    }
  }

  /// Re-runs the history fetch after an error.
  Future<void> retry() async {
    state = state.copyWith(loading: true, clearError: true);
    await _load();
    if (_stream == null) _openStream();
  }

  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    _retry?.cancel();
    unawaited(_stream?.close());
    super.dispose();
  }
}

/// One chat controller per order, disposed with its last listener.
final orderChatProvider = StateNotifierProvider.autoDispose
    .family<OrderChatController, OrderChatState, String>((ref, orderId) {
  return OrderChatController(dio: ref.watch(apiClientProvider), orderId: orderId);
});

/// Unread-message count for an order's thread, polled independently of the
/// chat sheet so the tracking screen can badge its Message button.
///
/// Backed by `GET /chat/orders/{id}/messages/unread`.
final orderChatUnreadProvider =
    StreamProvider.autoDispose.family<int, String>((ref, orderId) {
  final dio = ref.watch(apiClientProvider);

  Future<int> fetch() async {
    try {
      final response =
          await dio.get<dynamic>('/chat/orders/$orderId/messages/unread');
      final data = response.data;
      if (data is Map && data['unread_count'] is num) {
        return (data['unread_count'] as num).toInt();
      }
    } catch (_) {
      // Treated as "no badge" — a badge is not worth an error state.
    }
    return 0;
  }

  final controller = StreamController<int>();
  Timer? timer;

  Future<void> tick() async {
    final value = await fetch();
    if (!controller.isClosed) controller.add(value);
  }

  unawaited(tick());
  timer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(tick()));
  ref.onDispose(() {
    timer?.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});

// ── Mutations ─────────────────────────────────────────────────────────────

/// The write side of the order feature: cancel, confirm, reorder, review.
///
/// Every method throws on failure so the caller can show real copy instead of
/// swallowing the error, and every method invalidates exactly what it changed.
class OrderActions {
  const OrderActions(this._ref);

  final Ref _ref;

  Dio get _dio => _ref.read(apiClientProvider);

  /// `POST /orders/{id}/cancel`. The backend refuses once the courier has the
  /// food, with a plain-language reason the UI surfaces as-is.
  Future<void> cancel(String orderId) async {
    await _dio.post<dynamic>('/orders/$orderId/cancel');
    _ref.invalidate(consumerOrdersProvider);
    await _ref.read(orderTrackerProvider(orderId)).refreshNow();
  }

  /// `POST /orders/{id}/confirm-delivery`.
  Future<void> confirmDelivery(String orderId) async {
    await _dio.post<dynamic>('/orders/$orderId/confirm-delivery');
    _ref.invalidate(consumerOrdersProvider);
    await _ref.read(orderTrackerProvider(orderId)).refreshNow();
  }

  /// `POST /orders/{id}/reorder` — places a brand-new order from a past one
  /// and returns its id so the caller can jump straight to tracking.
  Future<String> reorder(String orderId) async {
    final response = await _dio.post<dynamic>('/orders/$orderId/reorder');
    final data = response.data;
    if (data is! Map || data['id'] == null) {
      throw StateError('Reorder did not return a new order');
    }
    _ref.invalidate(consumerOrdersProvider);
    return data['id'].toString();
  }

  /// `POST /rating/orders/{id}/review`.
  ///
  /// `restaurant_rating` is required (1–5); `driver_rating` is optional and
  /// rejected with a 400 when the order had no courier.
  Future<void> submitReview(
    String orderId, {
    required int restaurantRating,
    int? driverRating,
    String? comment,
    List<String> tags = const [],
  }) async {
    await _dio.post<dynamic>(
      '/rating/orders/$orderId/review',
      data: {
        'restaurant_rating': restaurantRating,
        if (driverRating != null) 'driver_rating': driverRating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
        if (tags.isNotEmpty) 'tags': tags,
      },
    );
    _ref.invalidate(orderReviewProvider(orderId));
  }
}

/// The order feature's mutations.
final orderActionsProvider = Provider<OrderActions>(OrderActions.new);

/// Turns a thrown API error into copy a hungry person can act on.
///
/// The backend's 400/409 `detail` strings for orders are already written in
/// plain language ("Your order has already been picked up. Contact support…"),
/// so they are surfaced verbatim; everything else gets a generic sentence.
/// A raw exception or status code is never shown (§5.5).
String orderErrorMessage(Object error, {required String fallback}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      final detail = (data['detail'] as String).trim();
      if (detail.isNotEmpty && detail.length < 240) return detail;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'That took too long. Check your connection and try again.';
      case DioExceptionType.connectionError:
        return "We couldn't reach Zvingo. Check your connection and try again.";
      default:
        break;
    }
  }
  return fallback;
}
