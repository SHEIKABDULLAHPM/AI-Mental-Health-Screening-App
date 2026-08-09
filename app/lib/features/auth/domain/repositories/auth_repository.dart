import 'dart:async';

import 'package:mindease/features/auth/domain/entities/auth_session.dart';
import 'package:mindease/features/auth/domain/entities/login_params.dart';
import 'package:mindease/features/auth/domain/entities/user.dart';

/// Auth repository contract (domain layer).
abstract class AuthRepository {
  Future<AuthSession> login(LoginParams params);
  Future<User> getCurrentUser();
  Future<void> logout();
  Stream<AuthStatus> get status;
}

enum AuthStatus { unknown, authenticated, unauthenticated }
