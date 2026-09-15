import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/auth/phone_number.dart';
import 'package:consumer_app/features/auth/session_interceptor.dart';
import 'package:consumer_app/features/auth/token_store.dart';

part 'auth_provider.g.dart';

/// The signed-in person, as `GET /auth/me` returns them.
class ZvUserProfile {
  const ZvUserProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    this.role = 'consumer',
    this.isActive = true,
  });

  final String id;
  final String fullName;
  final String phone;
  final String? email;
  final String role;
  final bool isActive;

  factory ZvUserProfile.fromJson(Map<String, dynamic> json) => ZvUserProfile(
        id: json['id']?.toString() ?? '',
        fullName: (json['full_name'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        email: (json['email']?.toString().isEmpty ?? true)
            ? null
            : json['email'].toString(),
        role: (json['role'] ?? 'consumer').toString(),
        isActive: json['is_active'] ?? true,
      );

  /// "Tinashe Moyo" -> "TM". Falls back to a person glyph upstream when empty.
  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String get displayPhone => ZvPhone.formatDisplay(phone);

  ZvUserProfile copyWith({String? fullName, String? email}) => ZvUserProfile(
        id: id,
        fullName: fullName ?? this.fullName,
        phone: phone,
        email: email ?? this.email,
        role: role,
        isActive: isActive,
      );
}

/// Why an auth attempt failed, in words a user can act on.
///
/// The server deliberately answers identically for "no such account" and
/// "wrong password" (an enumeration oracle would let anyone test whether a
/// phone number is registered), so the copy here must not invent a distinction
/// the API does not make.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.retryAfterSeconds});

  final String message;
  final int? retryAfterSeconds;

  @override
  String toString() => message;

  static AuthFailure from(Object error, {required String fallback}) {
    if (error is AuthFailure) return error;
    if (error is DioException) {
      final status = error.response?.statusCode;
      final detail = _detailOf(error.response?.data);
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return const AuthFailure(
          'We could not reach Zvingo. Check your connection and try again.',
        );
      }
      if (status == 429) {
        final retryAfter =
            int.tryParse('${error.response?.headers.value('retry-after')}');
        return AuthFailure(
          detail ??
              'Too many attempts. Please wait a moment before trying again.',
          retryAfterSeconds: retryAfter,
        );
      }
      if (status != null && status >= 500) {
        return const AuthFailure(
          'Zvingo is having trouble right now. Please try again in a minute.',
        );
      }
      if (detail != null) return AuthFailure(detail);
    }
    return AuthFailure(fallback);
  }

  /// FastAPI puts the message in `detail`, which is a string for
  /// `HTTPException` and a list of field errors for a validation failure.
  static String? _detailOf(Object? data) {
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          return (first['msg'] as String).replaceFirst('Value error, ', '');
        }
      }
    }
    return null;
  }
}

/// Every authentication action in the consumer app.
///
/// The notifier's `AsyncValue` state drives the submit button's spinner;
/// failures are surfaced as an [AuthFailure] the caller renders inline, never
/// as a raw exception or an HTTP status (§5.5).
@riverpod
class Auth extends _$Auth {
  @override
  FutureOr<void> build() {
    // Installing the refresh interceptor here means it is live from the very
    // first sign-in attempt onwards.
    ref.watch(authSessionProvider);
  }

  Dio get _dio => ref.read(apiClientProvider);

