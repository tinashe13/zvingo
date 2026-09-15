/// Live order transport: Server-Sent Events with a polling floor underneath.
///
/// ## The rule this file exists to enforce
///
/// **A tracking screen that has quietly stopped updating is worse than one that
/// says so.** Every failure path here ends in one of two places: a successful
/// poll, or a visible "we are not live right now" status. There is no path
/// where the screen keeps rendering a stale ETA as if it were fresh.
///
/// ## Two streams, one authority
///
/// * **Order lifecycle** — `GET /notification/events/consumer_{consumerId}`.
///   The payload is only `{event, order_id, timestamp}`, so it is treated as a
///   *signal*: when an event names our order we immediately re-fetch
///   `GET /orders/{id}` over the authenticated REST API and trust that. The
///   stream is never the source of truth, which also means a malformed or
///   spoofed event can at worst cause one redundant fetch.
/// * **Courier position** — `GET /location/driver/{driverId}/track`, which
///   carries real coordinates (`{lat, lng, ts}`) and is applied directly.
///
/// ## Resilience
///
/// | Concern | Behaviour |
/// |---|---|
/// | Connect fails / drops | Exponential backoff 1s → 30s with ±20% jitter, reset on the first event |
/// | SSE never works at all | Polling continues forever at the degraded interval |
/// | SSE healthy | Polling drops to a slow safety net, so a silently dead stream is still caught |
/// | App backgrounded | Streams closed and timers cancelled; nothing burns battery |
/// | App resumed | Immediate poll + reconnect with the backoff reset |
/// | Order reaches a terminal state | Everything is torn down — a delivered order has nothing left to stream |
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import 'package:consumer_app/features/order/order_models.dart';
import 'package:consumer_app/features/order/order_timeline.dart';

/// How live the tracking screen currently is.
enum OrderConnectionStatus {
  /// First load, or reconnecting after a drop.
  connecting,

  /// The event stream is open and delivering.
  live,

  /// The stream is down but polling is still succeeding. Updates are slower,
  /// not absent — the banner says so rather than pretending.
  degraded,

  /// Neither the stream nor polling can reach the server.
  offline,

  /// The order is finished; there is nothing left to track.
  closed,
}

/// Everything the tracking UI needs, in one immutable value.
@immutable
class OrderTrackingState {
  const OrderTrackingState({
    required this.orderId,
    required this.status,
    required this.eta,
    this.order,
    this.driverPosition,
    this.lastUpdate,
    this.error,
  });

  final String orderId;
  final OrderConnectionStatus status;
  final TrackedOrder? order;

  /// Freshest courier position: the live stream's fix when there is one,
  /// otherwise the snapshot's.
  final LatLng? driverPosition;

  /// When the order snapshot was last successfully refreshed.
  final DateTime? lastUpdate;

  /// The estimate, already smoothed. Never a fabricated number.
  final OrderEta eta;

  /// The last transport error, for [ZvErrorState]-style copy. Never rendered raw.
  final Object? error;

  bool get hasOrder => order != null;

  /// True when the last successful refresh is old enough that the user should
  /// be told, rather than left looking at a confident stale number.
  bool get isStale {
    final last = lastUpdate;
    if (last == null) return status != OrderConnectionStatus.connecting;
    return DateTime.now().difference(last) > const Duration(seconds: 75);
  }

  /// Non-blocking banner copy, or null when everything is healthy.
  String? get connectionMessage {
    switch (status) {
      case OrderConnectionStatus.live:
      case OrderConnectionStatus.closed:
        return null;
      case OrderConnectionStatus.connecting:
        return hasOrder ? 'Reconnecting to live updates…' : null;
      case OrderConnectionStatus.degraded:
        return 'Live updates paused. Refreshing every few seconds instead.';
      case OrderConnectionStatus.offline:
        // With no order loaded the full-screen error state already explains
        // it; a banner on top of that is noise.
        return hasOrder
            ? "Can't reach Zvingo right now. We keep retrying — this screen "
                'may be out of date.'
            : null;
    }
  }

