import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
// `geolocator` re-exports `AndroidSettings`, `ForegroundNotificationConfig`,
// `AppleSettings` and `ActivityType`, so the platform packages do not need to
// be direct dependencies.
import 'package:geolocator/geolocator.dart';

import 'pub_sub_service.dart';

/// Why location reporting could not start. Each value maps to a different
/// thing the driver has to do, so the UI can say something actionable instead
/// of "location unavailable".
enum LocationStartFailure {
  /// The device's location services (GPS) are switched off entirely.
  serviceDisabled,

  /// The driver declined the permission prompt this time.
  denied,

  /// The driver declined permanently — only the OS settings screen can undo
  /// it, so the app must send them there.
  deniedForever,

  /// Foreground permission is granted but the OS refused "always". Tracking
  /// works while the app is open and stops when it is not, which for a driver
  /// means missing offers with the phone in their pocket.
  backgroundDenied,
}

/// Result of asking to start tracking.
@immutable
class LocationStartResult {
  final bool started;
  final LocationStartFailure? failure;

  /// True when tracking runs only while the app is in the foreground.
  final bool foregroundOnly;

  const LocationStartResult._(this.started, this.failure, this.foregroundOnly);

  const LocationStartResult.success({bool foregroundOnly = false})
      : this._(true, null, foregroundOnly);

  const LocationStartResult.failed(LocationStartFailure failure)
      : this._(false, failure, false);
}

/// Streams the driver's position to dispatch for as long as they are on shift.
///
/// ## The defect this replaces (finding X10)
///
/// The previous implementation was a `Timer.periodic` calling
/// `getCurrentPosition` every 3 seconds. Two things were wrong with that, and
/// both of them cost drivers money:
///
/// * **It died on screen lock.** Dart timers stop running once Android or iOS
///   suspends the app, so tracking silently stopped the moment the driver put
///   the phone in their pocket — which is exactly when they are riding. To
///   dispatch the driver looked stale, and stale drivers score badly in
///   `connectivity_score`, so they stopped being offered work.
/// * **It hammered the GPS.** A fix every 3 seconds at
///   [LocationAccuracy.high] regardless of whether the bike had moved is close
///   to the worst case for battery on a phone that also has to last the shift.
///
/// The replacement is a platform location *stream* with a real background
/// strategy:
///
/// * **Android** — [AndroidSettings] with a [ForegroundNotificationConfig].
///   Supplying that config makes the plugin run the location work inside an
///   Android **foreground service**, which is the only way the OS keeps
///   delivering fixes with the screen off. The persistent notification is a
///   feature, not a cost: the driver can see at a glance that they are on
///   shift and being tracked.
/// * **iOS** — [AppleSettings] with `allowBackgroundLocationUpdates` and
///   `pauseLocationUpdatesAutomatically: false`, plus the blue status bar
///   indicator so tracking is never invisible to the driver.
/// * **Battery** — a [_distanceFilterMeters] metre distance filter and a
///   [_intervalSeconds] second minimum interval. A stationary driver costs
///   nothing; a moving one is reported often enough for the customer's live
///   map to look smooth.
/// * **A stationary heartbeat** — the platform stream goes quiet when the bike
///   is parked, but dispatch scores drivers partly on how recently they pinged
///   (`connectivity_score` in `dispatch/service.py`). A driver waiting outside
///   a restaurant must not decay into looking offline, so the last known fix is
///   re-sent every [_heartbeatSeconds] seconds.
///
/// **Platform manifests are required for any of this to work** — see the
/// D1 report. Without `NSLocationWhenInUseUsageDescription` iOS terminates the
/// process on the first request (finding X2), and without
/// `FOREGROUND_SERVICE_LOCATION` Android refuses to start the service.
class LocationService {
  /// Minimum metres of movement between reports. Roughly one city block at
  /// riding speed; small enough that the customer's tracking map stays smooth.
  static const int _distanceFilterMeters = 25;

  /// Minimum seconds between Android fixes. Caps the update rate on a fast
  /// road where the distance filter alone would fire constantly.
  static const int _intervalSeconds = 8;

  /// Re-send the last fix this often while stationary, so dispatch keeps
  /// seeing a live driver. Comfortably under the backend's per-driver location
  /// rate limit (30 updates / 60s).
  static const int _heartbeatSeconds = 45;

