import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the token pair in encrypted storage on the device.
///
/// All reads are guarded so that platform-channel availability (widget tests,
/// headless runs) never crashes the flow — a missing token simply means the
/// user is not authenticated.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> accessToken() async {
    try {
      final token = await _storage.read(key: _kAccess);
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  Future<String?> refreshToken() async {
    try {
      final token = await _storage.read(key: _kRefresh);
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  Future<void> save({required String accessToken, required String refreshToken}) async {
    try {
      await _storage.write(key: _kAccess, value: accessToken);
      await _storage.write(key: _kRefresh, value: refreshToken);
    } catch (_) {
      // Non-fatal in tests / headless runs.
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
    } catch (_) {
      // Non-fatal.
    }
  }
}