/// Central configuration for server connectivity.
///
/// Override at build time with --dart-define=API_BASE_URL=...
///   - Android emulator (dev): 'http://10.0.2.2/api'          (host Nginx, default)
///   - Real device / staging:  'http://<your-server-ip>/api'
///   - Production:             'https://api.zvingo.com/api'
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2/api',
  );
}
