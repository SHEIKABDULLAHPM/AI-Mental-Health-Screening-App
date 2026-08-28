import 'package:flutter/foundation.dart';

import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/error/failures.dart';

/// Manages the centralized personalized context state.
///
/// Fetches the unified context from the backend and exposes
/// personalized signals to the UI: mood trend, journal activity,
/// emotional themes, and an explainable summary.
class PersonalizationController extends ChangeNotifier {
  PersonalizationController(this._api);

  final FeatureApi _api;

  Map<String, dynamic>? _context;
  bool _loading = false;
  String? _error;

  /// Whether context is currently being loaded.
  bool get loading => _loading;

  /// Last error message, if any.
  String? get error => _error;

  /// The full personalized context map from the backend.
  Map<String, dynamic>? get context => _context;

  // ── Convenience accessors ──────────────────────────────────────

  /// Current mood label (e.g. "happy", "stressed").
  String? get currentMood => _context?['currentMood'] as String?;

  /// Current emotion label.
  String? get currentEmotion => _context?['currentEmotion'] as String?;

  /// Mood trend: "improving", "declining", "stable", "fluctuating", "unknown".
  String? get moodTrend => _context?['moodTrend'] as String?;

  /// Human-readable mood trend description.
  String? get moodTrendDescription =>
      _context?['moodTrendDescription'] as String?;

  /// Dominant mood in the recent window.
  String? get dominantMood => _context?['dominantMood'] as String?;

  /// Number of mood entries in the analysis window.
  int get moodEntryCount =>
      (_context?['moodEntryCount'] as num?)?.toInt() ?? 0;

  /// Hours since the last mood check-in.
  int get hoursSinceLastCheckin =>
      (_context?['hoursSinceLastCheckin'] as num?)?.toInt() ?? 0;

  /// Whether journal data is available.
  bool get journalAvailable =>
      _context?['journalAvailable'] as bool? ?? false;

  /// Number of recent journal entries considered.
  int get recentJournalCount =>
      (_context?['recentJournalCount'] as num?)?.toInt() ?? 0;

  /// Journal writing frequency indicator.
  String? get journalActivityLevel =>
      _context?['journalActivityLevel'] as String?;

  /// Emotional themes derived across all features.
  List<String> get emotionalThemes {
    final raw = _context?['emotionalThemes'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  /// Whether the user has active coach conversations.
  bool get coachActive => _context?['coachActive'] as bool? ?? false;

  /// User's primary wellness focus.
  String? get primaryFocus => _context?['primaryFocus'] as String?;

  /// User's wellness score (0–100).
  int? get wellnessScore =>
      (_context?['wellnessScore'] as num?)?.toInt();

  /// Short explainable reason for the current personalization state.
  String get personalizationSummary =>
      _context?['personalizationSummary'] as String? ??
      'Start tracking your mood to unlock personalized insights.';

  // ── Loading helpers ────────────────────────────────────────────

  void _start() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void _fail(Object e) {
    _error = e is Failure ? e.message : 'Something went wrong.';
    _loading = false;
    notifyListeners();
  }

  // ── Public methods ─────────────────────────────────────────────

  /// Fetch the personalized context (uses cache if fresh).
  Future<void> loadContext() async {
    _start();
    try {
      _context = await _api.getPersonalizedContext();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Force a context refresh (after significant feature events).
  Future<void> refreshContext() async {
    _start();
    try {
      _context = await _api.refreshPersonalizedContext();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Record a cross-feature feedback event.
  Future<void> recordFeedback({
    required String eventType,
    String? contentId,
    String? sourceFeature,
    Map<String, String>? metadata,
  }) async {
    try {
      await _api.recordPersonalizationFeedback(
        eventType: eventType,
        contentId: contentId,
        sourceFeature: sourceFeature,
        metadata: metadata,
      );
    } catch (_) {
      // Feedback failure is non-blocking
    }
  }
}
