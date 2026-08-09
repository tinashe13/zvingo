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

  static const bool _isRelease = bool.fromEnvironment('dart.vm.product');

  /// Fails early when a build points at an invalid or insecure API endpoint.
  static void validate() {
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('API_BASE_URL must be an absolute URL: $apiBaseUrl');
    }
    if (_isRelease && uri.scheme != 'https') {
      throw StateError(
        'Release builds require an HTTPS API_BASE_URL. Received: $apiBaseUrl',
      );
    }
  }
}
