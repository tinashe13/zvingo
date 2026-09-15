import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/app_config.dart';
import '../models/order_offer.dart';
// `ConnectionStatus` is owned by the banner that renders it. Importing it here
// rather than redefining it keeps one vocabulary between the transport and the
// UI — there is no mapping layer to get out of sync.
import '../widgets/connection_status_banner.dart';

/// Why the backend refused something the driver did.
///
/// The dispatch WebSocket answers a rejected `accept_offer` /
/// `delivery_action` with `{"type":"error","code":…}`. Before this existed the
/// client logged `Unknown event "error"` and the offer card just hung on an
/// order the driver was never going to get.
enum PubSubErrorCode {
  /// Another driver claimed the order first, or it was cancelled.
  offerUnavailable,

  /// The order could not be moved to the requested state.
  deliveryActionRejected,

  /// Anything the server adds later.
  unknown;

  static PubSubErrorCode fromWire(String? code) => switch (code) {
        'offer_unavailable' => PubSubErrorCode.offerUnavailable,
        'delivery_action_rejected' => PubSubErrorCode.deliveryActionRejected,
        _ => PubSubErrorCode.unknown,
      };
}

/// A refusal pushed by the backend over the socket.
@immutable
class PubSubError {
  final PubSubErrorCode code;
  final String orderId;

  /// The server's own wording. Never shown to a driver verbatim — the provider
  /// maps [code] to plain language and keeps this for logs.
  final String detail;

  const PubSubError({
    required this.code,
    required this.orderId,
    required this.detail,
  });

  @override
  String toString() => 'PubSubError($code, order=$orderId, detail=$detail)';
}

/// Bidirectional pub/sub over a single authenticated WebSocket.
///
/// The driver app is both subscriber (offers, order updates, refusals) and
/// publisher (location, accept/decline, delivery progress).
///
/// ## Why this file is defensive
///
/// A dropped socket means missed offers, which means a driver earns nothing
/// for the hour they spent on the road. The connection therefore has to
/// survive the things that actually happen to a phone on a motorbike in
/// Harare: cell handovers, a tunnel, the screen locking, the OS freezing the
/// process, a proxy silently reaping an idle connection, and a captive-portal
/// Wi-Fi that accepts TCP and then eats every frame.
///
/// Five mechanisms, each aimed at one of those:
///
/// 1. **Exponential backoff with jitter.** 1s → 30s, ×1.8, ±25% jitter so a
///    fleet coming back after a backend restart does not stampede it.
/// 2. **A liveness watchdog.** The server pings every 20s
///    (`PING_INTERVAL` in `dispatch/ws_router.py`). If nothing arrives for
///    [_inboundTimeout] the socket is *half-open* — TCP thinks it is fine and
///    no `onDone` will ever fire — so it is torn down and rebuilt. This is the
///    failure mode that silently costs drivers offers.
/// 3. **An outbound keepalive.** A `pong` every [_keepAliveInterval] of
///    silence. The server treats `pong` as a no-op ack, so this costs nothing
///    and stops NATs/proxies dropping an idle socket.
/// 4. **Lifecycle resume.** On `AppLifecycleState.resumed` the socket is
///    verified immediately rather than waiting out a backoff window, because
///    the OS routinely kills sockets while the app is frozen.
/// 5. **Connectivity awareness.** While the radio reports no network, retrying
///    is pointless: backoff is parked and the banner says *offline* rather than
///    *reconnecting*. The moment connectivity returns the socket is rebuilt at
///    once instead of finishing a 30-second sleep.
///
/// ## Authentication
///
/// The socket is opened with the driver's JWT as `?token=`. The server
/// (`app/auth/ws.py`) decodes it, loads the account, and rejects the handshake
/// with close code 1008 unless the token subject equals the `driver_id` in the
/// path. The path segment is therefore only a claim — the client never relies
/// on the server trusting it, and a connection without a token is not
/// attempted at all, because it can only ever be refused.
///
/// Protocol (JSON both ways):
/// ```text
/// Server → Driver  {"type":"offer", …}         {"event":"offer", …}
///                  {"type":"order_update","order_id":…,"state":…}
///                  {"type":"error","code":…,"order_id":…,"message":…}
///                  {"type":"ping"}
/// Driver → Server  {"type":"location_update","lat":…,"lng":…,"status":…}
///                  {"type":"accept_offer","order_id":…}
///                  {"type":"decline_offer","order_id":…}
///                  {"type":"delivery_action","order_id":…,"state":…}
///                  {"type":"status_change","status":"ONLINE"|"OFFLINE"}
///                  {"type":"pong"}
/// ```
class PubSubService {
  // ── Resilience tuning ──────────────────────────────────────────────────

