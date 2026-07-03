import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../models/order_offer.dart';

/// SSE client that connects to the backend notification stream.
/// Listens for real-time delivery offers on `driver_{userId}` channel.
class SseService {
  static const _baseUrl = AppConfig.baseUrl;
  static const _initialReconnectDelay = 5; // seconds
  static const _maxReconnectDelay = 60; // seconds

  http.Client? _client;
  StreamSubscription? _subscription;
  bool _shouldReconnect = false;
  bool _isConnecting = false;
  String? _channelId;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  /// Callback when a new offer arrives.
  void Function(OrderOffer offer)? onOffer;

  /// Whether the service is currently connected or trying to connect.
  bool get isActive => _shouldReconnect;

  /// Start listening for offers on this driver's channel.
  /// Safe to call multiple times — will no-op if already active for the same channel.
  void connect(String userId) {
    final newChannel = 'driver_$userId';

    // Already connected/connecting to this channel — no-op
    if (_shouldReconnect && _channelId == newChannel) {
      debugPrint('SSE: Already active for $newChannel, skipping duplicate connect');
      return;
    }

    // If switching channels, disconnect first
    if (_shouldReconnect) disconnect();

    _channelId = newChannel;
    _shouldReconnect = true;
    _isConnecting = false;
    _reconnectAttempts = 0;
    _doConnect();
  }

  Future<void> _doConnect() async {
    if (!_shouldReconnect || _channelId == null) return;

    // Prevent concurrent connection attempts
    if (_isConnecting) return;
    _isConnecting = true;

    // Clean up any existing connection before reconnecting
    await _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = http.Client();

    final token = Hive.box('settings').get('access_token') as String?;

    try {
      final request = http.Request(
        'GET',
        Uri.parse('$_baseUrl/notification/events/$_channelId'),
      );
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      request.headers['Connection'] = 'keep-alive';

      debugPrint('SSE: Connecting to $_channelId (attempt ${_reconnectAttempts + 1})');
      final response = await _client!.send(request).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('SSE connection timeout after 30 seconds');
        },
      );

      // Check if we were disconnected while awaiting
      if (!_shouldReconnect) {
        _isConnecting = false;
        return;
      }

      debugPrint('SSE: HTTP ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('SSE: HTTP ${response.statusCode}, scheduling retry...');
        _isConnecting = false;
        _scheduleReconnect();
        return;
      }

      // Successfully connected — reset backoff
      debugPrint('SSE: Connected to $_channelId');
      _reconnectAttempts = 0;
      _isConnecting = false;

      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _handleLine,
        onError: (e) {
          debugPrint('SSE: Stream error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('SSE: Stream ended');
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } on TimeoutException catch (e) {
      debugPrint('SSE: Timeout: $e');
      _isConnecting = false;
      _scheduleReconnect();
    } catch (e) {
      debugPrint('SSE: Connection failed: $e');
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  String _dataBuffer = '';
  String _eventType = '';

  void _handleLine(String line) {
    if (line.isEmpty) {
      // Empty line marks end of event — dispatch based on event type
      if (_dataBuffer.isNotEmpty) {
        _parseMessage(_eventType, _dataBuffer);
        _dataBuffer = '';
        _eventType = '';
      }
    } else if (line.startsWith('data:')) {
      _dataBuffer += line.substring(5).trim();
    } else if (line.startsWith('event:')) {
      _eventType = line.substring(6).trim();
    }
  }

  void _parseMessage(String eventType, String data) {
    // Ignore keepalive pings
    if (eventType == 'ping' || data == 'ping') return;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;

      // The SSE event type from the backend is "message" for all Redis pub/sub
      // messages, so always prefer the inner JSON 'event' field which carries
      // the actual semantic type (offer, new_order, etc.).
      final event = json['event'] as String? ??
          (eventType.isNotEmpty ? eventType : null);

      switch (event) {
        case 'connected':
          debugPrint('SSE: ${json['data'] ?? 'Connected'}');
          break;
        case 'offer':
          final offer = OrderOffer.fromJson(json);
          debugPrint('SSE: Received offer ${offer.orderId}');
          onOffer?.call(offer);
          break;
        case 'error':
          debugPrint('SSE: Server error - ${json['data']}');
          break;
        default:
          debugPrint('SSE: Event "$event" - ${json['data'] ?? data}');
      }
    } catch (e) {
      debugPrint('SSE: Parse error: $e (data=$data)');
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    // Cancel any existing pending reconnect to avoid stacking
    _reconnectTimer?.cancel();

    // Exponential backoff: 5s, 10s, 20s, 40s, 60s cap
    _reconnectAttempts++;
    final delaySec = min(
      _initialReconnectDelay * pow(2, _reconnectAttempts - 1),
      _maxReconnectDelay,
    ).toInt();

    debugPrint('SSE: Reconnecting in ${delaySec}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(Duration(seconds: delaySec), _doConnect);
  }

  /// Disconnect and stop reconnecting.
  void disconnect() {
    _shouldReconnect = false;
    _isConnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    _dataBuffer = '';
    _eventType = '';
    _reconnectAttempts = 0;
    debugPrint('SSE: Disconnected');
  }
}
