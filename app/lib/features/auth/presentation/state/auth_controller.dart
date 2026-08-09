import 'package:flutter/foundation.dart';

import 'package:mindease/features/auth/domain/entities/auth_session.dart';
import 'package:mindease/features/auth/domain/entities/login_params.dart';
import 'package:mindease/features/auth/domain/entities/user.dart';
import 'package:mindease/features/auth/domain/repositories/auth_repository.dart';

/// Authentication state management via ChangeNotifier.
class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthRepository _repository;

  AuthStatus _status = AuthStatus.unknown;
  AuthSession? _session;
  User? _user;
  String? _error;

  AuthStatus get status => _status;
  AuthSession? get session => _session;
  User? get user => _user;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  Future<void> login(String email, String password) async {
    _error = null;
    notifyListeners();
    try {
      _session = await _repository
          .login(LoginParams(email: email, password: password));
      _user = await _repository.getCurrentUser();
      _status = AuthStatus.authenticated;
    } catch (e) {
      _error = e.toString();
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _repository.logout();
    _session = null;
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
