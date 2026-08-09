import 'package:flutter/foundation.dart';

/// Static application configuration.
///
/// Values can be injected at build time via --dart-define, e.g.
///   flutter run --dart-define=API_BASE_URL=https://api.mindease.local
class AppConfig {
  AppConfig._();

  /// Base URL of the Spring Boot backend (/api/v1 endpoints).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1',
  );

  /// Base URL of the AI service (rarely called directly from the app).
  static const String aiServiceUrl = String.fromEnvironment(
    'AI_SERVICE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  /// Keycloak authorization endpoint (authorization-code flow).
  static const String authServerUrl = String.fromEnvironment(
    'AUTH_SERVER_URL',
    defaultValue: 'http://10.0.2.2:8081',
  );

  static const String realm =
      String.fromEnvironment('AUTH_REALM', defaultValue: 'mindease');
  static const String clientId =
      String.fromEnvironment('AUTH_CLIENT_ID', defaultValue: 'mindease-app');

  static const String initialRoute = '/dashboard';
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: kReleaseMode ? 'production' : 'development',
  );
}
