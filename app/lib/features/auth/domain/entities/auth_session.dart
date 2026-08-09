import 'package:equatable/equatable.dart';

class AuthSession extends Equatable {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final dynamic user;

  @override
  List<Object?> get props => [accessToken, refreshToken, expiresIn, user];
}
