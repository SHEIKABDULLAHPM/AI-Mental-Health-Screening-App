import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/mood_tracking/data/mood_entry.dart';

/// Abstract interface for mood-related API calls.
/// Implemented by [FeatureApi] in production; stubbed in tests.
abstract class MoodApi {
  Future<List<Map<String, dynamic>>> getMoodEntries();
  Future<List<Map<String, dynamic>>> getRecentMoodEntries({int limit = 5});
  Future<Map<String, dynamic>> getMoodEntry(String id);
  Future<List<Map<String, dynamic>>> getMoodTrends({int days = 14});
  Future<Map<String, dynamic>> getEnhancedTrends({int days = 30});
  Future<Map<String, dynamic>> getOnboardingMoodSummary();
  Future<Map<String, dynamic>?> recordMood({
    required String mood,
    String? emotion,
    String? note,
    String? source,
    double? confidence,
    String? aiSuggestedMood,
    List<Map<String, dynamic>>? aiObservations,
    int? intensity,
  });
  Future<void> deleteMood(String id);
  Future<Map<String, dynamic>> analyzeMood({
    required String mood,
    String? emotion,
    String? note,
    Map<String, dynamic>? cameraObservation,
  });
  Future<Map<String, dynamic>> getStatistics();

  /// Persist one on-device facial-expression observation as an immutable
  /// emotion event (structured engine output). Returns the created event.
  Future<Map<String, dynamic>> recordEmotionEvent(Map<String, dynamic> event);
}

/// Manages mood tracking state: entries, today's moods, trends,
/// and multimodal AI analysis.
class MoodController extends ChangeNotifier {
  MoodController(this._api);

  final MoodApi _api;

  List<MoodEntry> _entries = [];
  List<MoodEntry> _todayEntries = [];
  List<MoodEntry> _recentEntries = [];
  List<Map<String, dynamic>> _trends = [];
  Map<String, dynamic>? _enhancedTrends;
  Map<String, dynamic>? _statistics;
  // Reference-counted loading: concurrent loadEntries/loadTrends/
  // loadEnhancedTrends must not clear each other's spinner.
  int _pendingLoads = 0;
  String? _error;

  // ── AI analysis state ──
  Map<String, dynamic>? _analysisResult;
  bool _analyzing = false;
  bool _disposed = false;
  String? _analysisError;

  List<MoodEntry> get entries => _entries;
  List<MoodEntry> get todayEntries => _todayEntries;
  List<MoodEntry> get recentEntries => _recentEntries;
  List<Map<String, dynamic>> get trends => _trends;
  Map<String, dynamic>? get enhancedTrends => _enhancedTrends;
  Map<String, dynamic>? get statistics => _statistics;
  bool get loading => _pendingLoads > 0;
  String? get error => _error;

  Map<String, dynamic>? get analysisResult => _analysisResult;
  bool get analyzing => _analyzing;
  String? get analysisError => _analysisError;

  // ──────────────────────────────────────────── Loading helpers

  void _start() {
    _pendingLoads++;
    _error = null;
    _deferNotify();
  }

