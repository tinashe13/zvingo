/// Central configuration for server connectivity.
///
/// Override at build time with --dart-define=API_BASE_URL=...
///   - Android emulator (dev): 'http://10.0.2.2:8000'          (default)
///   - iOS simulator (dev):    'http://127.0.0.1:8000'
///   - Real device / staging:  'http://<your-server-ip>'       (port 80 via Nginx)
///   - Production:             'https://api.zvingo.com'
class AppConfig {
  AppConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// WebSocket URL derived from baseUrl (http → ws, https → wss).
  static String get wsBaseUrl =>
      baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
}
