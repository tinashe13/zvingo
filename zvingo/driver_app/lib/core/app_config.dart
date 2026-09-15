/// Build-time configuration for the driver app.
///
/// Nothing here is hardcoded to a developer's machine or a private IP: every
/// value comes from `--dart-define` with a development default that only makes
/// sense on an emulator. Shipping a real host means passing it at build time,
/// not editing this file.
///
/// ```bash
/// # Android emulator against a local backend (the default)
/// flutter run
///
/// # iOS simulator
/// flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
///
/// # Staging / production
/// flutter build apk --release \
///   --dart-define=API_BASE_URL=https://api.zvingo.com \
///   --dart-define=ORS_API_KEY=$ORS_API_KEY
/// ```
///
/// Supported defines:
///
/// | Define | Default | Purpose |
/// |---|---|---|
/// | `API_BASE_URL` | `http://10.0.2.2:8000` | REST origin, `/api/v1` is appended per call |
/// | `WS_BASE_URL` | derived from `API_BASE_URL` | WebSocket origin, override only when the socket is on a different host |
/// | `ORS_API_KEY` | empty | OpenRouteService directions key used by `NavigationMap` |
/// | `API_CONNECT_TIMEOUT_SECONDS` | `15` | Dio connect timeout |
/// | `API_RECEIVE_TIMEOUT_SECONDS` | `20` | Dio receive timeout |
class AppConfig {
  AppConfig._();

  /// REST origin. Override with `--dart-define=API_BASE_URL=…`.
  ///
  /// `10.0.2.2` is the Android emulator's alias for the host machine's
  /// loopback — it is a well-known emulator constant, not a developer's IP.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Explicit WebSocket origin. Empty means "derive it from [baseUrl]".
  static const String _wsOverride = String.fromEnvironment('WS_BASE_URL');

  /// WebSocket origin: the explicit `WS_BASE_URL` define when one is given,
  /// otherwise [baseUrl] with `http`→`ws` / `https`→`wss`.
  static String get wsBaseUrl {
    if (_wsOverride.isNotEmpty) return _stripTrailingSlash(_wsOverride);
    return _stripTrailingSlash(baseUrl).replaceFirst(RegExp(r'^http'), 'ws');
  }

  /// OpenRouteService API key for turn-by-turn directions.
  ///
  /// Empty by default: a key is a third-party credential and must never be
  /// committed. `NavigationMap` degrades to a straight-line route with a
  /// visible explanation when this is blank — it does not fail silently.
  static const String orsApiKey = String.fromEnvironment('ORS_API_KEY');

  /// True when turn-by-turn routing can be requested.
  static bool get hasRoutingKey => orsApiKey.isNotEmpty;

  /// Dio connect timeout.
  static const Duration connectTimeout = Duration(
    seconds: int.fromEnvironment(
      'API_CONNECT_TIMEOUT_SECONDS',
      defaultValue: 15,
    ),
  );

  /// Dio receive timeout. Slightly longer than the connect timeout because
  /// dispatch and earnings queries can fan out across collections.
  static const Duration receiveTimeout = Duration(
    seconds: int.fromEnvironment(
      'API_RECEIVE_TIMEOUT_SECONDS',
      defaultValue: 20,
    ),
  );

  /// True when the app is talking to a non-TLS origin, i.e. a dev backend.
  /// Useful for showing a build banner so a tester never mistakes a local
  /// build for production.
  static bool get isDevBackend => baseUrl.startsWith('http://');

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
