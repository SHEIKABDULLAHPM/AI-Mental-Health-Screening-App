import 'package:dio/dio.dart';

import 'package:mindease/core/error/error_mapper.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/network/dio_client.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';

/// Thin client for every feature endpoint the controllers call.
///
/// Follows the same envelope convention as [MindeaseApi]: every response is
/// `{success, data}` and the inner `data` is unwrapped here.
class FeatureApi implements MoodApi {
  FeatureApi(this._client);

  final DioClient _client;

  // ──────────────────────────────────────── Envelope helpers

  Map<String, dynamic> _unwrapBody(Map<String, dynamic>? body) {
    final payload = body?['data'];
    if (payload is! Map) {
      throw const ServerFailure('The server returned an invalid response.');
    }
    return payload as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> _unwrapList(Map<String, dynamic>? body) {
    final payload = body?['data'];
    if (payload is! List) return const [];
    return [
      for (final item in payload)
        if (item is Map<String, dynamic>) item,
    ];
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

  // ──────────────────────────────────────── Mood Tracking

  @override
  Future<List<Map<String, dynamic>>> getMoodEntries() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>('/moods');
        return _unwrapList(res.data);
      });

  @override
  Future<void> recordMood({
    required String mood,
    String? emotion,
    String? note,
    String? source,
    double? confidence,
    String? aiSuggestedMood,
    List<Map<String, dynamic>>? aiObservations,
    int? intensity,
  }) =>
      _guard(() async {
        await _client.post<Map<String, dynamic>>(
          '/moods',
          data: {
            'mood': mood,
            if (emotion != null) 'emotion': emotion,
            if (note != null) 'note': note,
            if (source != null) 'source': source,
            if (confidence != null) 'confidence': confidence,
            if (aiSuggestedMood != null) 'aiSuggestedMood': aiSuggestedMood,
            if (aiObservations != null) 'aiObservations': aiObservations,
            if (intensity != null) 'intensity': intensity,
          },
        );
      });