  OrderTrackingState copyWith({
    OrderConnectionStatus? status,
    TrackedOrder? order,
    LatLng? driverPosition,
    DateTime? lastUpdate,
    OrderEta? eta,
    Object? error,
    bool clearError = false,
  }) {
    return OrderTrackingState(
      orderId: orderId,
      status: status ?? this.status,
      order: order ?? this.order,
      driverPosition: driverPosition ?? this.driverPosition,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      eta: eta ?? this.eta,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Minimal Server-Sent Events decoder over a Dio byte stream.
///
/// `flutter_client_sse` was the previous transport. It is not used here because
/// its `unsubscribeFromSSE()` closes the process-wide client, so closing one
/// order's stream also killed every other one — with two maps and a shell
/// overlay open at once that silently stopped tracking. Owning the parsing
/// gives per-connection cancellation, the app's own `Authorization` header via
/// the shared Dio interceptor, and control of the receive timeout.
class SseConnection {
  SseConnection._(this._subscription, this._cancelToken, this._markClosed);

  final StreamSubscription<String> _subscription;
  final CancelToken _cancelToken;

  /// Silences this connection's callbacks. Cancelling a Dio stream surfaces as
  /// an error on the subscription; without this, closing an old connection
  /// would fire the caller's "stream lost" handler and tear down the *new*
  /// one, which is how reconnect loops start.
  final void Function() _markClosed;

  /// Opens [path] on [dio] and calls [onEvent] for every SSE event.
  ///
  /// [onEvent] receives `(eventName, data)`. Comment lines and empty data
  /// frames are dropped. Throws if the connection cannot be established, so
  /// the caller can apply its backoff.
  static Future<SseConnection> connect(
    Dio dio,
    String path, {
    Map<String, dynamic>? queryParameters,
    required void Function(String event, String data) onEvent,
    required void Function(Object error) onError,
    required VoidCallback onDone,
  }) async {
    final cancelToken = CancelToken();
    var closed = false;
    final response = await dio.get<ResponseBody>(
      path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: const {
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
        },
        // An SSE connection is idle by design between events. The app-wide
        // 20s receive timeout would tear it down between keepalives.
        receiveTimeout: Duration.zero,
      ),
    );

    final body = response.data;
    if (body == null) {
      cancelToken.cancel();
      throw StateError('Event stream returned no body');
    }

    var eventName = 'message';
    final data = StringBuffer();

    void flush() {
      final payload = data.toString();
      data.clear();
      final name = eventName;
      eventName = 'message';
      if (payload.isEmpty) return;
      onEvent(name, payload);
    }

    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final subscription = lines.listen(
      (line) {
        if (closed) return;
        if (line.isEmpty) {
          flush();
          return;
        }
        if (line.startsWith(':')) return; // comment / keepalive
        final separator = line.indexOf(':');
        final field = separator == -1 ? line : line.substring(0, separator);
        var value = separator == -1 ? '' : line.substring(separator + 1);
        if (value.startsWith(' ')) value = value.substring(1);
        switch (field) {
          case 'event':
            eventName = value;
            break;
          case 'data':
            if (data.isNotEmpty) data.write('\n');
            data.write(value);
            break;
          default:
            break; // id / retry are not used by this backend
        }
      },
      onError: (Object error, StackTrace _) {
        if (!closed) onError(error);
      },
      onDone: () {
        if (!closed) onDone();
      },
      cancelOnError: true,
    );

    return SseConnection._(subscription, cancelToken, () => closed = true);
  }

  /// Closes this connection only. Other streams are unaffected, and this
  /// connection's callbacks never fire again.
  Future<void> close() async {
    _markClosed();
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('closed');
    }
    await _subscription.cancel();
  }
}

/// Owns the live view of one order.
///
/// Created per order id and shared by everything that needs it — the tracking
/// screen, the map, and the shell banner all read the same tracker, so an
/// order is fetched and streamed exactly once no matter how many widgets are
/// watching.
class OrderTracker with WidgetsBindingObserver {
  OrderTracker({required Dio dio, required this.orderId}) : _dio = dio;

  final Dio _dio;
  final String orderId;

  /// Slow safety net while the stream is healthy — catches a stream that has
  /// silently stopped delivering without the socket closing.
  static const Duration _healthyPollInterval = Duration(seconds: 25);

  /// Used while the stream is down. Fast enough to feel live.
  static const Duration _degradedPollInterval = Duration(seconds: 5);

  static const Duration _minBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);

  final StreamController<OrderTrackingState> _controller =
      StreamController<OrderTrackingState>.broadcast();
  final OrderEtaEstimator _estimator = OrderEtaEstimator();
  final Random _random = Random();

  OrderTrackingState? _latest;
  SseConnection? _orderStream;
  SseConnection? _driverStream;
  Timer? _pollTimer;
  Timer? _orderRetryTimer;
  Timer? _driverRetryTimer;
  Timer? _staleTicker;
  int _orderAttempt = 0;
  int _driverAttempt = 0;
  String? _streamingDriverId;
  bool _started = false;
  bool _disposed = false;
  bool _fetching = false;
  bool _backgrounded = false;

  /// The current value, or null before the first fetch resolves.
  OrderTrackingState? get latest => _latest;

  /// Broadcast stream that replays the latest value to every new listener.
  Stream<OrderTrackingState> get stream async* {
    final current = _latest;
    if (current != null) yield current;
    yield* _controller.stream;
  }