  /// First retry delay. Deliberately short: most drops are a cell handover
  /// that has already healed by the time we retry.
  static const Duration _baseReconnectDelay = Duration(seconds: 1);

  /// Ceiling on the backoff. Half a minute without offers is already painful;
  /// there is no case for backing off further.
  static const Duration _maxReconnectDelay = Duration(seconds: 30);

  /// Growth factor per failed attempt.
  static const double _backoffFactor = 1.8;

  /// Proportion of each delay that is randomised, ±. Stops a whole fleet
  /// reconnecting on the same tick after a backend deploy.
  static const double _jitterFraction = 0.25;

  /// No inbound frame for this long means the socket is half-open. The server
  /// pings every 20s, so this is two and a half missed pings.
  static const Duration _inboundTimeout = Duration(seconds: 50);

  /// Outbound silence after which a keepalive `pong` is sent.
  static const Duration _keepAliveInterval = Duration(seconds: 25);

  /// How long an offer id is remembered for de-duplication. Comfortably longer
  /// than the 45s offer window, so a redelivery after a reconnect (the server
  /// flushes `driver_pending_offer_*` on connect *and* publishes live) cannot
  /// produce two cards for one job.
  static const Duration _dedupeWindow = Duration(minutes: 5);

  /// Cap on the de-duplication table so a long shift cannot grow it forever.
  static const int _dedupeMaxEntries = 60;

  // ── Connection state ───────────────────────────────────────────────────

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  AppLifecycleListener? _lifecycle;

  String? _driverId;
  bool _shouldReconnect = false;
  bool _isConnecting = false;
  bool _hasNetwork = true;
  int _reconnectAttempts = 0;

  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  Timer? _keepAliveTimer;

  final Random _random = Random();

  ConnectionStatus _status = ConnectionStatus.offline;
  String? _statusMessage;

  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();

  /// Offer ids already delivered to [onOffer], with the time they arrived.
  final LinkedHashMap<String, DateTime> _seenOffers =
      LinkedHashMap<String, DateTime>();

  // ── Callbacks ──────────────────────────────────────────────────────────

  /// A new, non-duplicate offer arrived.
  void Function(OrderOffer offer)? onOffer;

  /// The backend moved an order to a new state.
  void Function(String orderId, String state)? onOrderUpdate;

  /// The backend refused something this driver asked for.
  void Function(PubSubError error)? onError;

  // ── Public API ─────────────────────────────────────────────────────────

  /// True while the service is trying to hold a connection open.
  bool get isActive => _shouldReconnect;

  /// True when a socket is open right now.
  bool get isConnected => _status == ConnectionStatus.connected;

  /// The current link state, for a synchronous read at build time.
  ConnectionStatus get status => _status;

  /// Plain-language detail for the current [status], when there is any.
  /// Pass it straight to `ConnectionStatusBanner(message:)`.
  String? get statusMessage => _statusMessage;

  /// The link state, current value first so a late listener is never blank.
  Stream<ConnectionStatus> get statusStream async* {
    yield _status;
    yield* _statusController.stream;
  }

