import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/network/dio_client.dart';
import 'package:mindease/features/auth/domain/entities/login_params.dart';

/// Remote auth API (proxies Keycloak via the backend token endpoint).
///
/// Every response is wrapped in the standard ApiResponse envelope
/// `{success, data}` — the inner `data` is unwrapped here.
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client);

  final DioClient _client;

  Map<String, dynamic> _unwrapBody(Map<String, dynamic>? body) {
    final payload = body?['data'];
    if (payload is! Map) {
      throw const ServerFailure('The server returned an invalid response.');
    }
    return payload as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(LoginParams params) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': params.email, 'password': params.password},
    );
    return _unwrapBody(response.data);
  }

  /// Fetches the current user profile from `GET /users/me`.
  Future<Map<String, dynamic>> fetchProfile() async {
    final response = await _client.get<Map<String, dynamic>>('/users/me');
    return _unwrapBody(response.data);
  }
}
