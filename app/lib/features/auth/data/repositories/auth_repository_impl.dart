import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:mindease/core/error/error_mapper.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mindease/features/auth/data/models/user_model.dart';
import 'package:mindease/features/auth/domain/entities/auth_session.dart';
import 'package:mindease/features/auth/domain/entities/login_params.dart';
import 'package:mindease/features/auth/domain/entities/user.dart';
import 'package:mindease/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote, {FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final AuthRemoteDataSource _remote;
  final FlutterSecureStorage _storage;
  final _statusController = StreamController<AuthStatus>.broadcast();

  @override
  Stream<AuthStatus> get status => _statusController.stream;

  @override
  Future<AuthSession> login(LoginParams params) async {
    try {
      final data = await _remote.login(params);
      final accessToken = data['accessToken'] as String?;
      final refreshToken = data['refreshToken'] as String?;
      if (accessToken == null || accessToken.isEmpty || refreshToken == null || refreshToken.isEmpty) {
        throw const ServerFailure('The server returned an invalid response.');
      }
      final session = AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresIn: data['expiresIn'] as int? ?? 3600,
      );
      await _storage.write(key: 'access_token', value: session.accessToken);
      await _storage.write(key: 'refresh_token', value: session.refreshToken);
      _statusController.add(AuthStatus.authenticated);
      return session;
    } on Failure {
      rethrow;
    } catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<User> getCurrentUser() async {
    try {
      final data = await _remote.fetchProfile();
      final model = UserModel.fromJson(data);
      return User(
        id: model.id,
        email: model.email,
        displayName: model.displayName,
        roles: model.roles,
      );
    } on Failure {
      rethrow;
    } catch (e) {
      throw mapDioError(e);
    }
  }

  @override
  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    _statusController.add(AuthStatus.unauthenticated);
  }
}