  /// Begins tracking. Safe to call more than once.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _emit(
      OrderTrackingState(
        orderId: orderId,
        status: OrderConnectionStatus.connecting,
        eta: OrderEta.unknown,
      ),
    );
    unawaited(_refresh());
    _schedulePoll(_degradedPollInterval);
    // Re-emit periodically so "last updated 2 min ago" copy stays truthful
    // even when nothing new arrives.
    _staleTicker = Timer.periodic(const Duration(seconds: 20), (_) {
      final current = _latest;
      if (current != null) _emit(current);
    });
  }

  /// Pull once, now — the pull-to-refresh and "Try again" path.
  Future<void> refreshNow() => _refresh();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_backgrounded) return;
        _backgrounded = false;
        // Resume cleanly: a fresh snapshot first so the screen is correct
        // within one frame, then rebuild the streams from scratch. Backoff is
        // reset because "the app was in the background" is not a server fault.
        _orderAttempt = 0;
        _driverAttempt = 0;
        unawaited(_refresh());
        _openOrderStream();
        final driverId = _latest?.order?.driver?.id;
        if (driverId != null) _openDriverStream(driverId);
        _schedulePoll(_degradedPollInterval);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_backgrounded) return;
        _backgrounded = true;
        _teardownConnections();
        break;
      case AppLifecycleState.inactive:
        break; // a transient overlay, not a real background
    }
  }

  // ── Snapshot ────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    if (_disposed || _fetching) return;
    _fetching = true;
    try {
      final response = await _dio.get<dynamic>('/orders/$orderId');
      final raw = response.data;
      if (raw is! Map) throw StateError('Unexpected order payload');
      final order = TrackedOrder.fromJson(Map<String, dynamic>.from(raw));
      _applyOrder(order);
    } catch (error) {
      if (_disposed) return;
      final current = _latest;
      _emit(
        (current ??
                OrderTrackingState(
                  orderId: orderId,
                  status: OrderConnectionStatus.offline,
                  eta: OrderEta.unknown,
                ))
            .copyWith(
          status: _orderStream != null
              ? OrderConnectionStatus.degraded
              : OrderConnectionStatus.offline,
          error: error,
        ),
      );
    } finally {
      _fetching = false;
    }
  }

  /// Connection status implied by the current stream state.
  ///
  /// "Not open yet" on the very first attempt is *connecting*, not *degraded*
  /// — the banner should not accuse the network before we have tried once.
  OrderConnectionStatus _streamStatus() {
    if (_orderStream != null) return OrderConnectionStatus.live;
    if (_orderAttempt == 0) return OrderConnectionStatus.connecting;
    return OrderConnectionStatus.degraded;
  }

  void _applyOrder(TrackedOrder order) {
    if (_disposed) return;
    final previous = _latest;
    final position = order.driverPosition ?? previous?.driverPosition;

    if (order.isTerminal) {
      _estimator.reset();
      _teardownConnections();
      _pollTimer?.cancel();
      _emit(
        OrderTrackingState(
          orderId: orderId,
          status: OrderConnectionStatus.closed,
          order: order,
          driverPosition: order.driverPosition ?? previous?.driverPosition,
          lastUpdate: DateTime.now(),
          eta: OrderEta.finished,
        ),
      );
      return;
    }

    _emit(
      OrderTrackingState(
        orderId: orderId,
        status: _streamStatus(),
        order: order,
        driverPosition: position,
        lastUpdate: DateTime.now(),
        eta: _estimator.estimate(order, driverPosition: position),
      ),
    );

    // The consumer id only arrives with the snapshot, and it is what names the
    // lifecycle channel — so the stream can only open once state is applied.
    if (_orderStream == null && _orderRetryTimer == null && !_backgrounded) {
      _openOrderStream();
    }
    final driverId = order.driver?.id;
    if (driverId != null && driverId != _streamingDriverId) {
      _openDriverStream(driverId);
    }

    _schedulePoll(
      _orderStream != null ? _healthyPollInterval : _degradedPollInterval,
    );
  }

  void _schedulePoll(Duration interval) {
    _pollTimer?.cancel();
    if (_disposed || _backgrounded) return;
    if (_latest?.order?.isTerminal ?? false) return;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(_refresh()));
  }

  // ── Order lifecycle stream ──────────────────────────────────────────────

  void _openOrderStream() {
    final consumerId = _latest?.order?.consumerId;
    if (consumerId == null || _disposed || _backgrounded) return;
    unawaited(_orderStream?.close());
    _orderStream = null;
    _orderRetryTimer?.cancel();
    _orderRetryTimer = null;

    unawaited(
      SseConnection.connect(
        _dio,
        '/notification/events/consumer_$consumerId',
        onEvent: _onOrderEvent,
        onError: (_) => _onOrderStreamLost(),
        onDone: _onOrderStreamLost,
      ).then((connection) {
        if (_disposed || _backgrounded) {
          unawaited(connection.close());
          return;
        }
        _orderStream = connection;
        _orderAttempt = 0;
        final current = _latest;
        if (current != null && current.order?.isTerminal != true) {
          _emit(current.copyWith(
            status: OrderConnectionStatus.live,
            clearError: true,
          ));
          _schedulePoll(_healthyPollInterval);
        }
      }).catchError((Object _) => _onOrderStreamLost()),
    );
  }

  void _onOrderEvent(String event, String data) {
    if (_disposed) return;
    if (event == 'ping' || event == 'connected') return;
    // The payload carries no authorisation context, so it is a hint only: if
    // it names our order we re-read the authenticated REST resource.
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map && decoded['order_id'] != null) {
        if (decoded['order_id'].toString() != orderId) return;
      }
    } catch (_) {
      // Undecodable payload: refresh anyway, the REST call is the authority.
    }
    unawaited(_refresh());
  }

  void _onOrderStreamLost() {
    if (_disposed) return;
    unawaited(_orderStream?.close());
    _orderStream = null;
    final current = _latest;
    if (current != null && (current.order?.isTerminal ?? false)) return;
    if (current != null) {
      _emit(current.copyWith(status: OrderConnectionStatus.degraded));
    }
    // Polling takes over immediately so the screen never goes quiet.
    _schedulePoll(_degradedPollInterval);
    if (_backgrounded) return;
    _orderRetryTimer?.cancel();
    _orderRetryTimer = Timer(_backoff(_orderAttempt++), _openOrderStream);
  }

  // ── Courier position stream ─────────────────────────────────────────────

  void _openDriverStream(String driverId) {
    if (_disposed || _backgrounded) return;
    _streamingDriverId = driverId;
    unawaited(_driverStream?.close());
    _driverStream = null;
    _driverRetryTimer?.cancel();

    unawaited(
      SseConnection.connect(
        _dio,
        '/location/driver/$driverId/track',
        onEvent: _onDriverEvent,
        onError: (_) => _onDriverStreamLost(driverId),
        onDone: () => _onDriverStreamLost(driverId),
      ).then((connection) {
        if (_disposed || _backgrounded || _streamingDriverId != driverId) {
          unawaited(connection.close());
          return;
        }
        _driverStream = connection;
        _driverAttempt = 0;
      }).catchError((Object _) => _onDriverStreamLost(driverId)),
    );
  }

  void _onDriverEvent(String event, String data) {
    if (_disposed || event == 'ping') return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      final position = coordinatesFrom(decoded['lat'], decoded['lng']);
      if (position == null) return;
      final current = _latest;
      if (current?.order == null) return;
      _emit(
        current!.copyWith(
          driverPosition: position,
          lastUpdate: DateTime.now(),
          eta: _estimator.estimate(current.order!, driverPosition: position),
          clearError: true,
        ),
      );
    } catch (_) {
      // A malformed position must never interrupt tracking.
    }
  }

  void _onDriverStreamLost(String driverId) {
    if (_disposed || _streamingDriverId != driverId) return;
    unawaited(_driverStream?.close());
    _driverStream = null;
    if (_backgrounded) return;
    // The snapshot poll still carries `driver_lat`/`driver_lng`, so position
    // degrades to the poll cadence rather than freezing.
    _driverRetryTimer?.cancel();
    _driverRetryTimer =
        Timer(_backoff(_driverAttempt++), () => _openDriverStream(driverId));
  }

  // ── Plumbing ────────────────────────────────────────────────────────────

  /// Exponential backoff with ±20% jitter so a server restart does not bring
  /// every client back in the same millisecond.
  Duration _backoff(int attempt) {
    final base = _minBackoff.inMilliseconds * pow(2, attempt.clamp(0, 5));
    final capped = min(base.toDouble(), _maxBackoff.inMilliseconds.toDouble());
    final jitter = capped * (0.8 + _random.nextDouble() * 0.4);
    return Duration(milliseconds: jitter.round());
  }

  void _emit(OrderTrackingState state) {
    _latest = state;
    if (!_controller.isClosed) _controller.add(state);
  }

  void _teardownConnections() {
    _orderRetryTimer?.cancel();
    _driverRetryTimer?.cancel();
    unawaited(_orderStream?.close());
    unawaited(_driverStream?.close());
    _orderStream = null;
    _driverStream = null;
    _streamingDriverId = null;
    _pollTimer?.cancel();
  }

  /// Releases every timer, stream and observer.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _staleTicker?.cancel();
    _teardownConnections();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.close());
  }
}