  /// Connect (or reconnect) the driver's channel. Idempotent for the same
  /// driver.
  void connect(String driverId) {
    if (driverId.isEmpty) {
      _setStatus(
        ConnectionStatus.failed,
        message: "We couldn't identify your account. Sign out and back in.",
      );
      return;
    }
    if (_shouldReconnect && _driverId == driverId) return;
    if (_shouldReconnect) disconnect();

    _driverId = driverId;
    _shouldReconnect = true;
    _isConnecting = false;
    _reconnectAttempts = 0;
    _watchLifecycle();
    _watchConnectivity();
    _doConnect();
  }

  /// Retry immediately, discarding any pending backoff. Wired to the
  /// connection banner's Retry affordance.
  void reconnectNow() {
    if (!_shouldReconnect || _driverId == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _isConnecting = false;
    _doConnect();
  }

  /// Close the socket and stop reconnecting.
  void disconnect() {
    _shouldReconnect = false;
    _isConnecting = false;
    _cancelTimers();
    _teardownSocket();
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _reconnectAttempts = 0;
    _seenOffers.clear();
    _setStatus(ConnectionStatus.offline, message: null);
  }

  /// Release everything. The service is unusable afterwards.
  void dispose() {
    disconnect();
    _statusController.close();
  }

  // ── Publisher helpers ──────────────────────────────────────────────────

  void publishLocation(
    double lat,
    double lng, {
    String status = 'ONLINE',
    int battery = 0,
  }) {
    _send({
      'type': 'location_update',
      'lat': lat,
      'lng': lng,
      'status': status,
      'battery': battery,
    });
  }

  void publishAccept(String orderId) =>
      _send({'type': 'accept_offer', 'order_id': orderId});

  void publishDecline(String orderId) =>
      _send({'type': 'decline_offer', 'order_id': orderId});

  void publishStatusChange(String status) =>
      _send({'type': 'status_change', 'status': status});

  /// Report a delivery-state transition (`ARRIVED_AT_MERCHANT`, `PICKED_UP`,
  /// `ARRIVED_AT_CUSTOMER`, `DELIVERED`). [backendState] must be a real
  /// `OrderState` value.
  void publishDeliveryAction(String orderId, String backendState) => _send({
        'type': 'delivery_action',
        'order_id': orderId,
        'state': backendState,
      });

  /// Forget an offer id so a genuine re-offer of the same order (dispatch does
  /// re-offer after a full round of declines) is not swallowed by the
  /// de-duplication table.
  void forgetOffer(String orderId) => _seenOffers.remove(orderId);

  // ── Connection lifecycle ───────────────────────────────────────────────

  void _doConnect() {
    if (!_shouldReconnect || _driverId == null) return;
    if (_isConnecting) return;

    if (!_hasNetwork) {
      _setStatus(
        ConnectionStatus.offline,
        message: "No signal. You won't get offers until you're back in range.",
      );
      return;
    }

    final token = _accessToken();
    if (token == null) {
      // Retrying without a token can only ever earn another 1008. Say so
      // instead of looping silently while the driver waits for work.
      _setStatus(
        ConnectionStatus.failed,
        message: 'Your session has expired. Sign in again to receive offers.',
      );
      return;
    }

    _isConnecting = true;
    _teardownSocket();
    _setStatus(ConnectionStatus.reconnecting);

    final uri = Uri.parse('${AppConfig.wsBaseUrl}/ws/driver/$_driverId')
        .replace(queryParameters: {'token': token});

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object e) => _onSocketDown('stream error: $e'),
        onDone: () => _onSocketDown(
          'closed (code=${channel.closeCode}, reason=${channel.closeReason})',
          closeCode: channel.closeCode,
        ),
        cancelOnError: false,
      );

