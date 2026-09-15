/// Central configuration for server connectivity.
///
/// The API base URL is **always** supplied at build time; nothing in the app
/// hardcodes a host. Set it with `--dart-define`:
///
/// ```bash
/// # Production
/// flutter build appbundle --release \
///   --dart-define=API_BASE_URL=https://api.pindira.com/api
///
/// # Staging / a real device pointed at your laptop
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
///
/// # Android emulator against a server on the host machine
/// flutter run --dart-define=ZV_ENV=local-android
///
/// # iOS simulator / desktop against a server on the same machine
/// flutter run --dart-define=ZV_ENV=local
/// ```
///
/// `10.0.2.2` is the Android emulator's alias for the host loopback. It is a
/// **developer convenience only** — it must never be the default, because a
/// release build pointed at it silently fails on every real device. It is
/// reachable here only through the explicit `ZV_ENV=local-android` shortcut,
/// and [validate] refuses any non-HTTPS URL in a release build regardless.
class AppConfig {
  AppConfig._();

  /// Production API. The default for every build that defines nothing.
  ///
  /// This is the host the repo's deployment config actually provisions
  /// (`.env.backend.example`, `DEPLOYMENT.md`, `nginx/nginx.prod.conf`), over
  /// HTTPS because certbot issues a certificate for it. Note that
  /// `consumer_app/BUILD.md` still documents `api.zvingo.com`; the two must be
  /// reconciled before a store build, since the host is compiled into the
  /// binary. Until then, always pass `--dart-define=API_BASE_URL=...`
  /// explicitly for a release.
  static const String productionBaseUrl = 'https://api.pindira.com/api';

  /// Host loopback as seen from an Android emulator (`ZV_ENV=local-android`).
  static const String androidEmulatorBaseUrl = 'http://10.0.2.2:8000/api';

  /// Loopback for an iOS simulator, desktop or web debug run
  /// (`ZV_ENV=local`).
  static const String localBaseUrl = 'http://127.0.0.1:8000/api';

  /// Optional shorthand for a local dev target: `local` or `local-android`.
  /// Ignored when `API_BASE_URL` is supplied explicitly.
  static const String _env = String.fromEnvironment('ZV_ENV');

  /// Explicit override. Wins over [_env]. Empty means "not supplied".
  static const String _explicitBaseUrl = String.fromEnvironment('API_BASE_URL');

  static const bool _isRelease = bool.fromEnvironment('dart.vm.product');

  /// The resolved API base URL, e.g. `https://api.zvingo.com/api`.
  ///
  /// Resolution order: `--dart-define=API_BASE_URL` → `--dart-define=ZV_ENV`
  /// shorthand → [productionBaseUrl].
  static String get apiBaseUrl {
    if (_explicitBaseUrl.isNotEmpty) return _explicitBaseUrl;
    switch (_env) {
      case 'local-android':
        return androidEmulatorBaseUrl;
      case 'local':
        return localBaseUrl;
      default:
        return productionBaseUrl;
    }
  }

  /// True when the app is talking to a developer machine rather than a
  /// deployed environment. Useful for gating verbose logging.
  static bool get isLocalTarget {
    final host = Uri.tryParse(apiBaseUrl)?.host ?? '';
    return host == '10.0.2.2' ||
        host == '127.0.0.1' ||
        host == 'localhost' ||
        host == '10.0.3.2';
  }

  /// True in a `--release` build.
  static bool get isRelease => _isRelease;

  /// Fails early when a build points at an invalid or insecure API endpoint.
  /// Called from `main()` before the first frame.
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
    if (_isRelease && isLocalTarget) {
      throw StateError(
        'Release builds must not point at a loopback host. '
        'Received: $apiBaseUrl',
      );
    }
  }
}
