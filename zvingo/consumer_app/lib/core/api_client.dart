import 'package:consumer_app/core/app_config.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api_client.g.dart';

@riverpod
Dio apiClient(ApiClientRef ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Auth interceptor: attach Bearer token from Hive
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
      // On 401, clear token and let the UI handle redirect
      if (error.response?.statusCode == 401) {
        final box = Hive.box('settings');
        box.delete('access_token');
      }
      handler.next(error);
    },
  ));

  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
  ));

  return dio;
}
