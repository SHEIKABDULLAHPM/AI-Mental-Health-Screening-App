import 'package:dio/dio.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/error/error_mapper.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/network/dio_client.dart';

/// Single thin client over every backend endpoint the onboarding journey uses.
///
/// Every accessor unwraps the ApiResponse envelope ({success, data}) and maps
/// transport errors to a user-facing [Failure].
class MindeaseApi {
  MindeaseApi(this._client);

  final DioClient _client;

  Map<String, dynamic> _unwrapBody(
    Map<String, dynamic>? body, {
    String requiredField = '',
  }) {
    final payload = body?['data'];
    if (payload is! Map) {
      throw const ServerFailure('The server returned an invalid response.');
    }
    final data = payload as Map<String, dynamic>;
    if (requiredField.isNotEmpty && data[requiredField] == null) {
      throw const ServerFailure('The server returned an invalid response.');
    }
    return data;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw mapDioError(e);
    } on Failure {
      rethrow;
    } catch (e) {
      throw mapDioError(e);
    }
  }

  // ------------------------------------------------------------------- Auth

  AuthSession _fromAuthBody(Map<String, dynamic>? body) {
    final data = _unwrapBody(body);
    final access = data['accessToken'] as String?;
    final refresh = data['refreshToken'] as String?;
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty) {
      throw const ServerFailure('The server returned an invalid response.');
    }
    return AuthSession(
      user: data['user'] is Map
          ? MindeaseUser.fromJson(data['user'] as Map<String, dynamic>)
          : const MindeaseUser(id: '', email: '', fullName: ''),
      accessToken: access,
      refreshToken: refresh,
    );
  }

  Future<AuthSession> register({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
  }) {
    return _guard(() async {
      final body = await _client.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'fullName': fullName,
          'email': email,
          'password': password,
          'confirmPassword': confirmPassword,
        },
      );
      return _fromAuthBody(body.data);
    });
  }

  Future<AuthSession> login(String email, String password) {
    return _guard(() async {
      final body = await _client.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return _fromAuthBody(body.data);
    });
  }

  Future<void> logout(String refreshToken) {
    return _guard(() async {
      await _client.post<Map<String, dynamic>>(
        '/auth/logout',
        data: {'refreshToken': refreshToken},
      );
    });
  }

  Future<MindeaseUser> me() {
    return _guard(() async {
      final body = await _client.get<Map<String, dynamic>>('/users/me');
      return MindeaseUser.fromJson(_unwrapBody(body.data));
    });
  }

  Future<void> forgotPassword(String email) {
    return _guard(() async {
      await _client.post<Map<String, dynamic>>(
        '/auth/forgot-password',
        data: {'email': email},
      );
    });
  }

  /// Verifies the OTP and returns the single-use reset token.
  Future<String> verifyOtp(String email, String otp) {
    return _guard(() async {
      final body = await _client.post<Map<String, dynamic>>(
        '/auth/verify-otp',
        data: {'email': email, 'otp': otp},
      );
      final data = _unwrapBody(body.data, requiredField: 'resetToken');
      return data['resetToken'] as String;
    });
  }

  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _guard(() async {
      await _client.post<Map<String, dynamic>>(
        '/auth/reset-password',
        data: {
          'email': email,
          'resetToken': resetToken,
          'newPassword': newPassword,
          'confirmPassword': confirmPassword,
        },
      );
    });
  }

  // ------------------------------------------------------------- Onboarding

  Future<bool> consentCompleted() {
    return _guard(() async {
      final body = await _client.get<Map<String, dynamic>>('/consent');
      final data = _unwrapBody(body.data);
      return data['completed'] == true;
    });
  }

  Future<void> acceptConsent() {
    return _guard(() async {
      await _client.post<Map<String, dynamic>>(
        '/consent',
        data: {
          'privacyPolicy': true,
          'termsAndConditions': true,
          'aiAnalysis': true,
          'secureStorage': true,
          'policyVersion': '1.0',
        },
      );
    });
  }

  // ------------------------------------------------------------- Screening

  Future<MindeaseCatalog> questionnaireCatalog() {
    return _guard(() async {
      final body =
          await _client.get<Map<String, dynamic>>('/screenings/questions');
      return MindeaseCatalog.fromJson(_unwrapBody(body.data));
    });
  }

  Future<Map<String, dynamic>> createScreening() {
    return _guard(() async {
      final body = await _client.post<Map<String, dynamic>>(
        '/screenings',
        data: <String, dynamic>{},
      );
      return _unwrapBody(body.data);
    });
  }

  Future<Map<String, dynamic>> saveScreening(
    String id,
    Map<String, dynamic> payload,
  ) {
    return _guard(() async {
      final body = await _client.put<Map<String, dynamic>>(
        '/screenings/$id',
        data: payload,
      );
      return _unwrapBody(body.data);
    });
  }

  Future<Map<String, dynamic>> submitScreening(String id) {
    return _guard(() async {
      final body =
          await _client.post<Map<String, dynamic>>('/screenings/$id/submit');
      return _unwrapBody(body.data);
    });
  }

  /// Current AI analysis job status. Returns an empty map when the job is
  /// unknown to the caller, so a stale/missing id degrades to "keep polling".
  Future<Map<String, dynamic>> aiAnalysisStatus(String jobId) async {
    try {
      final body = await _client
          .get<Map<String, dynamic>>('/ai-analysis/$jobId/status');
      return _unwrapBody(body.data);
    } on Failure {
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Re-queues a failed AI analysis job for another attempt.
  Future<Map<String, dynamic>> retryAiAnalysis(String jobId) {
    return _guard(() async {
      final body = await _client
          .post<Map<String, dynamic>>('/ai-analysis/$jobId/retry');
      return _unwrapBody(body.data);
    });
  }

  // ------------------------------------------------------- Profile & dashboard

  Future<MindeaseProfile?> wellnessProfile() async {
    try {
      final body = await _client.get<Map<String, dynamic>>('/wellness-profile');
      // A NOT_FOUND response means no profile yet -> treat as pending (null).
      if (body.data is! Map) return null;
      final inner = (body.data as Map<String, dynamic>)['data'];
      if (inner is! Map) return null;
      return MindeaseProfile.fromJson(inner as Map<String, dynamic>);
    } on Failure {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<MindeaseDashboard> dashboard() {
    return _guard(() async {
      final body = await _client.get<Map<String, dynamic>>('/dashboard');
      return MindeaseDashboard.fromJson(_unwrapBody(body.data));
    });
  }
}