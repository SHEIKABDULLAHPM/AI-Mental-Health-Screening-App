// Converts exceptions into safe user-facing messages.
import 'package:dio/dio.dart';

import 'failures.dart';

Failure mapDioError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const NetworkFailure(
            'Unable to reach the server. Check your connection.',);
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        final message = _messageFromBody(error.response?.data);
        return ServerFailure(message, code: 'HTTP_$status');
      default:
        return const ServerFailure('Unexpected network error.');
    }
  }
  return ServerFailure('Unexpected error: ${error.toString()}');
}

String _messageFromBody(dynamic data) {
  if (data is Map && data['message'] is String) {
    return data['message'] as String;
  }
  return 'Server returned an error.';
}
