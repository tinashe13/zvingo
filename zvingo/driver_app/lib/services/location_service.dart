import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'pub_sub_service.dart';

/// Reports driver GPS location to the backend every [_intervalSeconds].
/// Publishes via the shared [PubSubService] WebSocket instead of individual
/// HTTP POST calls, so all real-time traffic flows through a single connection.
class LocationService {
  static const _intervalSeconds = 3;

  final PubSubService _pubSub;

  Timer? _timer;
  bool _isReporting = false;

  LocationService({required PubSubService pubSub}) : _pubSub = pubSub;

  /// Start reporting location. Returns false if permission denied.
  Future<bool> startReporting() async {
    if (_isReporting) return true;

    final permission = await _checkPermission();
    if (!permission) return false;

    _isReporting = true;

    // Send immediately, then on interval
    await _sendLocation();
    _timer = Timer.periodic(
      const Duration(seconds: _intervalSeconds),
      (_) => _sendLocation(),
    );

    debugPrint('LocationService: Started reporting every ${_intervalSeconds}s');
    return true;
  }

  /// Stop reporting location and broadcast OFFLINE status.
  void stopReporting() {
    _isReporting = false;
    _timer?.cancel();
    _timer = null;
    _sendOffline();
    debugPrint('LocationService: Stopped reporting');
  }

  Future<bool> _checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('LocationService: Location services disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('LocationService: Permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('LocationService: Permission permanently denied');
      return false;
    }

    return true;
  }

  Future<void> _sendLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _pubSub.publishLocation(
        position.latitude,
        position.longitude,
        status: 'ONLINE',
      );
    } catch (e) {
      debugPrint('LocationService: Error getting position: $e');
    }
  }

  void _sendOffline() {
    _pubSub.publishStatusChange('OFFLINE');
  }

  void dispose() {
    stopReporting();
  }
}
