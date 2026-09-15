import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../core/api_client.dart';

/// Hive keys for the stored session. One place, so a typo cannot silently
/// strand a driver on the login screen.
class _SessionKeys {
  static const box = 'settings';
  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const expiresAt = 'access_token_expires_at';
  static const email = 'email';
  static const phone = 'phone';
  static const driverName = 'driver_name';
  static const userId = 'user_id';
}

/// Why the driver is being asked to sign in again. Shown on the login screen
/// so a session ending mid-shift is explained rather than mysterious.
enum SignOutReason {
  /// The driver tapped Log out.
  userInitiated,

  /// The refresh token was rejected — expired, revoked, or already used.
  sessionExpired,
}

/// Auth state.
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;
  final String email;
  final String phone;
  final String driverName;
  final String? userId;

  /// Set when the session ended on its own rather than by the driver's choice.
  final SignOutReason? signOutReason;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
    this.email = '',
    this.phone = '',
    this.driverName = '',
    this.userId,
    this.signOutReason,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
    String? email,
    String? phone,
    String? driverName,
    String? userId,
    SignOutReason? signOutReason,
    bool clearSignOutReason = false,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      driverName: driverName ?? this.driverName,
      userId: userId ?? this.userId,
      signOutReason:
          clearSignOutReason ? null : (signOutReason ?? this.signOutReason),
    );
  }

  /// What to greet the driver with. Falls back through name → phone → a
  /// neutral noun, never an empty string.
  String get displayName {
    if (driverName.trim().isNotEmpty) return driverName.trim();
    if (phone.trim().isNotEmpty) return phone.trim();
    return 'Driver';
  }

  /// Up to two initials for the avatar.
  String get initials {
    final parts = driverName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'D';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

/// Owns the access/refresh token pair and replays a request once across a
/// token rotation.
///
/// Agent F4 added refresh-token **rotation with revocation**
/// (`backend/app/auth/tokens.py`): `POST /auth/refresh` consumes the presented
/// refresh token atomically and mints a new pair, so each refresh token works
/// exactly once and a replay — by us or by a thief — is a 401. That makes two
/// things mandatory on this side:
///
/// 1. **Store both halves of every response.** Keeping the old refresh token
///    after a rotation guarantees the next refresh fails.
/// 2. **Never refresh twice concurrently.** Two parallel 401s must await one
///    in-flight refresh; racing them means one of the two rotations loses and
///    the driver is logged out mid-shift, which is the exact failure this
///    class exists to prevent.
///
/// `ApiClient`'s request interceptor reads the bearer straight out of Hive on
/// every call, so writing the new token to Hive is what actually re-arms the
/// client; `setAuthToken` is called too, to keep the two in step.
class AuthSession {
  final ApiClient _api;

  /// Invoked when a refresh is refused and the session is genuinely over.
  void Function()? onSessionExpired;

  Future<bool>? _refreshInFlight;

  AuthSession(this._api);

  Box get _box => Hive.box(_SessionKeys.box);

  String? get accessToken {
    try {
      final token = _box.get(_SessionKeys.accessToken) as String?;
      return (token != null && token.isNotEmpty) ? token : null;
    } catch (_) {
      return null;
    }
  }

  String? get refreshToken {
    try {
      final token = _box.get(_SessionKeys.refreshToken) as String?;
      return (token != null && token.isNotEmpty) ? token : null;
    } catch (_) {
      return null;
    }
  }

  /// Runs [request], and on a 401 refreshes the token pair once and replays it.
  ///
  /// Anything other than a 401 — including the 403 the finance router raises
  /// when a driver asks for someone else's earnings — passes straight through
  /// to the caller, because those are not fixed by a new token.
  Future<Response<T>> send<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) rethrow;
      final refreshed = await refresh();
      if (!refreshed) rethrow;
      return await request();
    }
  }

  /// Exchanges the stored refresh token for a new pair. Returns false when
  /// there is nothing to refresh with or the server refuses.
  Future<bool> refresh() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final token = refreshToken;
    if (token == null) {
      // Sessions created before refresh tokens existed have no refresh half.
      // There is nothing to rotate, so the access token is all we have.
      return false;
    }
    try {
      final response = await _api.post(
        '/auth/refresh',
        data: {'refresh_token': token},
      );
      final data = response.data;
      if (data is! Map) return false;
      final access = data['access_token'] as String?;
      if (access == null || access.isEmpty) return false;
      persistTokens(
        accessToken: access,
        refreshToken: data['refresh_token'] as String?,
        expiresIn: (data['expires_in'] as num?)?.toInt(),
      );
      return true;
    } on DioException catch (e) {
      // 401/403 here means the refresh token is spent, revoked or stolen.
      // Anything else (no network, 500) is transient: keep the session and let
      // the caller surface a retry rather than dumping the driver to login.
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        onSessionExpired?.call();
      } else {
        debugPrint('AuthSession: refresh failed transiently: ${e.message}');
      }
      return false;
    } catch (e) {
      debugPrint('AuthSession: refresh failed: $e');
      return false;
    }
  }

  /// Writes a freshly issued token pair to storage and arms the client.
  void persistTokens({
    required String accessToken,
    String? refreshToken,
    int? expiresIn,
  }) {
    try {
      _box.put(_SessionKeys.accessToken, accessToken);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        _box.put(_SessionKeys.refreshToken, refreshToken);
      }
      if (expiresIn != null && expiresIn > 0) {
        _box.put(
          _SessionKeys.expiresAt,
          DateTime.now()
              .add(Duration(seconds: expiresIn))
              .toUtc()
              .toIso8601String(),
        );
      }
    } catch (e) {
      debugPrint('AuthSession: could not persist tokens: $e');
    }
    _api.setAuthToken(accessToken);
  }

  /// Best-effort revocation of this device's refresh token, then local wipe.
  Future<void> clear({bool revokeOnServer = true}) async {
    final token = refreshToken;
    if (revokeOnServer && token != null) {
      try {
        await _api.post('/auth/logout', data: {'refresh_token': token});
      } catch (e) {
        // A driver who taps Log out on a dead network must still end up logged
        // out locally; the token expires on its own.
        debugPrint('AuthSession: server logout failed: $e');
      }
    }
    try {
      _box.delete(_SessionKeys.accessToken);
      _box.delete(_SessionKeys.refreshToken);
      _box.delete(_SessionKeys.expiresAt);
      _box.delete(_SessionKeys.email);
      _box.delete(_SessionKeys.phone);
      _box.delete(_SessionKeys.driverName);
      _box.delete(_SessionKeys.userId);
    } catch (e) {
      debugPrint('AuthSession: could not clear session: $e');
    }
    _api.setAuthToken(null);
  }
}

