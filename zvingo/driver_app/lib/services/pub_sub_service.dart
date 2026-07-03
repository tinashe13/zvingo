import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/app_config.dart';
import '../models/order_offer.dart';

/// Bidirectional pub/sub service over a single WebSocket connection.
///
/// The driver app acts as BOTH:
///   Subscriber — receives offers and order-update events from the backend.
///   Publisher  — sends location updates, accept/decline events to the backend.
///
/// Protocol (JSON in both directions):
///   Server → Driver  {"type":"offer", ...offer_fields}
///                    {"type":"order_update", "order_id":..., "state":...}
///                    {"type":"ping"}
///   Driver → Server  {"type":"location_update","lat":..., "lng":..., "status":"ONLINE"}
///                    {"type":"accept_offer",   "order_id":...}
///                    {"type":"decline_offer",  "order_id":...}
///                    {"type":"status_change",  "status":"ONLINE"|"OFFLINE"}
class PubSubService {
  static const int _initialReconnectDelay = 5; // seconds
  static const int _maxReconnectDelay = 60; // seconds

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _driverId;
  bool _shouldReconnect = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // ── Callbacks ──────────────────────────────────────────────────────────────

  /// Called when an offer arrives from the backend.
  void Function(OrderOffer offer)? onOffer;

  /// Called when the backend sends an order state update.
  void Function(String orderId, String state)? onOrderUpdate;

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get isActive => _shouldReconnect;

  /// Connect (or reconnect) to the driver's WebSocket channel.
  /// Safe to call multiple times — no-op if already connected for the same driver.
  void connect(String driverId) {
    if (_shouldReconnect && _driverId == driverId) {
      debugPrint('PubSub: Already active for driver_$driverId, skipping');
      return;
    }
    if (_shouldReconnect) disconnect();

    _driverId = driverId;
    _shouldReconnect = true;
    _isConnecting = false;
    _reconnectAttempts = 0;
    _doConnect();
  }

  /// Disconnect and stop reconnecting.
  void disconnect() {
    _shouldReconnect = false;
    _isConnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _reconnectAttempts = 0;
    debugPrint('PubSub: Disconnected');
  }

  // ── Publisher helpers ───────────────────────────────────────────────────────

  void publishLocation(double lat, double lng, {String status = 'ONLINE', int battery = 0}) {
    _send({
      'type': 'location_update',
      'lat': lat,
      'lng': lng,
      'status': status,
      'battery': battery,
    });
  }

  void publishAccept(String orderId) {
    _send({'type': 'accept_offer', 'order_id': orderId});
  }

  void publishDecline(String orderId) {
    _send({'type': 'decline_offer', 'order_id': orderId});
  }

  void publishStatusChange(String status) {
    _send({'type': 'status_change', 'status': status});
  }

  /// Notify the backend of a delivery state transition (e.g. arrived at merchant,
  /// picked up, arrived at customer). [backendState] must be a valid OrderState
  /// string recognised by the server (e.g. 'ARRIVED_AT_MERCHANT').
  void publishDeliveryAction(String orderId, String backendState) {
    _send({'type': 'delivery_action', 'order_id': orderId, 'state': backendState});
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> payload) {
    if (_channel == null) {
      debugPrint('PubSub: Cannot send — not connected (${payload['type']})');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('PubSub: Send error: $e');
    }
  }

  void _doConnect() {
    if (!_shouldReconnect || _driverId == null) return;
    if (_isConnecting) return;
    _isConnecting = true;

    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;

    final token = Hive.box('settings').get('access_token') as String?;
    final wsUrl = '${AppConfig.wsBaseUrl}/ws/driver/$_driverId'
        '${token != null ? '?token=$token' : ''}';

    debugPrint('PubSub: Connecting to driver_$_driverId (attempt ${_reconnectAttempts + 1})');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('PubSub: Stream error: $e');
          _isConnecting = false;
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('PubSub: Stream closed');
          _isConnecting = false;
          _scheduleReconnect();
        },
        cancelOnError: false,
      );

      // Successfully set up the listener — reset backoff
      _reconnectAttempts = 0;
      _isConnecting = false;
      debugPrint('PubSub: Connected to driver_$_driverId');
    } catch (e) {
      debugPrint('PubSub: Connection failed: $e');
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String? ?? msg['event'] as String?;

      switch (type) {
        case 'offer':
          final offer = OrderOffer.fromJson(msg);
          debugPrint('PubSub: Received offer ${offer.orderId}');
          onOffer?.call(offer);
          break;

        case 'order_update':
          final orderId = msg['order_id'] as String? ?? '';
          final state = msg['state'] as String? ?? '';
          debugPrint('PubSub: Order update $orderId → $state');
          onOrderUpdate?.call(orderId, state);
          break;

        case 'connected':
          debugPrint('PubSub: ${msg['data'] ?? 'Connected'}');
          break;

        case 'ping':
          // Respond with pong to confirm liveness
          _send({'type': 'pong'});
          break;

        default:
          debugPrint('PubSub: Unknown event "$type"');
      }
    } catch (e) {
      debugPrint('PubSub: Parse error: $e (raw=$raw)');
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    _reconnectTimer?.cancel();

    _reconnectAttempts++;
    final delaySec = min(
      _initialReconnectDelay * pow(2, _reconnectAttempts - 1),
      _maxReconnectDelay,
    ).toInt();

    debugPrint('PubSub: Reconnecting in ${delaySec}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(Duration(seconds: delaySec), _doConnect);
  }
}
