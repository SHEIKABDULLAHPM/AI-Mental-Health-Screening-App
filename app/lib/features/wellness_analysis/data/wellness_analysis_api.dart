import 'package:dio/dio.dart';

import 'package:mindease/core/api/models.dart';
import 'package:mindease/core/error/error_mapper.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/network/dio_client.dart';

class WellnessAnalysisApi {
  WellnessAnalysisApi(this._client);

  final DioClient _client;

  Map<String, dynamic> _unwrapBody(Map<String, dynamic>? body) {
    final payload = body?['data'];
    if (payload is! Map) {
      throw const ServerFailure('The server returned an invalid response.');
    }
    return payload as Map<String, dynamic>;
  }

  Future<MentalWellnessAnalysis> analyzeMentalWellness() async {
    return _guard(() async {
      final body = await _client.post<Map<String, dynamic>>('/wellness/mental/analyze', data: const {});
      return MentalWellnessAnalysis.fromJson(_unwrapBody(body.data));
    });
  }

  Future<PhysicalWellnessAnalysis> analyzePhysicalWellness() async {
    return _guard(() async {
      final body = await _client.post<Map<String, dynamic>>('/physical/analyze', data: const {});
      return PhysicalWellnessAnalysis.fromJson(_unwrapBody(body.data));
    });
  }

  Future<CombinedWellnessAnalysis> analyzeCombinedWellness() async {
    return _guard(() async {
      final body = await _client.post<Map<String, dynamic>>('/wellness/combined/analyze', data: const {});
      return CombinedWellnessAnalysis.fromJson(_unwrapBody(body.data));
    });
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      throw mapDioError(e);
    } on Failure {
      rethrow;
    } on Object {
      throw const ServerFailure('Something went wrong.');
    }
  }
}