  /// Runs [action], keeping `state` in sync so the UI can show a spinner, and
  /// translating any failure into an [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() action,
      {required String fallback}) async {
    state = const AsyncValue.loading();
    try {
      final result = await action();
      state = const AsyncValue.data(null);
      return result;
    } catch (error, stack) {
      final failure = AuthFailure.from(error, fallback: fallback);
      state = AsyncValue.error(failure, stack);
      throw failure;
    }
  }

  Future<void> _adoptSession(Response<dynamic> response) async {
    final data = response.data;
    if (data is! Map || data['access_token'] == null) {
      throw const AuthFailure('Sign-in did not complete. Please try again.');
    }
    await TokenStore.saveTokenResponse(Map<String, dynamic>.from(data));
    ref.invalidate(userProfileProvider);
    ref.invalidate(locationStartupProvider);
  }

  /// `POST /auth/token` — the OAuth2 password grant. `username` is the phone in
  /// E.164 or the email address; the backend accepts either.
  Future<void> signInWithPassword({
    required String identifier,
    required String password,
  }) {
    return _guard(
      () async {
        final response = await _dio.post<dynamic>(
          '/auth/token',
          data: {'username': identifier, 'password': password},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        await _adoptSession(response);
      },
      fallback: 'That phone number, email or password is not right. '
          'Check them and try again.',
    );
  }

  Future<void> signInWithPhone({
    required String phone,
    required String password,
  }) {
    final e164 = ZvPhone.toE164(phone);
    if (e164 == null) {
      throw const AuthFailure('Enter your mobile number');
    }
    return signInWithPassword(identifier: e164, password: password);
  }

  /// `POST /auth/otp/request`. Always answers the same whether or not the
  /// number is registered, so the UI must not promise that a code is coming to
  /// a *known* account.
  Future<void> requestOtp(String phone) {
    final e164 = ZvPhone.toE164(phone);
    if (e164 == null) throw const AuthFailure('Enter your mobile number');
    return _guard(
      () async {
        await _dio.post<dynamic>('/auth/otp/request', data: {'phone': e164});
      },
      fallback: 'We could not send a code just now. Please try again.',
    );
  }

  /// `POST /auth/otp/verify` — returns a full token pair on success.
  Future<void> verifyOtp({required String phone, required String code}) {
    final e164 = ZvPhone.toE164(phone);
    if (e164 == null) throw const AuthFailure('Enter your mobile number');
    return _guard(
      () async {
        final response = await _dio.post<dynamic>(
          '/auth/otp/verify',
          data: {'phone': e164, 'code': code.trim()},
        );
        await _adoptSession(response);
      },
      fallback: 'That code is not right, or it has expired. '
          'Request a new one and try again.',
    );
  }

  /// `POST /auth/register`. The role is fixed to `consumer` — this app never
  /// creates drivers or merchants.
  Future<void> register({
    required String fullName,
    required String phone,
    required String password,
    String? email,
  }) {
    final e164 = ZvPhone.toE164(phone);
    if (e164 == null) throw const AuthFailure('Enter your mobile number');
    final trimmedEmail = email?.trim();
    return _guard(
      () async {
        final response = await _dio.post<dynamic>('/auth/register', data: {
          'phone': e164,
          'password': password,
          'full_name': fullName.trim(),
          if (trimmedEmail != null && trimmedEmail.isNotEmpty)
            'email': trimmedEmail,
          'role': 'consumer',
        });
        await _adoptSession(response);
      },
      fallback: 'We could not create your account. '
          'That phone number or email may already be in use.',
    );
  }

  /// `POST /auth/reset-password/request`.
  ///
  /// The reset code is delivered **only by SMS** — the server never returns it
  /// and this client never displays or logs it (see `backend/app/auth/router.py`
  /// `request_password_reset`). The response is identical for a registered and
  /// an unregistered number, so the UI says "if that number has an account".
  Future<void> requestPasswordReset(String phone) {
    final e164 = ZvPhone.toE164(phone);
    if (e164 == null) throw const AuthFailure('Enter your mobile number');
    return _guard(
      () async {
        await _dio.post<dynamic>(
          '/auth/reset-password/request',
          data: {'phone': e164},
        );
      },
      fallback: 'We could not start a password reset. Please try again.',
    );
  }

  /// `POST /auth/reset-password/confirm`. Completing a reset revokes every
  /// other session, so afterwards the user signs in fresh.
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) {
    return _guard(
      () async {
        await _dio.post<dynamic>('/auth/reset-password/confirm', data: {
          'token': code.trim(),
          'new_password': newPassword,
        });
        // The reset invalidated every token this device holds.
        await TokenStore.clearSession();
      },
      fallback: 'That code is not right, or it has expired. '
          'Request a new one and try again.',
    );
  }

  /// Sign out of this device.
  ///
  /// Tells the server to revoke this device's refresh token (`POST
  /// /auth/logout`), then clears **everything** on device: tokens, cart, cache,
  /// addresses, favourites and search history. A network failure never blocks
  /// the local half — the user tapped sign out and must end up signed out.
  Future<void> signOut() async {
    final refreshToken = TokenStore.refreshToken;
    try {
      await _dio.post<dynamic>(
        '/auth/logout',
        data: refreshToken == null ? null : {'refresh_token': refreshToken},
      );
    } catch (_) {
      // Offline, expired, already revoked — all fine. Clear locally anyway.
    }
    await TokenStore.clearEverything();
    ref.read(deliveryLocationNotifierProvider.notifier).clear();
    ref.invalidate(userProfileProvider);
    ref.invalidate(savedAddressesProvider);
    ref.invalidate(locationStartupProvider);
    state = const AsyncValue.data(null);
  }

  bool get isSignedIn => TokenStore.isSignedIn;
}

/// The signed-in user's profile.
///
/// Errors propagate: a screen showing a fabricated "User" profile because the
/// request failed is worse than one showing [ZvErrorState] with a Retry.
@riverpod
Future<ZvUserProfile> userProfile(Ref ref) async {
  ref.watch(authSessionProvider);
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get<dynamic>('/auth/me');
  final profile = ZvUserProfile.fromJson(
    Map<String, dynamic>.from(response.data as Map),
  );
  await TokenStore.saveUserId(profile.id);
  return profile;
}
