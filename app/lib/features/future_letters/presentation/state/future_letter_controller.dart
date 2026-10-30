import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mindease/core/api/feature_api.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/future_letters/data/future_letter.dart';

/// Manages future letters: listing, CRUD, scheduled/delivered views.
class FutureLetterController extends ChangeNotifier {
  FutureLetterController(this._api);

  final FeatureApi _api;

  List<FutureLetter> _letters = [];
  List<FutureLetter> _scheduledLetters = [];
  List<FutureLetter> _deliveredLetters = [];
  bool _loading = false;
  bool _disposed = false;
  String? _error;

  List<FutureLetter> get letters => _letters;
  List<FutureLetter> get scheduledLetters => _scheduledLetters;
  List<FutureLetter> get deliveredLetters => _deliveredLetters;
  bool get loading => _loading;
  String? get error => _error;

  void _start() {
    _loading = true;
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

  void _fail(Object e) {
    _error = e is Failure ? e.message : 'Something went wrong.';
    _loading = false;
    notifyListeners();
  }

  /// Fetch all future letters for the current user.
  Future<void> loadLetters() async {
    _start();
    try {
      final rows = await _api.getFutureLetters();
      _letters = rows.map(_fromApi).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Create a new future letter and refresh the list.
  Future<void> createLetter({
    required String title,
    required String recipient,
    required DateTime scheduledDate,
    required String content,
  }) async {
    _start();
    try {
      await _api.createFutureLetter(
        title: title,
        recipient: recipient,
        scheduledDate: scheduledDate.toIso8601String(),
        content: content,
      );
      await loadLetters();
    } catch (e) {
      _fail(e);
    }
  }

  /// Update an existing letter and refresh the list.
  Future<void> updateLetter({
    required String id,
    required String title,
    required String recipient,
    required DateTime scheduledDate,
    required String content,
  }) async {
    _start();
    try {
      await _api.updateFutureLetter(
        id: id,
        title: title,
        recipient: recipient,
        scheduledDate: scheduledDate.toIso8601String(),
        content: content,
      );
      await loadLetters();
    } catch (e) {
      _fail(e);
    }
  }

  /// Delete a letter and refresh the list.
  Future<void> deleteLetter(String id) async {
    _start();
    try {
      await _api.deleteFutureLetter(id);
      await loadLetters();
    } catch (e) {
      _fail(e);
    }
  }

  /// Fetch only scheduled letters.
  Future<void> loadScheduled() async {
    _start();
    try {
      final rows = await _api.getScheduledLetters();
      _scheduledLetters = rows.map(_fromApi).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Fetch only delivered (but unopened) letters.
  Future<void> loadDelivered() async {
    _start();
    try {
      final rows = await _api.getDeliveredLetters();
      _deliveredLetters = rows.map(_fromApi).toList();
      _loading = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  /// Mark a delivered letter as opened and refresh delivered list.
  Future<void> openLetter(String id) async {
    _start();
    try {
      await _api.openFutureLetter(id);
      await loadDelivered();
      await loadLetters();
    } catch (e) {
      _fail(e);
    }
  }
}

// ──────────────────────────────────────────── API → domain mapping

FutureLetter _fromApi(Map<String, dynamic> json) => FutureLetter(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      recipient: json['recipient'] as String? ?? '',
      scheduledDate: _parseDate(json['scheduledDate']),
      content: json['content'] as String? ?? '',
      status: _parseStatus(json['status']),
    );

DateTime _parseDate(dynamic value) {
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

LetterStatus _parseStatus(dynamic value) {
  final raw = (value as String?) ?? 'scheduled';
  return LetterStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => LetterStatus.scheduled,
  );
}