  /// Analyze mood via the AI service (text emotion + camera fusion).
  @override
  Future<Map<String, dynamic>> analyzeMood({
    required String mood,
    String? emotion,
    String? note,
    Map<String, dynamic>? cameraObservation,
  }) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/moods/analyze',
          data: {
            'mood': mood,
            if (emotion != null) 'emotion': emotion,
            if (note != null) 'note': note,
            if (cameraObservation != null)
              'cameraObservation': cameraObservation,
          },
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<List<Map<String, dynamic>>> getMoodTrends({int days = 14}) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/moods/trends',
          query: {'days': days},
        );
        return _unwrapList(res.data);
      });

  /// Enhanced trends with emotion distribution, source breakdown, daily data.
  @override
  Future<Map<String, dynamic>> getEnhancedTrends({int days = 30}) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/moods/trends/enhanced',
          query: {'days': days},
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> getMoodEntry(String id) => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>('/moods/$id');
        return _unwrapBody(res.data);
      });

  @override
  Future<List<Map<String, dynamic>>> getRecentMoodEntries({int limit = 5}) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/moods/recent',
          query: {'limit': limit},
        );
        return _unwrapList(res.data);
      });

  @override
  Future<void> deleteMood(String id) => _guard(() async {
        await _client.delete<Map<String, dynamic>>('/moods/$id');
      });

  @override
  Future<Map<String, dynamic>> getStatistics() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>('/moods/stats');
        return _unwrapBody(res.data);
      });

  // ──────────────────────────────────────── Journal

  Future<Map<String, dynamic>> createJournalEntry({
    required String title,
    required String content,
    required String type,
    String? emotion,
    String? imageKey,
    String? imageContentType,
    int? imageSize,
    String? audioKey,
    String? audioContentType,
    int? audioSize,
    int? audioDurationSeconds,
    String? videoKey,
    String? videoContentType,
    int? videoSize,
    int? videoDurationSeconds,
  }) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/journals',
          data: {
            'title': title,
            'content': content,
            'type': type,
            if (emotion != null) 'emotion': emotion,
            if (imageKey != null) 'imageKey': imageKey,
            if (imageContentType != null) 'imageContentType': imageContentType,
            if (imageSize != null) 'imageSize': imageSize,
            if (audioKey != null) 'audioKey': audioKey,
            if (audioContentType != null) 'audioContentType': audioContentType,
            if (audioSize != null) 'audioSize': audioSize,
            if (audioDurationSeconds != null)
              'audioDurationSeconds': audioDurationSeconds,
            if (videoKey != null) 'videoKey': videoKey,
            if (videoContentType != null) 'videoContentType': videoContentType,
            if (videoSize != null) 'videoSize': videoSize,
            if (videoDurationSeconds != null)
              'videoDurationSeconds': videoDurationSeconds,
          },
        );
        return _unwrapBody(res.data);
      });

  Future<Map<String, dynamic>> getJournalEntry(String id) => _guard(() async {
        final res =
            await _client.get<Map<String, dynamic>>('/journals/$id');
        return _unwrapBody(res.data);
      });

  Future<void> updateJournalEntry({
    required String id,
    required String title,
    required String content,
    String? emotion,
    String? imageKey,
    String? imageContentType,
    int? imageSize,
    String? audioKey,
    String? audioContentType,
    int? audioSize,
    int? audioDurationSeconds,
    String? videoKey,
    String? videoContentType,
    int? videoSize,
    int? videoDurationSeconds,
    bool removeImage = false,
    bool removeAudio = false,
    bool removeVideo = false,
  }) =>
      _guard(() async {
        await _client.put<Map<String, dynamic>>(
          '/journals/$id',
          data: {
            'title': title,
            'content': content,
            if (emotion != null) 'emotion': emotion,
            if (imageKey != null) 'imageKey': imageKey,
            if (imageContentType != null) 'imageContentType': imageContentType,
            if (imageSize != null) 'imageSize': imageSize,
            if (audioKey != null) 'audioKey': audioKey,
            if (audioContentType != null) 'audioContentType': audioContentType,
            if (audioSize != null) 'audioSize': audioSize,
            if (audioDurationSeconds != null)
              'audioDurationSeconds': audioDurationSeconds,
            if (videoKey != null) 'videoKey': videoKey,
            if (videoContentType != null) 'videoContentType': videoContentType,
            if (videoSize != null) 'videoSize': videoSize,
            if (videoDurationSeconds != null)
              'videoDurationSeconds': videoDurationSeconds,
            if (removeImage) 'removeImage': true,
            if (removeAudio) 'removeAudio': true,
            if (removeVideo) 'removeVideo': true,
          },
        );
      });

  Future<void> deleteJournalEntry(String id) => _guard(() async {
        await _client.delete<Map<String, dynamic>>('/journals/$id');
      });

  /// Retry AI analysis for a journal entry that failed or is stale.
  Future<Map<String, dynamic>> retryJournalAnalysis(String id) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/journals/$id/analysis/retry',
        );
        return _unwrapBody(res.data);
      });

  // ──────────────────────────────────────── AI Coach / Chat

  Future<List<Map<String, dynamic>>> getConversations() => _guard(() async {
        final res =
            await _client.get<Map<String, dynamic>>('/conversations');
        return _unwrapList(res.data);
      });

  Future<Map<String, dynamic>> createConversation({String? title}) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/conversations',
          data: {
            if (title != null) 'title': title,
          },
        );
        return _unwrapBody(res.data);
      });

  Future<Map<String, dynamic>> sendChatMessage({
    required String conversationId,
    required String text,
  }) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/conversations/$conversationId/messages',
          data: {'message': text},
        );
        return _unwrapBody(res.data);
      });

  Future<List<Map<String, dynamic>>> getChatMessages(
          String conversationId,) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/conversations/$conversationId/messages',
        );
        return _unwrapList(res.data);
      });

  Future<Map<String, dynamic>> getConversation(String id) => _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/conversations/$id');
        return _unwrapBody(res.data);
      });

  Future<void> deleteConversation(String id) => _guard(() async {
        await _client.delete<Map<String, dynamic>>('/conversations/$id');
      });

  // ──────────────────────────────────────── Habits

  Future<List<Map<String, dynamic>>> getHabits() => _guard(() async {
        final res =
            await _client.get<Map<String, dynamic>>('/habits');
        return _unwrapList(res.data);
      });

  Future<Map<String, dynamic>> createHabit({
    required String title,
    required int iconCodePoint,
    required int colorValue,
    required String goalLabel,
    String unit = 'session',
  }) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/habits',
          data: {
            'title': title,
            'iconCodePoint': iconCodePoint,
            'colorValue': colorValue,
            'goalLabel': goalLabel,
            'unit': unit,
          },
        );
        return _unwrapBody(res.data);
      });

  Future<Map<String, dynamic>> getHabit(String id) => _guard(() async {
        final res =
            await _client.get<Map<String, dynamic>>('/habits/$id');
        return _unwrapBody(res.data);
      });

  Future<void> updateHabit({
    required String id,
    String? title,
    int? iconCodePoint,
    int? colorValue,
    String? goalLabel,
    String? unit,
  }) =>
      _guard(() async {
        await _client.put<Map<String, dynamic>>(
          '/habits/$id',
          data: {
            if (title != null) 'title': title,
            if (iconCodePoint != null) 'iconCodePoint': iconCodePoint,
            if (colorValue != null) 'colorValue': colorValue,
            if (goalLabel != null) 'goalLabel': goalLabel,
            if (unit != null) 'unit': unit,
          },
        );
      });

  Future<void> deleteHabit(String id) => _guard(() async {
        await _client.delete<Map<String, dynamic>>('/habits/$id');
      });

  Future<void> toggleHabit(String id) => _guard(() async {
        final today = DateTime.now().toIso8601String().substring(0, 10);
        await _client.post<Map<String, dynamic>>(
          '/habits/$id/records',
          data: {'date': today, 'completed': true},
        );
      });

  // ──────────────────────────────────────── Challenges

  Future<List<Map<String, dynamic>>> getAvailableChallenges() =>
      _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/challenges');
        return _unwrapList(res.data);
      });

  Future<List<Map<String, dynamic>>> getActiveChallenges() =>
      _guard(() async {
        final res =
            await _client.get<Map<String, dynamic>>('/challenges/active');
        return _unwrapList(res.data);
      });

  Future<List<Map<String, dynamic>>> getCompletedChallenges() =>
      _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/challenges/completed');
        return _unwrapList(res.data);
      });

  Future<Map<String, dynamic>> getChallenge(String id) => _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/challenges/$id');
        return _unwrapBody(res.data);
      });

  Future<void> startChallenge(String id) => _guard(() async {
        await _client.post<Map<String, dynamic>>('/challenges/$id/start');
      });

  Future<void> updateChallengeProgress(String id) => _guard(() async {
        await _client
            .put<Map<String, dynamic>>('/challenges/user-challenges/$id/progress');
      });

  // ──────────────────────────────────────── Recommendations

  Future<List<Map<String, dynamic>>> getRecommendations() => _guard(() async {
        final res =
            await _client.get<Map<String, dynamic>>('/recommendations');
        return _unwrapList(res.data);
      });

  Future<Map<String, dynamic>> getRecommendation(String id) =>
      _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/recommendations/$id');
        return _unwrapBody(res.data);
      });

  Future<List<Map<String, dynamic>>> getRecommendationsByCategory(
          String category,) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/recommendations',
          query: {'category': category},
        );
        return _unwrapList(res.data);
      });

  Future<void> recordRecommendationFeedback(
          String contentId, String feedbackType, {String? requestId,}) =>
      _guard(() async {
        await _client.post<Map<String, dynamic>>(
          '/recommendations/$contentId/feedback',
          data: {
            'feedbackType': feedbackType,
            if (requestId != null) 'requestId': requestId,
          },
        );
      });

  Future<void> recordRecommendationInteraction(
          String contentId, String interactionType, {String? requestId,}) =>
      _guard(() async {
        await _client.post<Map<String, dynamic>>(
          '/recommendations/$contentId/interaction',
          data: {
            'interactionType': interactionType,
            if (requestId != null) 'requestId': requestId,
          },
        );
      });

  // ──────────────────────────────────────── Future Letters

  Future<List<Map<String, dynamic>>> getFutureLetters() => _guard(() async {
        final res =
            await _client.get<Map<String, dynamic>>('/future-letters');
        return _unwrapList(res.data);
      });

  Future<Map<String, dynamic>> createFutureLetter({
    required String title,
    required String recipient,
    required String scheduledDate,
    required String content,
  }) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/future-letters',
          data: {
            'title': title,
            'recipient': recipient,
            'scheduledDate': scheduledDate,
            'content': content,
          },
        );
        return _unwrapBody(res.data);
      });

  Future<void> updateFutureLetter({
    required String id,
    required String title,
    required String recipient,
    required String scheduledDate,
    required String content,
  }) =>
      _guard(() async {
        await _client.put<Map<String, dynamic>>(
          '/future-letters/$id',
          data: {
            'title': title,
            'recipient': recipient,
            'scheduledDate': scheduledDate,
            'content': content,
          },
        );
      });

  Future<void> deleteFutureLetter(String id) => _guard(() async {
        await _client.delete<Map<String, dynamic>>('/future-letters/$id');
      });

  Future<List<Map<String, dynamic>>> getScheduledLetters() =>
      _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/future-letters/scheduled');
        return _unwrapList(res.data);
      });

  Future<List<Map<String, dynamic>>> getDeliveredLetters() =>
      _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/future-letters/delivered');
        return _unwrapList(res.data);
      });

  Future<void> openFutureLetter(String id) => _guard(() async {
        await _client
            .put<Map<String, dynamic>>('/future-letters/$id/open');
      });

  // ──────────────────────────────────────── Relax Activities

  Future<List<Map<String, dynamic>>> getRelaxActivities() => _guard(() async {
        final res =
            await _client.get<Map<String, dynamic>>('/relax');
        return _unwrapList(res.data);
      });

  Future<Map<String, dynamic>> getRelaxActivity(String id) =>
      _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/relax/$id');
        return _unwrapBody(res.data);
      });

  Future<void> completeRelaxActivity(String id) => _guard(() async {
        await _client
            .post<Map<String, dynamic>>('/relax/$id/complete');
      });

  // ──────────────────────────────────────── Journal (enhanced)

  Future<Map<String, dynamic>> searchJournalEntries({
    String? search,
    String? type,
    int page = 0,
    int size = 20,
  }) => _guard(() async {
    final query = <String, dynamic>{
      'page': page,
      'size': size,
    };
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (type != null) query['type'] = type;
    final res = await _client.get<Map<String, dynamic>>(
      '/journals',
      query: query,
    );
    return _unwrapBody(res.data);
  });

  // ──────────────────────────────────────── Progress

  Future<Map<String, dynamic>> getProgress() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>('/progress');
        return _unwrapBody(res.data);
      });

  // ──────────────────────────────────────── Personalization

  Future<Map<String, dynamic>> getPersonalizedContext() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/personalization/context',
        );
        return _unwrapBody(res.data);
      });

  Future<Map<String, dynamic>> refreshPersonalizedContext() => _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/personalization/context/refresh',
        );
        return _unwrapBody(res.data);
      });

  Future<void> recordPersonalizationFeedback({
    required String eventType,
    String? contentId,
    String? sourceFeature,
    Map<String, String>? metadata,
  }) =>
      _guard(() async {
        await _client.post<Map<String, dynamic>>(
          '/personalization/feedback',
          data: {
            'eventType': eventType,
            if (contentId != null) 'contentId': contentId,
            if (sourceFeature != null) 'sourceFeature': sourceFeature,
            if (metadata != null) 'metadata': metadata,
          },
        );
      });
}
