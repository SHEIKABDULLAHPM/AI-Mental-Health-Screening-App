import 'package:flutter/foundation.dart';

import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/challenges/data/challenge.dart';

/// Manages wellness challenges: available, active and completed lists.
class ChallengeController extends ChangeNotifier {
  ChallengeController(this._api);

  final FeatureApi _api;

  List<Challenge> _available = [];
  List<Challenge> _active = [];
  List<Challenge> _completed = [];
  Challenge? _currentChallenge;
  bool _loading = false;
  String? _error;

  List<Challenge> get available => _available;
  List<Challenge> get active => _active;
  List<Challenge> get completed => _completed;
  Challenge? get currentChallenge => _currentChallenge;
  bool get loading => _loading;
  String? get error => _error;

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

  /// Fetch challenges the user has not yet started.
  Future<void> loadAvailable() async {
    _start();
    try {
      final rows = await _api.getAvailableChallenges();
      _available = rows.map(_fromApi).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Fetch challenges the user is currently participating in.
  Future<void> loadActive() async {
    _start();
    try {
      final rows = await _api.getActiveChallenges();
      _active = rows.map(_fromApi).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Fetch challenges the user has completed.
  Future<void> loadCompleted() async {
    _start();
    try {
      final rows = await _api.getCompletedChallenges();
      _completed = rows.map(_fromApi).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Start participating in a challenge and move it to active.
  Future<void> startChallenge(String id) async {
    _start();
    try {
      await _api.startChallenge(id);
      await loadAvailable();
      await loadActive();
    } catch (e) {
      _fail(e);
    }
  }

  /// Record a day of progress on an active challenge.
  Future<void> updateProgress(String id) async {
    _start();
    try {
      await _api.updateChallengeProgress(id);
      await loadActive();
      await loadCompleted();
    } catch (e) {
      _fail(e);
    }
  }

  /// Load a single challenge into [currentChallenge].
  Future<void> loadDetails(String id) async {
    _start();
    try {
      final json = await _api.getChallenge(id);
      _currentChallenge = _fromApi(json);
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }
}

// ──────────────────────────────────────────── API → domain mapping

Challenge _fromApi(Map<String, dynamic> json) => Challenge(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      durationDays: (json['durationDays'] as num?)?.toInt() ?? 0,
      points: (json['points'] as num?)?.toInt() ?? 0,
      isCompleted: json['isCompleted'] as bool? ?? false,
      currentDay: (json['currentDay'] as num?)?.toInt() ?? 0,
    );
