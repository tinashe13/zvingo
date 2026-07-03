import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../core/api_client.dart';

/// Auth state.
class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;
  final String email;
  final String driverName;
  final String? userId;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
    this.email = '',
    this.driverName = '',
    this.userId,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
    String? email,
    String? driverName,
    String? userId,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      email: email ?? this.email,
      driverName: driverName ?? this.driverName,
      userId: userId ?? this.userId,
    );
  }
}

/// Auth provider — matches consumer_app auth pattern.
class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _apiClient;

  AuthNotifier(this._apiClient) : super(const AuthState()) {
    _restoreSession();
  }

  void _restoreSession() {
    final box = Hive.box('settings');
    final token = box.get('access_token') as String?;
    if (token != null && token.isNotEmpty) {
      _apiClient.setAuthToken(token);
      state = AuthState(
        isAuthenticated: true,
        email: box.get('email') as String? ?? '',
        driverName: box.get('driver_name') as String? ?? '',
        userId: box.get('user_id') as String?,
      );
    }
  }

  /// Login with email/phone + password.
  /// Backend uses OAuth2 form-urlencoded: POST /auth/token
  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _apiClient.login(
        username: email,
        password: password,
      );
      final token = response.data['access_token'] as String;
      final uid = _extractUserId(token);
      _apiClient.setAuthToken(token);
      _saveSession(token: token, email: email, userId: uid);
      state = AuthState(
        isAuthenticated: true,
        email: email,
        userId: uid,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _extractError(e),
      );
    }
  }

  /// Register a new driver account.
  /// Backend uses JSON: POST /auth/register
  Future<void> register(String name, String phone, String email,
      String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _apiClient.register(
        phone: phone,
        password: password,
        fullName: name,
        email: email.isNotEmpty ? email : null,
      );
      final token = response.data['access_token'] as String;
      final uid = _extractUserId(token);
      _apiClient.setAuthToken(token);
      _saveSession(token: token, email: email, name: name, userId: uid);
      state = AuthState(
        isAuthenticated: true,
        email: email,
        driverName: name,
        userId: uid,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _extractError(e),
      );
    }
  }

  void logout() {
    _apiClient.setAuthToken(null);
    Hive.box('settings').clear();
    state = const AuthState();
  }

  void _saveSession({
    required String token,
    String email = '',
    String name = '',
    String? userId,
  }) {
    final box = Hive.box('settings');
    box.put('access_token', token);
    box.put('email', email);
    box.put('driver_name', name);
    if (userId != null) box.put('user_id', userId);
  }

  /// Decode JWT payload to extract sub (user ID).
  String? _extractUserId(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      // Pad base64 to multiple of 4
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return map['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _extractError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('detail')) {
        return data['detail'].toString();
      }
      return e.message ?? 'Network error';
    }
    if (e is Exception) return e.toString().replaceFirst('Exception: ', '');
    return 'An error occurred';
  }
}

/// Global auth provider.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiClientProvider));
});