  /// Listeners must not be notified synchronously from a loader a screen
  /// calls out of `initState`: the provider scope sits above the router, and
  /// marking it while the framework is still building that screen trips its
  /// "setState() or markNeedsBuild() called during build" assertion. State is
  /// already assigned synchronously, so the in-flight build reads the right
  /// values; this only schedules the follow-up rebuild safely.
  void _deferNotify() {
    if (_disposed) return;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _finish() {
    if (_pendingLoads > 0) _pendingLoads--;
    notifyListeners();
  }

  void _fail(Object e) {
    _error = _message(e);
    if (_pendingLoads > 0) _pendingLoads--;
    notifyListeners();
  }

  String _message(Object e) =>
      e is Failure ? e.message : 'Something went wrong.';

  // ──────────────────────────────────────────── Public methods

  /// Fetch all mood entries for the current user.
  Future<void> loadEntries() async {
    _start();
    try {
      final rows = await _api.getMoodEntries();
      _entries = rows.map(_fromApi).toList();
      _filterToday();
      _finish();
    } catch (e) {
      _fail(e);
    }
  }

  /// Fetch recent mood entries for the home screen "Recent moods" section.
  Future<void> loadRecentEntries({int limit = 5}) async {
    try {
      final rows = await _api.getRecentMoodEntries(limit: limit);
      _recentEntries = rows.map(_fromApi).toList();
      notifyListeners();
    } catch (_) {
      // Non-critical: home screen can fall back to filtering `entries`.
    }
  }

  /// Fetch aggregated mood statistics (streaks, averages, distributions).
  Future<void> loadStatistics() async {
    try {
      _statistics = await _api.getStatistics();
      notifyListeners();
    } catch (_) {
      // Non-critical: home screen can show without stats.
    }
  }

  /// Fetch a single mood entry by ID from the API.
  Future<MoodEntry?> loadEntry(String id) async {
    try {
      final json = await _api.getMoodEntry(id);
      return _fromApi(json);
    } catch (e) {
      // Fallback: search local entries
      return _entries.where((e) => e.id == id).firstOrNull;
    }
  }

  void _filterToday() {
    final now = DateTime.now();
    _todayEntries = _entries.where((e) =>
        e.date.year == now.year &&
        e.date.month == now.month &&
        e.date.day == now.day,
    ).toList();
  }

  /// Analyze mood via AI service (text emotion + camera fusion).
  /// Returns the analysis result for the UI to display before confirmation.
  Future<Map<String, dynamic>?> analyzeMood({
    required String mood,
    String? emotion,
    String? note,
    Map<String, dynamic>? cameraObservation,
  }) async {
    _analyzing = true;
    _analysisError = null;
    _analysisResult = null;
    notifyListeners();

    try {
      final result = await _api.analyzeMood(
        mood: mood,
        emotion: emotion,
        note: note,
        cameraObservation: cameraObservation,
      );
      _analysisResult = result;
      _analyzing = false;
      notifyListeners();
      return result;
    } catch (e) {
      _analysisError = _message(e);
      _analyzing = false;
      notifyListeners();
      // Return null on failure — caller can fall back to manual
      return null;
    }
  }

  /// Record a new mood (optionally with AI observations) and reload entries.
  /// [aiObservations] should be a list of maps matching the backend
  /// AiObservationInput schema (source, emotion, confidence, sentiment, etc.).
  /// Returns the created entry id, or null when the server did not return one
  /// (callers needing a link should treat null as "unlinked but recorded").
  Future<String?> recordMood({
    required String moodId,
    String? emotion,
    String? note,
    String? source,
    double? confidence,
    String? aiSuggestedMood,
    List<Map<String, dynamic>>? aiObservations,
    int? intensity,
  }) async {
    _start();
    String? createdId;
    try {
      final created = await _api.recordMood(
        mood: moodId,
        emotion: emotion,
        note: note,
        source: source,
        confidence: confidence,
        aiSuggestedMood: aiSuggestedMood,
        aiObservations: aiObservations,
        intensity: intensity,
      );
      createdId = created?['id'] as String?;
      _analysisResult = null;
    } catch (e) {
      _fail(e);
      return null;
    }
    // Own write succeeded — release our slot before the refresh, which
    // manages its own loading/error state via loadEntries().
    if (_pendingLoads > 0) _pendingLoads--;
    await loadEntries();
    return createdId;
  }

  /// Persist a confirmed camera observation as an emotion event.
  ///
  /// Best-effort telemetry: returns the event id on success, null on
  /// failure (logged). Never throws into the save flow — the mood record
  /// itself must not fail because event ingestion did.
  Future<String?> recordEmotionEvent(Map<String, dynamic> event) async {
    try {
      final created = await _api.recordEmotionEvent(event);
      return created['id'] as String?;
    } catch (e) {
      debugPrint('recordEmotionEvent failed: $e');
      return null;
    }
  }

  /// Load aggregated trend data for the mood chart.
  Future<void> loadTrends({int days = 14}) async {
    _start();
    try {
      _trends = await _api.getMoodTrends(days: days);
      _finish();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load enhanced trends with emotion distribution and daily data.
  Future<void> loadEnhancedTrends({int days = 30}) async {
    _start();
    try {
      _enhancedTrends = await _api.getEnhancedTrends(days: days);
      final moodTrends = _enhancedTrends?['moodTrends'];
      _trends = (moodTrends is List)
          ? moodTrends.cast<Map<String, dynamic>>()
          : [];
      _finish();
    } catch (e) {
      _fail(e);
    }
  }

  /// Delete a mood entry by id and refresh the list.
  Future<void> deleteMood(String id) async {
    _start();
    try {
      await _api.deleteMood(id);
    } catch (e) {
      _fail(e);
      return;
    }
    if (_pendingLoads > 0) _pendingLoads--;
    await loadEntries();
  }

  /// Clear the current analysis result (e.g. when user cancels).
  void clearAnalysis() {
    _analysisResult = null;
    _analysisError = null;
    notifyListeners();
  }
}

// ──────────────────────────────────────────── API → domain mapping

MoodEntry _fromApi(Map<String, dynamic> json) {
  final observations = (json['aiObservations'] as List?)
          ?.map((obs) => AiObservation.fromJson(obs as Map<String, dynamic>))
          .toList() ??
      [];

  return MoodEntry(
    id: json['id'] as String? ?? '',
    date: _parseDate(json['recordedAt']),
    moodId: json['mood'] as String? ?? '',
    emotion: json['emotion'] as String?,
    note: json['note'] as String?,
    source: json['source'] as String?,
    confidence: (json['confidence'] as num?)?.toDouble(),
    analysisStatus: json['analysisStatus'] as String?,
    aiObservations: observations,
    aiSuggestedMood: json['aiSuggestedMood'] as String?,
    intensity: (json['intensity'] as num?)?.toInt(),
  );
}

DateTime _parseDate(dynamic value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    // Backend stores UTC instants; convert to local so day grouping and
    // Today filters match the user's calendar near midnight.
    if (parsed != null) return parsed.isUtc ? parsed.toLocal() : parsed;
    return DateTime.now();
  }
  return DateTime.now();
}
