import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/challenges/data/challenge.dart';
import 'package:mindease/features/challenges/data/challenge_api.dart';

/// Aggregated view model backing the Challenges home screen, derived entirely
/// from the server `home` envelope (activity-driven, never client-forged).
class ChallengeHomeData {
  const ChallengeHomeData({
    this.active = const [],
    this.completed = const [],
    this.badges = const [],
    this.recommended,
    this.currentStreak = 0,
    this.pointsEarned = 0,
  });

  final List<Challenge> active;
  final List<Challenge> completed;
  final List<ChallengeBadge> badges;
  final Challenge? recommended;
  final int currentStreak;
  final int pointsEarned;
}

/// Manages wellness challenges backed by the server's aggregated home payload.
class ChallengeController extends ChangeNotifier {
  ChallengeController(this._api);

  final ChallengeApi _api;

  ChallengeHomeData _home = const ChallengeHomeData();
  Challenge? _currentChallenge;
  bool _loading = false;
  bool _loaded = false;
  bool _disposed = false;
  String? _error;

  // History
  List<Challenge> _history = [];
  bool _historyLoading = false;
  bool _historyHasMore = true;
  int _historyPage = 0;

  // Active progress
  List<Challenge> _activeProgress = [];

  ChallengeHomeData get home => _home;
  List<Challenge> get active => _home.active;
  List<Challenge> get completed => _home.completed;
  List<ChallengeBadge> get badges => _home.badges;
  Challenge? get recommended => _home.recommended;
  int get currentStreak => _home.currentStreak;
  int get pointsEarned => _home.pointsEarned;
  Challenge? get currentChallenge => _currentChallenge;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  List<Challenge> get history => _history;
  bool get historyLoading => _historyLoading;
  bool get historyHasMore => _historyHasMore;
  List<Challenge> get activeProgress => _activeProgress;

  void _start() {
    _loading = true;
    _error = null;
    // Screens call loaders straight from `initState`; notifying here would
    // mark the provider scope mid-build and trip the framework's
    // "setState() or markNeedsBuild() called during build" assertion.
    // `_loading` is already set for the in-flight build; this only schedules
    // the follow-up rebuild safely.
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

  void _fail(Object e) {
    _error = e is Failure ? e.message : 'Something went wrong.';
    _loading = false;
    notifyListeners();
  }

  /// Load the full aggregated home payload: active, completed, badges,
  /// streak, points and the recommended challenge.
  Future<void> loadHome({bool refresh = false}) async {
    if (!refresh && _loaded) return;
    _start();
    try {
      final json = await _api.getChallengeHome();
      final active = _list(json['active']);
      final completed = _list(json['completed']);
      final badgesRows = json['badges'];
      final recommendedMap = json['recommended'] as Map<String, dynamic>?;

      _home = ChallengeHomeData(
        active: active,
        completed: completed,
        badges: [
          for (final b in (badgesRows is List ? badgesRows : const []))
            if (b is Map<String, dynamic>) ChallengeBadge.fromJson(b),
        ],
        recommended: recommendedMap == null ? null : Challenge.fromJson(recommendedMap),
        currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
        pointsEarned: (json['pointsEarned'] as num?)?.toInt() ?? 0,
      );
      _loaded = true;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Start participating in a challenge, then refresh the home payload.
  Future<void> startChallenge(String id) async {
    _start();
    try {
      final started = await _api.startChallenge(id);
      _currentChallenge = Challenge.fromJson(started);
      // Refresh home data without clobbering _currentChallenge.
      // loadHome() calls _start() internally which resets _loading, so we
      // must restore _currentChallenge and _loading afterwards.
      try {
        final json = await _api.getChallengeHome();
        final active = _list(json['active']);
        final completed = _list(json['completed']);
        final badgesRows = json['badges'];
        final recommendedMap = json['recommended'] as Map<String, dynamic>?;

        _home = ChallengeHomeData(
          active: active,
          completed: completed,
          badges: [
            for (final b in (badgesRows is List ? badgesRows : const []))
              if (b is Map<String, dynamic>) ChallengeBadge.fromJson(b),
          ],
          recommended: recommendedMap == null ? null : Challenge.fromJson(recommendedMap),
          currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
          pointsEarned: (json['pointsEarned'] as num?)?.toInt() ?? 0,
        );
        _loaded = true;
      } catch (_) {
        // Non-critical: home data refresh failed, but the challenge was started.
      }
      // Re-fetch the single challenge to get the latest server state
      // (status, progress, streak) after starting.
      try {
        final detailJson = await _api.getChallenge(id);
        _currentChallenge = Challenge.fromJson(detailJson);
      } catch (_) {
        // Use the start response as fallback — it already has the initial state.
      }
      _loading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load a single challenge (details screen). Server-derived only.
  Future<void> loadDetails(String id) async {
    _start();
    try {
      final json = await _api.getChallenge(id);
      _currentChallenge = Challenge.fromJson(json);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load challenge history, paginated.
  Future<void> loadHistory({bool refresh = false}) async {
    if (refresh) {
      _historyPage = 0;
      _history = [];
      _historyHasMore = true;
    }
    if (!_historyHasMore) return;
    _historyLoading = true;
    notifyListeners();
    try {
      final json = await _api.getChallengeHistory(
        page: _historyPage,
        size: 20,
      );
      final items = _list(json);
      if (refresh) {
        _history = items;
      } else {
        _history = [..._history, ...items];
      }
      _historyHasMore = items.length >= 20;
      _historyPage++;
      _historyLoading = false;
      notifyListeners();
    } catch (e) {
      _historyLoading = false;
      notifyListeners();
    }
  }

  /// Load active challenge progress summary.
  Future<void> loadActiveProgress() async {
    try {
      final json = await _api.getActiveProgress();
      _activeProgress = _list(json);
      notifyListeners();
    } catch (_) {
      // Silent — non-critical
    }
  }

  /// Submit a game result for challenge validation.
  Future<Challenge?> submitGameResult({
    required String challengeId,
    required String gameType,
    required int score,
    required bool completed,
    int moves = 0,
    int durationSeconds = 0,
    String? difficulty,
  }) async {
    _start();
    try {
      final json = await _api.submitGameResult(
        challengeId: challengeId,
        gameType: gameType,
        score: score,
        completed: completed,
        moves: moves,
        durationSeconds: durationSeconds,
        difficulty: difficulty,
      );
      final challenge = Challenge.fromJson(json);
      _currentChallenge = challenge;
      _loading = false;
      notifyListeners();
      return challenge;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  List<Challenge> _list(Object? value) => [
        for (final e in (value is List ? value : const []))
          if (e is Map<String, dynamic>) Challenge.fromJson(e),
      ];
}