      // `ready` completes only once the handshake actually succeeded, so the
      // backoff counter is reset on a *real* connection rather than on having
      // merely constructed a channel object.
      channel.ready.then((_) {
        if (!_shouldReconnect || !identical(_channel, channel)) return;
        _isConnecting = false;
        _reconnectAttempts = 0;
        _setStatus(ConnectionStatus.connected, message: null);
        _armWatchdog();
        _armKeepAlive();
        debugPrint('PubSub: connected as driver $_driverId');
      }).catchError((Object e) {
        if (!identical(_channel, channel)) return;
        _onSocketDown('handshake failed: $e', closeCode: channel.closeCode);
      });
    } catch (e) {
      _onSocketDown('connect threw: $e');
    }
  }

  /// One place where every kind of drop converges.
  void _onSocketDown(String why, {int? closeCode}) {
    _isConnecting = false;
    _cancelLivenessTimers();
    debugPrint('PubSub: socket down — $why');

    // 1008 is the server's policy-violation close: a missing/invalid/superseded
    // token, or a channel that is not this driver's. None of those heal by
    // retrying, so stop and tell the driver what to do.
    if (closeCode == 1008) {
      _teardownSocket();
      _setStatus(
        ConnectionStatus.failed,
        message: 'Your session is no longer valid. Sign in again to go back '
            'online.',
      );
      return;
    }

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    _reconnectTimer?.cancel();

    if (!_hasNetwork) {
      _setStatus(
        ConnectionStatus.offline,
        message: "No signal. You won't get offers until you're back in range.",
      );
      return;
    }

    _reconnectAttempts++;
    final delay = _backoffDelay(_reconnectAttempts);
    _setStatus(ConnectionStatus.reconnecting);
    debugPrint(
      'PubSub: reconnecting in ${delay.inMilliseconds}ms '
      '(attempt $_reconnectAttempts)',
    );
    _reconnectTimer = Timer(delay, _doConnect);
  }

  /// Exponential backoff with symmetric jitter, capped at [_maxReconnectDelay].
  Duration _backoffDelay(int attempt) {
    final raw = _baseReconnectDelay.inMilliseconds *
        pow(_backoffFactor, attempt - 1).toDouble();
    final capped = min(raw, _maxReconnectDelay.inMilliseconds.toDouble());
    final jitter = capped * _jitterFraction * (_random.nextDouble() * 2 - 1);
    return Duration(milliseconds: max(250, (capped + jitter).round()));
  }

  // ── Liveness ───────────────────────────────────────────────────────────

  /// Restart the "have we heard anything lately" timer. Called on connect and
  /// on every inbound frame.
  void _armWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(_inboundTimeout, () {
      // Nothing inbound for 50s although the server pings every 20s: the
      // socket is half-open. TCP will never tell us, so we decide.
      _teardownSocket();
      _onSocketDown('watchdog: no inbound frame for ${_inboundTimeout.inSeconds}s');
    });
  }

  void _armKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) {
      if (_status != ConnectionStatus.connected) return;
      // The server's `pong` branch is a no-op ack, so this keeps middleboxes
      // from reaping an idle socket without generating server-side noise.
      _send({'type': 'pong'});
    });
  }

  void _cancelLivenessTimers() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  void _cancelTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cancelLivenessTimers();
  }

  // ── Backgrounding & connectivity ───────────────────────────────────────

  void _watchLifecycle() {
    _lifecycle?.dispose();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!_shouldReconnect) return;
        // The OS routinely kills sockets while the process is frozen, and the
        // death often surfaces only on the next write. Rather than wait out a
        // backoff (during which every offer is lost), verify immediately.
        if (_status == ConnectionStatus.connected) {
          _armWatchdog();
          _send({'type': 'pong'});
        } else if (_status != ConnectionStatus.failed) {
          reconnectNow();
        }
      },
    );
  }

  void _watchConnectivity() {
    _connectivitySub?.cancel();
    final connectivity = Connectivity();

    unawaited(
      connectivity
          .checkConnectivity()
          .then(_onConnectivity)
          .catchError((Object _) {
        // A platform without the plugin (tests, desktop) must not be treated
        // as permanently offline.
        _hasNetwork = true;
      }),
    );

    _connectivitySub = connectivity.onConnectivityChanged.listen(
      _onConnectivity,
      onError: (Object _) => _hasNetwork = true,
    );
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final had = _hasNetwork;
    _hasNetwork =
        results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);

    if (!_shouldReconnect) return;

    if (!_hasNetwork) {
      _cancelTimers();
      _teardownSocket();
      _setStatus(
        ConnectionStatus.offline,
        message: "No signal. You won't get offers until you're back in range.",
      );
    } else if (!had && _status != ConnectionStatus.connected) {
      // Back in coverage — rebuild now instead of sleeping out the backoff.
      reconnectNow();
    }
  }

  // ── Messages ───────────────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    // Anything at all counts as proof of life, including the server's ping.
    _armWatchdog();

    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (e) {
      debugPrint('PubSub: parse error: $e');
      return;
    }

    // Offers are published with an `event` key, control frames with `type`.
    final type = (msg['type'] as String?) ?? (msg['event'] as String?);

    switch (type) {
      case 'offer':
        final offer = OrderOffer.fromJson(msg);
        if (offer.orderId.isEmpty) return;
        if (_isDuplicateOffer(offer.orderId)) {
          debugPrint('PubSub: dropped duplicate offer ${offer.orderId}');
          return;
        }
        if (offer.isExpired) {
          // The pending-offer cache can hand back an offer whose window has
          // already closed. Showing it would give the driver a card that can
          // only fail on tap.
          debugPrint('PubSub: dropped already-expired offer ${offer.orderId}');
          return;
        }
        onOffer?.call(offer);

      case 'order_update':
        final orderId = msg['order_id'] as String? ?? '';
        final state = msg['state'] as String? ?? '';
        if (orderId.isNotEmpty && state.isNotEmpty) {
          onOrderUpdate?.call(orderId, state);
        }

      case 'error':
        onError?.call(
          PubSubError(
            code: PubSubErrorCode.fromWire(msg['code'] as String?),
            orderId: msg['order_id'] as String? ?? '',
            detail: msg['message'] as String? ?? '',
          ),
        );

      case 'ping':
        _send({'type': 'pong'});

      case 'connected':
      case 'pong':
        break;

      default:
        debugPrint('PubSub: ignoring unknown event "$type"');
    }
  }

  /// True when this order id was already handed to [onOffer] recently.
  ///
  /// Duplicates are normal, not exceptional: the backend both publishes an
  /// offer and caches it under `driver_pending_offer_*` for the reconnect
  /// window, so a driver whose socket flaps during dispatch legitimately
  /// receives the same offer twice.
  bool _isDuplicateOffer(String orderId) {
    final now = DateTime.now();
    _seenOffers.removeWhere((_, at) => now.difference(at) > _dedupeWindow);
    if (_seenOffers.containsKey(orderId)) return true;
    _seenOffers[orderId] = now;
    while (_seenOffers.length > _dedupeMaxEntries) {
      _seenOffers.remove(_seenOffers.keys.first);
    }
    return false;
  }

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null || _status != ConnectionStatus.connected) {
      debugPrint('PubSub: not connected, dropped ${payload['type']}');
      return;
    }
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (e) {
      _onSocketDown('send failed: $e');
    }
  }

  // ── Plumbing ───────────────────────────────────────────────────────────

  String? _accessToken() {
    try {
      final token = Hive.box('settings').get('access_token') as String?;
      if (token == null || token.isEmpty) return null;
      return token;
    } catch (_) {
      return null;
    }
  }

  void _teardownSocket() {
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {
      // Already gone.
    }
    _channel = null;
  }

  void _setStatus(ConnectionStatus next, {String? message}) {
    final changed = next != _status || message != _statusMessage;
    _status = next;
    _statusMessage = message;
    if (changed && !_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