/// Auth provider — phone-first sign in, with transparent token rotation.
class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _apiClient;
  final AuthSession _session;

  AuthNotifier(this._apiClient, this._session) : super(const AuthState()) {
    _session.onSessionExpired = _onSessionExpired;
    _restoreSession();
  }

  /// Zimbabwe's country calling code. Drivers type `0771234567`; the backend
  /// requires E.164 (`app/auth/schemas.py` rejects anything that is not
  /// `+` followed by digits).
  static const String zimbabweDialCode = '+263';

  /// Normalises whatever the driver typed into E.164.
  ///
  /// `0771234567` → `+263771234567`; `263 77 123 4567` → `+263771234567`;
  /// an already-correct `+263…` is returned unchanged. Non-Zimbabwean numbers
  /// that already start with `+` pass through untouched.
  static String normalisePhone(String input) {
    var digits = input.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('00')) return '+${digits.substring(2)}';
    if (digits.startsWith('0')) {
      return '$zimbabweDialCode${digits.substring(1)}';
    }
    if (digits.startsWith('263')) return '+$digits';
    return '$zimbabweDialCode$digits';
  }

  /// Validation message for a phone field, or null when it is acceptable.
  ///
  /// Zimbabwean mobile numbers are `+263` plus a 9-digit subscriber number.
  static String? validatePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'Enter your phone number';
    final normalised = normalisePhone(trimmed);
    if (!normalised.startsWith('+')) {
      return 'Use the format 077 123 4567';
    }
    final digits = normalised.substring(1);
    if (!RegExp(r'^\d+$').hasMatch(digits)) {
      return 'Phone numbers can only contain digits';
    }
    if (normalised.startsWith(zimbabweDialCode)) {
      final subscriber = normalised.substring(zimbabweDialCode.length);
      if (subscriber.length != 9) {
        return 'A Zimbabwean number has 9 digits after +263';
      }
      if (!subscriber.startsWith('7')) {
        return 'Mobile numbers start with 7 after +263';
      }
      return null;
    }
    if (digits.length < 8 || digits.length > 15) {
      return 'That does not look like a valid phone number';
    }
    return null;
  }

  /// Validation message for a password field, or null when acceptable.
  /// The floor mirrors `MIN_PASSWORD_LENGTH` in `app/auth/schemas.py`.
  static String? validatePassword(String value, {bool isRegister = false}) {
    if (value.isEmpty) return 'Enter your password';
    if (isRegister && value.length < 8) {
      return 'Use at least 8 characters';
    }
    return null;
  }

  void _restoreSession() {
    final token = _session.accessToken;
    if (token == null) return;
    _apiClient.setAuthToken(token);
    try {
      final box = Hive.box(_SessionKeys.box);
      state = AuthState(
        isAuthenticated: true,
        email: box.get(_SessionKeys.email) as String? ?? '',
        phone: box.get(_SessionKeys.phone) as String? ?? '',
        driverName: box.get(_SessionKeys.driverName) as String? ?? '',
        userId: box.get(_SessionKeys.userId) as String? ??
            _extractUserId(token),
      );
    } catch (e) {
      debugPrint('AuthNotifier: could not restore session: $e');
      state = AuthState(isAuthenticated: true, userId: _extractUserId(token));
    }
    // Refresh the profile in the background so a name changed on another
    // device shows up, and so a dead session is discovered before the driver
    // needs it rather than mid-delivery.
    unawaited(_loadProfile());
  }

  /// Sign in with a phone number (or email) and password.
  ///
  /// `POST /auth/token` is OAuth2 form-encoded and matches on the `username`
  /// field, which `AuthService.authenticate_user` resolves against either the
  /// phone or the email column.
  Future<void> login(String identifier, String password) async {
    final isPhone = !identifier.contains('@');
    final username = isPhone ? normalisePhone(identifier) : identifier.trim();

    state = state.copyWith(
      isLoading: true,
      error: null,
      clearSignOutReason: true,
    );
    try {
      final response = await _apiClient.login(
        username: username,
        password: password,
      );
      _adoptToken(
        response.data,
        phone: isPhone ? username : '',
        email: isPhone ? '' : username,
      );
      await _loadProfile();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _extractError(e));
    }
  }

  /// Register a new driver account. `POST /auth/register` always returns a
  /// token pair, so a successful registration signs the driver straight in.
  Future<void> register({
    required String fullName,
    required String phone,
    required String password,
    String email = '',
  }) async {
    final normalised = normalisePhone(phone);
    state = state.copyWith(
      isLoading: true,
      error: null,
      clearSignOutReason: true,
    );
    try {
      final response = await _apiClient.register(
        phone: normalised,
        password: password,
        fullName: fullName.trim(),
        email: email.trim().isNotEmpty ? email.trim() : null,
      );
      _adoptToken(
        response.data,
        phone: normalised,
        email: email.trim(),
        name: fullName.trim(),
      );
      await _loadProfile();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _extractError(e));
    }
  }

  void _adoptToken(
    dynamic data, {
    String phone = '',
    String email = '',
    String name = '',
  }) {
    if (data is! Map) {
      throw const FormatException('Sign in returned an unexpected response');
    }
    final token = data['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const FormatException('Sign in returned no access token');
    }
    _session.persistTokens(
      accessToken: token,
      refreshToken: data['refresh_token'] as String?,
      expiresIn: (data['expires_in'] as num?)?.toInt(),
    );
    final uid = _extractUserId(token);
    _saveProfile(email: email, phone: phone, name: name, userId: uid);
    state = AuthState(
      isAuthenticated: true,
      email: email,
      phone: phone,
      driverName: name,
      userId: uid,
    );
  }

  /// Pulls the canonical profile from `GET /auth/me`.
  ///
  /// This is also the session's liveness check: it goes through
  /// [AuthSession.send], so an expired access token is rotated here, quietly,
  /// on app start — the whole point being that a driver is never dumped to the
  /// login screen in the middle of a shift.
  Future<void> _loadProfile() async {
    try {
      final response = await _session.send(() => _apiClient.get('/auth/me'));
      final data = response.data;
      if (data is! Map) return;
      final name = data['full_name'] as String? ?? state.driverName;
      final phone = data['phone'] as String? ?? state.phone;
      final email = data['email'] as String? ?? state.email;
      final uid = data['id'] as String? ?? state.userId;
      _saveProfile(email: email, phone: phone, name: name, userId: uid);
      state = state.copyWith(
        isAuthenticated: true,
        isLoading: false,
        driverName: name,
        phone: phone,
        email: email,
        userId: uid,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        _onSessionExpired();
        return;
      }
      // Offline or server hiccup — keep the cached profile.
      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('AuthNotifier: profile load failed: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// Re-reads the profile on demand (pull-to-refresh on the account screen).
  Future<void> refreshProfile() => _loadProfile();

  /// Signs the driver out on this device and revokes this device's refresh
  /// token server-side, so a lost phone cannot keep minting access tokens.
  Future<void> logout() async {
    await _session.clear();
    state = const AuthState(signOutReason: SignOutReason.userInitiated);
  }

  void _onSessionExpired() {
    if (!state.isAuthenticated) return;
    // The refresh token is spent or revoked; nothing to revoke server-side.
    unawaited(_session.clear(revokeOnServer: false));
    state = const AuthState(signOutReason: SignOutReason.sessionExpired);
  }

  /// Clears the "your session expired" banner once the driver has read it.
  void acknowledgeSignOut() {
    if (state.signOutReason == null) return;
    state = state.copyWith(clearSignOutReason: true);
  }

  void _saveProfile({
    String email = '',
    String phone = '',
    String name = '',
    String? userId,
  }) {
    try {
      final box = Hive.box(_SessionKeys.box);
      if (email.isNotEmpty) box.put(_SessionKeys.email, email);
      if (phone.isNotEmpty) box.put(_SessionKeys.phone, phone);
      if (name.isNotEmpty) box.put(_SessionKeys.driverName, name);
      if (userId != null) box.put(_SessionKeys.userId, userId);
    } catch (e) {
      debugPrint('AuthNotifier: could not persist profile: $e');
    }
  }

  /// Decode the JWT payload to read `sub` (the user id).
  ///
  /// This is a convenience only — the token is verified by the server, never
  /// here, and nothing security-relevant is decided from this value.
  String? _extractUserId(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return map['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Turns any failure into one sentence a driver can act on. Never surfaces
  /// a raw exception or an HTTP status (§5.5).
  String _extractError(dynamic e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'The connection timed out. Check your signal and try again.';
        case DioExceptionType.connectionError:
          return 'No connection. Check your mobile data and try again.';
        default:
          break;
      }
      final status = e.response?.statusCode;
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) {
        final detail = data['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] != null) {
            return first['msg'].toString();
          }
        }
      }
      if (status == 401) return 'That phone number or password is not right.';
      if (status == 403) {
        return 'This account is not active. Contact Zvingo driver support.';
      }
      if (status == 429) {
        return 'Too many attempts. Wait a minute and try again.';
      }
      if (status != null && status >= 500) {
        return 'Zvingo is having trouble right now. Try again in a moment.';
      }
      return 'Could not sign you in. Try again.';
    }
    if (e is FormatException) return e.message;
    return 'Something went wrong. Try again.';
  }
}

/// The shared session — token storage plus refresh-on-401 replay.
///
/// Every provider that calls an authenticated endpoint should route through
/// `ref.read(authSessionProvider).send(...)` rather than calling `ApiClient`
/// directly, so one expired access token does not surface as a blank screen.
final authSessionProvider = Provider<AuthSession>((ref) {
  return AuthSession(ref.read(apiClientProvider));
});

/// Global auth provider.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(apiClientProvider),
    ref.read(authSessionProvider),
  );
});
