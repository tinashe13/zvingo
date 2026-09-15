import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/features/auth/token_store.dart';

part 'session_interceptor.g.dart';

/// Paths that must never trigger a refresh — refreshing on a failed login is
/// both pointless and a way to loop forever.
const Set<String> _noRefreshPaths = <String>{
  '/auth/token',
  '/auth/register',
  '/auth/refresh',
  '/auth/otp/request',
  '/auth/otp/verify',
  '/auth/reset-password/request',
  '/auth/reset-password/confirm',
};

/// Keeps the user signed in across a token expiry, silently.
///
/// The backend (agent F4) issues short-lived access tokens alongside a
/// **single-use, rotating** refresh token: once `/auth/refresh` consumes a
/// refresh token, that token is dead and a replay is a 401. Two consequences
/// shape this class:
///
/// * **Only one refresh may ever be in flight.** If five requests 401 at once
///   and each refreshes, four of them replay a consumed token, the server
///   treats that as theft, and the session is revoked. [_refresh] is therefore
///   single-flighted: concurrent callers await the same future.
/// * **Both tokens must be replaced from the response**, not just the access
///   token, or the next refresh presents a token that no longer exists.
///
/// It also refreshes *proactively* in `onRequest` when the access token is
/// about to expire, so a person placing an order never even sees the 401 that
/// would otherwise bounce them to the sign-in screen.
class ZvSessionInterceptor extends Interceptor {
  ZvSessionInterceptor(this._dio);

  /// The app's shared client. Used only to replay the original request.
  final Dio _dio;

  /// Refresh this long before the advertised expiry.
  static const Duration refreshLeeway = Duration(seconds: 60);

  Future<bool>? _inFlight;

  /// Set when a refresh has definitively failed, so the app can show "you were
  /// signed out" rather than silently landing on the login screen.
  bool sessionExpired = false;

  bool _isAuthPath(String path) =>
      _noRefreshPaths.any((p) => path.endsWith(p));

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isAuthPath(options.path) &&
        TokenStore.refreshToken != null &&
        TokenStore.expiresWithin(refreshLeeway)) {
      await _refresh();
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final path = err.requestOptions.path;
    final alreadyRetried = err.requestOptions.extra['zv_retried'] == true;

    if (status != 401 ||
        alreadyRetried ||
        _isAuthPath(path) ||
        TokenStore.refreshToken == null) {
      handler.next(err);
      return;
    }

    final refreshed = await _refresh();
    if (!refreshed) {
      handler.next(err);
      return;
    }

    try {
      final options = err.requestOptions;
      options.extra = {...options.extra, 'zv_retried': true};
      // Drop the stale header; the request interceptor re-attaches the new one.
      options.headers.remove('Authorization');
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (_) {
      handler.next(err);
    }
  }

  /// Exchange the stored refresh token for a new pair. Single-flighted.
  Future<bool> _refresh() {
    return _inFlight ??= _performRefresh().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final token = TokenStore.refreshToken;
    if (token == null) return false;

    // A bare client: going through the shared Dio would re-enter this
    // interceptor and, on a 401 from /auth/refresh itself, recurse.
    final plain = Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    try {
      final response = await plain.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': token},
      );
      final data = response.data;
      if (data is Map && data['access_token'] != null) {
        await TokenStore.saveTokenResponse(Map<String, dynamic>.from(data));
        sessionExpired = false;
        return true;
      }
      return false;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // 401/403 means the refresh token is spent, revoked or forged: the
      // session is genuinely over. A network error is not — keep the token so
      // the next attempt, once back online, can still succeed.
      if (status == 401 || status == 403) {
        await TokenStore.clearSession();
        sessionExpired = true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      plain.close(force: true);
    }
  }
}

/// Installs [ZvSessionInterceptor] on the app's shared Dio, exactly once.
///
/// It is inserted at index 0 so it sees a 401 *before*
/// `core/api_client.dart`'s handler deletes the access token — a refresh that
/// succeeds leaves the session intact instead of bouncing the user to sign-in
/// in the middle of an order.
///
/// Read from [Auth], from [userProfile] and from `locationStartup` (which the
/// app shell watches on mount), so it is live before the first tab fetches
/// anything.
@Riverpod(keepAlive: true)
ZvSessionInterceptor authSession(Ref ref) {
  final dio = ref.watch(apiClientProvider);
  final existing = dio.interceptors.whereType<ZvSessionInterceptor>();
  if (existing.isNotEmpty) return existing.first;

  final interceptor = ZvSessionInterceptor(dio);
  dio.interceptors.insert(0, interceptor);
  return interceptor;
}