  final PubSubService _pubSub;

  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeatTimer;
  Position? _lastPosition;
  bool _isReporting = false;

  LocationService({required PubSubService pubSub}) : _pubSub = pubSub;

  /// True while positions are being streamed to dispatch.
  bool get isReporting => _isReporting;

  /// The most recent fix, or null before the first one arrives.
  Position? get lastPosition => _lastPosition;

  /// Begin streaming the driver's position.
  ///
  /// Returns what happened rather than a bare bool, so the caller can tell the
  /// driver which of four different things to do about it.
  Future<LocationStartResult> startReporting() async {
    if (_isReporting) return const LocationStartResult.success();

    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationStartResult.failed(
        LocationStartFailure.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const LocationStartResult.failed(LocationStartFailure.denied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationStartResult.failed(
        LocationStartFailure.deniedForever,
      );
    }

    // `whileInUse` still lets us start, but tracking will stop when the app
    // leaves the foreground. That is a materially worse shift, so the caller
    // is told and can nudge the driver towards "Allow all the time".
    final foregroundOnly = permission == LocationPermission.whileInUse;

    _isReporting = true;
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _settings(),
    ).listen(
      _onPosition,
      onError: (Object e) {
        debugPrint('LocationService: position stream error: $e');
      },
      cancelOnError: false,
    );

    // Send one fix immediately so dispatch can score this driver right away
    // rather than after the first 25 metres of travel.
    unawaited(_sendCurrentPositionOnce());

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _heartbeatSeconds),
      (_) => _sendHeartbeat(),
    );

    debugPrint(
      'LocationService: streaming (filter ${_distanceFilterMeters}m, '
      'foregroundOnly=$foregroundOnly)',
    );
    return LocationStartResult.success(foregroundOnly: foregroundOnly);
  }

  /// Stop streaming and tell the backend this driver is off shift.
  void stopReporting() {
    if (!_isReporting) return;
    _isReporting = false;
    _positionSub?.cancel();
    _positionSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pubSub.publishStatusChange('OFFLINE');
    debugPrint('LocationService: stopped');
  }

  void dispose() {
    stopReporting();
    _lastPosition = null;
  }

  /// Open the OS settings page for this app, for the permanently-denied case.
  Future<bool> openPermissionSettings() => Geolocator.openAppSettings();

  /// Open the OS location-services page, for the GPS-switched-off case.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  // ── Internals ──────────────────────────────────────────────────────────

  /// Per-platform settings. This is where background survival actually comes
  /// from; the generic `LocationSettings` fallback has no background story at
  /// all, which is why the previous implementation died on screen lock.
  LocationSettings _settings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
      );
    }
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        intervalDuration: const Duration(seconds: _intervalSeconds),
        // Providing this is what promotes the plugin's location work to an
        // Android foreground service, so fixes keep arriving with the screen
        // locked. `setOngoing` stops the driver swiping the shift away by
        // accident; `enableWakeLock` stops the OS batching a whole ride's
        // worth of fixes and delivering them at once when it next wakes.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "You're online with Zvingo",
          notificationText: 'Sharing your location so you get delivery offers.',
          notificationChannelName: 'Zvingo shift tracking',
          enableWakeLock: true,
          enableWifiLock: false,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        // iOS otherwise pauses updates when it decides the user has stopped
        // moving — which for a driver waiting at a restaurant looks exactly
        // like going offline.
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        // The blue bar. Tracking a person in the background must be visible to
        // them, always.
        showBackgroundLocationIndicator: true,
        activityType: ActivityType.automotiveNavigation,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _distanceFilterMeters,
    );
  }

  void _onPosition(Position position) {
    _lastPosition = position;
    _publish(position);
  }

  Future<void> _sendCurrentPositionOnce() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!_isReporting) return;
      _lastPosition = position;
      _publish(position);
    } catch (e) {
      debugPrint('LocationService: initial fix failed: $e');
    }
  }

  /// Re-send the last known fix so a parked driver does not decay out of
  /// dispatch's candidate pool.
  void _sendHeartbeat() {
    final position = _lastPosition;
    if (!_isReporting || position == null) return;
    _publish(position);
  }

  void _publish(Position position) {
    _pubSub.publishLocation(
      position.latitude,
      position.longitude,
      status: 'ONLINE',
    );
  }
}
