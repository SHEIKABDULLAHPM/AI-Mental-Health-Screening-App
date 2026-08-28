import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mime/mime.dart';

import 'package:mindease/core/config/app_config.dart';
import 'package:mindease/core/error/failures.dart';

/// Handles file uploads to the backend media endpoint.
class MediaUploadService {
  MediaUploadService(this._dio);

  final Dio _dio;

  /// Upload a file and return the stored reference key.
  Future<MediaResult> upload({
    required File file,
    required String mediaType, // 'IMAGE', 'AUDIO', or 'VIDEO'
  }) async {
    try {
      final fileName = file.path.split('/').last;
      final contentType = lookupMimeType(file.path) ??
          (mediaType == 'AUDIO' ? 'audio/mp4' : 'image/jpeg');
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
        'type': mediaType,
      });

      final response = await _dio.post<Map<String, dynamic>>(
        '${AppConfig.apiBaseUrl}/media/upload',
        data: formData,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      final body = response.data;
      final data = body?['data'];
      if (data is! Map) {
        throw const ServerFailure('Upload failed: invalid server response.');
      }

      final key = data['key'] as String? ?? '';
      if (key.isEmpty) {
        throw const ServerFailure('Upload failed: missing media reference.');
      }

      return MediaResult(
        key: key,
        mediaType: data['mediaType'] as String? ?? mediaType,
        contentType: data['contentType'] as String? ?? '',
        size: (data['size'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 413) {
        throw const ServerFailure(
          'File is too large. Please choose a smaller file.',
        );
      }
      throw ServerFailure('Upload failed: ${e.message ?? "network error"}');
    } on Failure {
      rethrow;
    } catch (e) {
      throw ServerFailure('Upload failed: $e');
    }
  }

  /// Delete a media object by key.
  Future<void> delete(String key) async {
    try {
      await _dio.delete<Map<String, dynamic>>(
        '${AppConfig.apiBaseUrl}/media',
        queryParameters: {'key': key},
      );
    } catch (_) {
      // Best-effort: don't block UI on media cleanup failure.
    }
  }
}

class MediaResult {
  const MediaResult({
    required this.key,
    required this.mediaType,
    required this.contentType,
    required this.size,
  });

  final String key;
  final String mediaType;
  final String contentType;
  final int size;
}
