import 'package:mindease/core/network/dio_client.dart';
import 'package:mindease/features/auth/domain/entities/login_params.dart';

/// Remote auth API (proxies Keycloak via the backend token endpoint).
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client);

  final DioClient _client;

  Future<Map<String, dynamic>> login(LoginParams params) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': params.email, 'password': params.password},
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> fetchProfile() async {
    final response = await _client.get<Map<String, dynamic>>('/auth/me');
    return response.data ?? const {};
  }
}
