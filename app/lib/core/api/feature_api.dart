import 'package:dio/dio.dart';

import 'package:mindease/core/error/error_mapper.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/network/dio_client.dart';
import 'package:mindease/features/challenges/data/challenge_api.dart';
import 'package:mindease/features/mood_tracking/presentation/state/mood_controller.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_api.dart';

/// Thin client for every feature endpoint the controllers call.
///
/// Follows the same envelope convention as [MindeaseApi]: every response is
/// `{success, data}` and the inner `data` is unwrapped here.
class FeatureApi
    implements MoodApi, ChallengeApi, PhysicalWellnessApi {
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
  Future<Map<String, dynamic>?> recordMood({
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
        final res = await _client.post<Map<String, dynamic>>(
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
        final payload = res.data?['data'];
        if (payload is! Map<String, dynamic>) return null;
        return payload;
      });

  /// Persist a confirmed on-device emotion observation.
  /// POST /emotions/events — the backend validates, dedupes by idempotency
  /// key and stores the immutable event.
  @override
  Future<Map<String, dynamic>> recordEmotionEvent(
    Map<String, dynamic> event,
  ) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/emotions/events',
          data: event,
        );
        return _unwrapBody(res.data);
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

  /// Combined onboarding mood context (recent + trend + statistics) in one
  /// round-trip, so onboarding prefill needs a single HTTP call.
  @override
  Future<Map<String, dynamic>> getOnboardingMoodSummary() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/moods/onboarding-summary',
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

  /// Aggregated payload for the Challenges home screen.
  ///
  /// Returns the raw home envelope map so the consumer can read `active`,
  /// `completed`, `badges`, `currentStreak`, `pointsEarned` and `recommended`.
  @override
  Future<Map<String, dynamic>> getChallengeHome() => _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/challenges/home');
        return _unwrapBody(res.data);
      });

  @override
  Future<List<Map<String, dynamic>>> getAvailableChallenges() =>
      _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/challenges');
        return _unwrapList(res.data);
      });

  @override
  Future<Map<String, dynamic>> getChallenge(String id) => _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/challenges/$id');
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> startChallenge(String id) => _guard(() async {
        final res = await _client
            .post<Map<String, dynamic>>('/challenges/$id/start');
        return _unwrapBody(res.data);
      });

  @override
  Future<List<Map<String, dynamic>>> getBadges() => _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/challenges/badges');
        return _unwrapList(res.data);
      });

  @override
  Future<List<Map<String, dynamic>>> getChallengeHistory({
    int page = 0,
    int size = 20,
  }) => _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>(
              '/challenges/history',
              query: {'page': page, 'size': size},
            );
        return _unwrapList(res.data);
      });

  @override
  Future<List<Map<String, dynamic>>> getActiveProgress() =>
      _guard(() async {
        final res = await _client
            .get<Map<String, dynamic>>('/challenges/progress');
        return _unwrapList(res.data);
      });

  @override
  Future<Map<String, dynamic>> submitGameResult({
    required String challengeId,
    required String gameType,
    required int score,
    required bool completed,
    int moves = 0,
    int durationSeconds = 0,
    String? difficulty,
  }) => _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/challenges/$challengeId/complete',
          data: {
            'gameType': gameType,
            'score': score,
            'completed': completed,
            'moves': moves,
            'durationSeconds': durationSeconds,
            if (difficulty != null) 'difficulty': difficulty,
          },
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> submitProgress({
    required String challengeId,
    required String sourceRecordId,
  }) => _guard(() async {
        final res = await _client.dio.post<Map<String, dynamic>>(
          '/challenges/$challengeId/progress',
          queryParameters: {'sourceRecordId': sourceRecordId},
        );
        return _unwrapBody(res.data);
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

  // ──────────────────────────────────────── Physical Wellness

  @override
  Future<Map<String, dynamic>> registerDevice({
    required String provider,
    required String deviceIdentifier,
    String? manufacturer,
    String? model,
    String? firmwareVersion,
    List<String>? capabilities,
    int? batteryLevel,
  }) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/wearables',
          data: {
            'provider': provider,
            'deviceIdentifier': deviceIdentifier,
            if (manufacturer != null) 'manufacturer': manufacturer,
            if (model != null) 'model': model,
            if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
            if (capabilities != null) 'capabilities': capabilities,
            if (batteryLevel != null) 'batteryLevel': batteryLevel,
          },
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<List<Map<String, dynamic>>> listDevices() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>('/wearables');
        return _unwrapList(res.data);
      });

  @override
  Future<Map<String, dynamic>> updateDeviceStatus(
    String deviceId, {
    int? batteryLevel,
    bool? charging,
    String? connectionStatus,
    String? firmwareVersion,
  }) =>
      _guard(() async {
        final res = await _client.put<Map<String, dynamic>>(
          '/wearables/$deviceId/status',
          data: {
            if (batteryLevel != null) 'batteryLevel': batteryLevel,
            if (charging != null) 'charging': charging,
            if (connectionStatus != null)
              'connectionStatus': connectionStatus,
            if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
          },
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<void> deleteDevice(String deviceId) => _guard(() async {
        await _client.delete<Map<String, dynamic>>('/wearables/$deviceId');
      });

  @override
  Future<Map<String, dynamic>> getPhysicalToday() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>('/physical/today');
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> getPhysicalActivity({int? days}) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/activity',
          query: {if (days != null) 'days': days},
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> getPhysicalHeartRate({int? hours}) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/heart-rate',
          query: {if (hours != null) 'hours': hours},
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> getPhysicalSleep({int? limit}) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/sleep',
          query: {if (limit != null) 'limit': limit},
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> getPhysicalExercise({int? limit}) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/exercise',
          query: {if (limit != null) 'limit': limit},
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> getPhysicalSummary() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/summary',
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> syncPhysical(Map<String, dynamic> payload) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/physical/sync',
          data: payload,
        );
        return _unwrapBody(res.data);
      });

  // ──────────────────────────────────────── Hydration

  @override
  Future<Map<String, dynamic>> getHydration({int? days}) => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/hydration',
          query: {if (days != null) 'days': days},
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> addHydration({
    required double amount,
    String? unit,
    DateTime? timestamp,
  }) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/physical/hydration',
          data: {
            'amount': amount,
            if (unit != null) 'unit': unit,
            if (timestamp != null)
              'timestamp': timestamp.toUtc().toIso8601String(),
          },
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> updateHydration(
    String entryId, {
    required double amount,
    String? unit,
    DateTime? timestamp,
  }) =>
      _guard(() async {
        final res = await _client.put<Map<String, dynamic>>(
          '/physical/hydration/$entryId',
          data: {
            'amount': amount,
            if (unit != null) 'unit': unit,
            if (timestamp != null)
              'timestamp': timestamp.toUtc().toIso8601String(),
          },
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<void> deleteHydration(String entryId) => _guard(() async {
        await _client.delete<Map<String, dynamic>>(
          '/physical/hydration/$entryId',
        );
      });

  @override
  Future<Map<String, dynamic>> updateHydrationTarget(int targetMl) =>
      _guard(() async {
        final res = await _client.put<Map<String, dynamic>>(
          '/physical/hydration/target',
          data: {'targetMl': targetMl},
        );
        return _unwrapBody(res.data);
      });

  // ──────────────────────────────────────── Body measurements

  @override
  Future<Map<String, dynamic>> getBody({int? limit}) => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/body',
          query: {if (limit != null) 'limit': limit},
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> addBodyMeasurement({
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    DateTime? measuredAt,
  }) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/physical/body',
          data: {
            if (weight != null) 'weight': weight,
            if (height != null) 'height': height,
            if (weightUnit != null) 'weightUnit': weightUnit,
            if (heightUnit != null) 'heightUnit': heightUnit,
            if (measuredAt != null)
              'measuredAt': measuredAt.toUtc().toIso8601String(),
          },
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> updateBodyMeasurement(
    String measurementId, {
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    DateTime? measuredAt,
  }) =>
      _guard(() async {
        final res = await _client.put<Map<String, dynamic>>(
          '/physical/body/$measurementId',
          data: {
            if (weight != null) 'weight': weight,
            if (height != null) 'height': height,
            if (weightUnit != null) 'weightUnit': weightUnit,
            if (heightUnit != null) 'heightUnit': heightUnit,
            if (measuredAt != null)
              'measuredAt': measuredAt.toUtc().toIso8601String(),
          },
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<void> deleteBodyMeasurement(String measurementId) => _guard(() async {
        await _client.delete<Map<String, dynamic>>(
          '/physical/body/$measurementId',
        );
      });

  // ──────────────────────────────────────── Goals, trends, insights

  @override
  Future<Map<String, dynamic>> getGoals() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/goals',
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> updateGoals(Map<String, dynamic> targets) =>
      _guard(() async {
        final res = await _client.put<Map<String, dynamic>>(
          '/physical/goals',
          data: targets,
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> applyAiGoalRecommendations(
          List<Map<String, dynamic>> recommendations) =>
      _guard(() async {
        final res = await _client.post<Map<String, dynamic>>(
          '/physical/goals/ai-recommendations',
          data: {'recommendations': recommendations},
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> getTrends({int? days}) => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/trends',
          query: {if (days != null) 'days': days},
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> getInsights() => _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/physical/insights',
        );
        return _unwrapBody(res.data);
      });

  // ──────────────────────────────────────── Capability registry

  @override
  Future<Map<String, dynamic>> getCapabilities(String deviceId) =>
      _guard(() async {
        final res = await _client.get<Map<String, dynamic>>(
          '/wearables/$deviceId/capabilities',
        );
        return _unwrapBody(res.data);
      });

  @override
  Future<Map<String, dynamic>> reportCapabilities(
    String deviceId,
    List<Map<String, dynamic>> capabilities,
  ) =>
      _guard(() async {
        final res = await _client.put<Map<String, dynamic>>(
          '/wearables/$deviceId/capabilities',
          data: {'capabilities': capabilities},
        );
        return _unwrapBody(res.data);
      });
}
