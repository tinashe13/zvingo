import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'app_config.dart';

/// API client for REST endpoints.
/// Mirrors the consumer_app pattern — Dio with JWT auth and base URL.
class ApiClient {
  late final Dio _dio;

  ApiClient({String? baseUrl}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl ?? AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.connectTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Auto-attach JWT from Hive if available
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final box = Hive.box('settings');
        final token = box.get('access_token');
        if (token != null && token.toString().isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  /// Set the auth token for all subsequent requests.
  void setAuthToken(String? token) {
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  // ── Auth Endpoints ──────────────────────────────────────

  /// Login — POST /auth/token (OAuth2 form-urlencoded)
  Future<Response> login({
    required String username,
    required String password,
  }) {
    return _dio.post(
      '/auth/token',
      data: {
        'username': username,
        'password': password,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  /// Register — POST /auth/register (JSON)
  Future<Response> register({
    required String phone,
    required String password,
    required String fullName,
    String? email,
  }) {
    return _dio.post('/auth/register', data: {
      'phone': phone,
      'password': password,
      'full_name': fullName,
      'email': email,
      'role': 'driver',
    });
  }

  /// Update dash session (start/stop dashing).
  Future<Response> updateDashSession({
    required bool active,
    double? lat,
    double? lng,
    int? radius,
  }) {
    return _dio.post('/driver/dash/session', data: {
      'active': active,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (radius != null) 'radius': radius,
    });
  }

  // ── Generic HTTP Methods ────────────────────────────────

  Future<Response> get(String path) => _dio.get(path);

  Future<Response> post(String path,
          {dynamic data, Options? options}) =>
      _dio.post(path, data: data, options: options);

  Future<Response> put(String path, {Map<String, dynamic>? data}) =>
      _dio.put(path, data: data);

  // ── Earnings / Finance Endpoints ────────────────────────

  /// Get driver earnings summary (today + this week).
  Future<Response> getDriverEarnings(String driverId) =>
      _dio.get('/finance/earnings/driver/$driverId');

  /// Get daily earnings breakdown (last N days).
  Future<Response> getDailyBreakdown(String driverId, {int days = 30}) =>
      _dio.get('/finance/earnings/driver/$driverId/daily', queryParameters: {'days': days});

  /// Record a completed delivery earning.
  Future<Response> recordEarning({
    required String orderId,
    required String driverId,
  }) =>
      _dio.post('/finance/earnings/record', queryParameters: {
        'order_id': orderId,
        'driver_id': driverId,
      });

  /// Get paginated earnings history with optional filters.
  Future<Response> getEarningsHistory(
    String driverId, {
    String? startDate,
    String? endDate,
    String? paymentMethod,
    int? minAmountCents,
    String? merchantName,
    String? area,
    int page = 1,
    int pageSize = 20,
  }) {
    final params = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (startDate != null) params['start_date'] = startDate;
    if (endDate != null) params['end_date'] = endDate;
    if (paymentMethod != null) params['payment_method'] = paymentMethod;
    if (minAmountCents != null) params['min_amount_cents'] = minAmountCents;
    if (merchantName != null) params['merchant_name'] = merchantName;
    if (area != null) params['area'] = area;
    return _dio.get(
      '/finance/earnings/driver/$driverId/history',
      queryParameters: params,
    );
  }
}

/// Global provider for ApiClient.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});
