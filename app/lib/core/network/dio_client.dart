import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:mindease/core/config/app_config.dart';

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
        baseUrl: AppConfig.apiBaseUrl,
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

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip attaching tokens to the refresh endpoint itself to avoid loops.
    if (options.path == '/auth/refresh') {
      handler.next(options);
      return;
    }
    final token = await _secureStorage.read(key: 'access_token');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
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
      final response = await Dio().post<Map<String, dynamic>>(
        '${AppConfig.apiBaseUrl}/auth/refresh',
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
