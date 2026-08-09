// User domain entity.
import 'package:equatable/equatable.dart';

class User extends Equatable {
  const User({
    required this.id,
    required this.email,
    this.displayName,
    this.roles = const ['user'],
  });

  final String id;
  final String email;
  final String? displayName;
  final List<String> roles;

  @override
  List<Object?> get props => [id, email, displayName, roles];
}
