import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:mindease/core/config/app_config.dart';
import 'package:mindease/core/config/server_endpoint.dart';

/// Thin wrapper around Dio giving a single configured HTTP client with
/// automatic token refresh on 401 responses.
///
/// When a request receives a 401 (Unauthorized), the interceptor attempts
/// to use the stored refresh token to obtain a new access token via
/// `POST /auth/refresh`, then retries the original request exactly once.
/// If refresh also fails the user's session is considered expired and
/// [onSessionExpired] is invoked (if set).
class DioClient {
  DioClient({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ServerEndpoint.current,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: Headers.jsonContentType,
      ),
    );
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ),);
  }

  late final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  bool _isRefreshing = false;

  /// Called when the session has expired (refresh token invalid/missing).
  /// Set this to trigger navigation to the login screen.
  VoidCallback? onSessionExpired;

  Dio get dio => _dio;

  /// Points every later request at [baseUrl]. Used when the user changes the
  /// server address for this device, so the change applies immediately instead
  /// of only after a restart.
  void setBaseUrl(String baseUrl) {
    if (baseUrl.isEmpty) return;
    _dio.options.baseUrl = baseUrl;
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Resolve the address at request time, so an address changed in Settings
    // applies to the very next request without restarting the app.
    options.baseUrl = ServerEndpoint.current;

    // Skip attaching tokens to the refresh endpoint itself to avoid loops.
    if (options.path == '/auth/refresh') {
      handler.next(options);
      return;
    }
    final token = await _secureStorage.read(key: 'access_token');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    final offset = DateTime.now().timeZoneOffset;
    final h = offset.inHours;
    final m = offset.inMinutes.remainder(60).abs();
    options.headers['X-User-Timezone'] =
        'UTC${h >= 0 ? '+' : '-'}${h.abs().toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only attempt refresh once, and only for 401 on non-auth endpoints.
    if (err.response?.statusCode == 401 &&
        !err.requestOptions.path.startsWith('/auth/') &&
        !_isRefreshing) {
      final refreshed = await _attemptTokenRefresh();
      if (refreshed) {
        // Retry the original request with the new token.
        try {
          final newToken = await _secureStorage.read(key: 'access_token');
          err.requestOptions.headers['Authorization'] =
              'Bearer ${newToken ?? ''}';
          final response = await _dio.fetch(err.requestOptions);
          handler.resolve(response);
          return;
        } on DioException catch (retryError) {
          handler.next(retryError);
          return;
        }
      } else {
        // Refresh failed — session is expired. Notify the app.
        onSessionExpired?.call();
      }
    }
    handler.next(err);
  }

  /// Attempts to use the refresh token to obtain a new access token.
  /// Returns `true` if the refresh succeeded.
  Future<bool> _attemptTokenRefresh() async {
    _isRefreshing = true;
    try {
      final refreshToken = await _secureStorage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) return false;

      // Use a bare Dio instance without interceptors to avoid recursion.
      // Timeouts match the main client: an unbounded refresh call could
      // otherwise stall app startup (e.g. splash session check) far beyond
      // the normal connect/receive budgets when the network drops packets.
      final refresher = Dio(
        BaseOptions(
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
        ),
      );
      final response = await refresher.post<Map<String, dynamic>>(
        '${ServerEndpoint.current}/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      final body = response.data;
      final data = body?['data'];
      if (data is! Map) return false;

      final newAccess = data['accessToken'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (newAccess == null || newAccess.isEmpty) return false;

      await _secureStorage.write(key: 'access_token', value: newAccess);
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await _secureStorage.write(key: 'refresh_token', value: newRefresh);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query}) =>
      _dio.get<T>(path, queryParameters: query);

  Future<Response<T>> post<T>(String path, {Object? data}) =>
      _dio.post<T>(path, data: data);

  Future<Response<T>> put<T>(String path, {Object? data}) =>
      _dio.put<T>(path, data: data);

  Future<Response<T>> delete<T>(String path) => _dio.delete<T>(path);
}
