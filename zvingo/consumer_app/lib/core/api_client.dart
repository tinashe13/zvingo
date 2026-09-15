import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:consumer_app/core/app_config.dart';

part 'api_client.g.dart';

/// The app's single Dio instance.
///
/// The base URL comes from [AppConfig.apiBaseUrl], which is resolved from
/// `--dart-define` at build time — no host is hardcoded here.
@riverpod
Dio apiClient(Ref ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Auth interceptor: attach the Bearer token from Hive.
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final box = Hive.box('settings');
      final token = box.get('access_token');
      if (token != null && token.toString().isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) {
      // On 401, clear the token and let the router redirect to sign-in.
      if (error.response?.statusCode == 401) {
        final box = Hive.box('settings');
        box.delete('access_token');
      }
      handler.next(error);
    },
  ));

  // Request/response bodies carry bearer tokens, addresses and phone numbers.
  // Log them in debug only — never in a profile or release build.
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(requestBody: true, responseBody: true),
    );
  }

  return dio;
}
