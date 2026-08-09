import 'package:consumer_app/core/api_client.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:dio/dio.dart';

part 'auth_provider.g.dart';

@riverpod
class Auth extends _$Auth {
  @override
  FutureOr<void> build() {}

  /// Login with phone + OTP (placeholder for future OTP flow)
  Future<bool> login(String phone, String otp) async {
    state = const AsyncValue.loading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      final dio = ref.read(apiClientProvider);
      final response = await dio.post(
        '/auth/token',
        data: {
          'username': phone,
          'password': otp,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      // Store token
      final token = response.data['access_token'];
      if (token != null) {
        final box = Hive.box('settings');
        await box.put('access_token', token);
        success = true;
      }
    });
    if (success) ref.invalidate(locationStartupProvider);
    return success;
  }

  /// Login with email + password
  Future<bool> loginWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      final dio = ref.read(apiClientProvider);
      final response = await dio.post(
        '/auth/token',
        data: {
          'username': email,
          'password': password,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final token = response.data['access_token'];
      if (token != null) {
        final box = Hive.box('settings');
        await box.put('access_token', token);
        success = true;
      }
    });
    if (success) ref.invalidate(locationStartupProvider);
    return success;
  }

  /// Register a new consumer account
  Future<bool> register(
      String name, String email, String phone, String password) async {
    state = const AsyncValue.loading();
    bool success = false;
    state = await AsyncValue.guard(() async {
      final dio = ref.read(apiClientProvider);
      final response = await dio.post('/auth/register', data: {
        'phone': phone,
        'password': password,
        'full_name': name,
        'email': email.isNotEmpty ? email : null,
        'role': 'consumer',
      });
      final token = response.data['access_token'];
      if (token != null) {
        final box = Hive.box('settings');
        await box.put('access_token', token);
        success = true;
      }
    });
    if (success) ref.invalidate(locationStartupProvider);
    return success;
  }

  /// Sign out
  Future<void> signOut() async {
    final box = Hive.box('settings');
    await box.delete('access_token');
    await box.delete('user_id');
    ref.read(deliveryLocationNotifierProvider.notifier).clear();
  }

  /// Check if logged in
  bool get isLoggedIn {
    final box = Hive.box('settings');
    final token = box.get('access_token');
    return token != null && token.toString().isNotEmpty;
  }
}

/// Provider for user profile data
@riverpod
Future<Map<String, dynamic>> userProfile(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  try {
    final response = await dio.get('/auth/me');
    return Map<String, dynamic>.from(response.data);
  } catch (e) {
    return {'full_name': 'User', 'email': '', 'phone': '', 'id': ''};
  }
}
