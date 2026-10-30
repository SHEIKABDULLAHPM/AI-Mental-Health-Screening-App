import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mindease/core/error/error_mapper.dart';
import 'package:mindease/core/error/failures.dart';
import 'package:mindease/core/api/models.dart' show GoalTargetSuggestion;
import 'package:mindease/features/physical_wellness/data/lifestyle_models.dart';
import 'package:mindease/features/physical_wellness/data/physical_local_cache.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_api.dart';

/// Drives the lifestyle half of the Physical Wellness hub: hydration, body
/// weight/BMI, goals, trends, Mind–Body insights and the capability registry.
///
/// Reads are cache-first: cached data paints immediately and a network failure
/// merely marks the section stale. Writes are *never* optimistically reported
/// as saved — a write either completes on the server, or it is queued as a
/// [PendingMutation] and surfaced as "waiting to sync".
class LifestyleWellnessController extends ChangeNotifier {
  LifestyleWellnessController(this._api, {required PhysicalLocalCache cache})
      : _cache = cache;

  final PhysicalWellnessApi _api;
  final PhysicalLocalCache _cache;

  HydrationOverview? _hydration;
  BodySummary? _body;
  GoalsOverview? _goals;
  TrendsOverview? _trends;
  InsightsOverview? _insights;
  CapabilityList? _capabilities;

  bool _loading = false;
  bool _saving = false;
  bool _offline = false;
  bool _disposed = false;
  String? _error;
  String? _notice;
  String? _lastSyncError;
  final Set<String> _stale = {};
  List<PendingMutation> _pending = const [];

  HydrationOverview? get hydration => _hydration;
  BodySummary? get body => _body;
  GoalsOverview? get goals => _goals;
  TrendsOverview? get trends => _trends;
  InsightsOverview? get insights => _insights;
  CapabilityList? get capabilities => _capabilities;

  bool get loading => _loading;
  bool get saving => _saving;

  /// True when at least one section kept cached data because the refresh
  /// failed. The UI must label the affected sections rather than hide them.
  bool get offline => _offline;
  String? get error => _error;
  String? get notice => _notice;

  /// A queued write was rejected on replay; kept separate from [notice] so it
  /// is not confusable with a transient offline message.
  String? get lastSyncError => _lastSyncError;

  /// Section keys whose last refresh failed (`hydration`, `body`, `goals`,
  /// `trends`, `insights`, `capabilities`).
  Set<String> get staleSections => Set.unmodifiable(_stale);

  List<PendingMutation> get pendingMutations => List.unmodifiable(_pending);
  int get pendingCount => _pending.length;

  bool get hasAnyData =>
      _hydration != null ||
      _body != null ||
      _goals != null ||
      _trends != null ||
      _insights != null;

  // ── Loading ────────────────────────────────────────────────────────────

  /// Paints cached views, then refreshes everything that can be refreshed.
  Future<void> init({String? deviceId}) async {
    final cached = await Future.wait([
      _cache.readHydration(),
      _cache.readBody(),
      _cache.readGoals(),
      _cache.readTrends(),
      _cache.readInsights(),
      _cache.readCapabilities(),
    ]);
    _hydration = cached[0] as HydrationOverview?;
    _body = cached[1] as BodySummary?;
    _goals = cached[2] as GoalsOverview?;
    _trends = cached[3] as TrendsOverview?;
    _insights = cached[4] as InsightsOverview?;
    _capabilities = cached[5] as CapabilityList?;
    _pending = await _cache.readMutations();
    _deferNotify();
    await flushMutations();
    await refreshAll(deviceId: deviceId);
  }

  /// Foreground recovery: retry queued writes, then refresh the views.
  Future<void> onForeground({String? deviceId}) async {
    await flushMutations();
    await refreshAll(deviceId: deviceId);
  }

  Future<void> refreshAll({String? deviceId}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    await Future.wait([
      loadHydration(),
      loadBody(),
      loadGoals(),
      loadTrends(),
      loadInsights(),
      if (deviceId != null && deviceId.isNotEmpty) loadCapabilities(deviceId),
    ]);
    _loading = false;
    _offline = _stale.isNotEmpty;
    if (_hydration == null &&
        _body == null &&
        _goals == null &&
        _trends == null &&
        _insights == null &&
        _error == null) {
      _error = 'Could not load your wellness data.';
    }
    _notify();
  }

  Future<void> loadHydration() async {
    final cached = _hydration ?? await _cache.readHydration();
    if (cached != null && _hydration == null) {
      _hydration = cached;
      _deferNotify();
    }
    try {
      final value = HydrationOverview.fromJson(await _api.getHydration());
      _hydration = value;
      _stale.remove('hydration');
      await _cache.writeHydration(value);
    } on Object catch (e) {
      _markFailure('hydration', e);
    }
    _notify();
  }

  Future<void> loadBody() async {
    final cached = _body ?? await _cache.readBody();
    if (cached != null && _body == null) {
      _body = cached;
      _deferNotify();
    }
    try {
      final value = BodySummary.fromJson(await _api.getBody());
      _body = value;
      _stale.remove('body');
      await _cache.writeBody(value);
    } on Object catch (e) {
      _markFailure('body', e);
    }
    _notify();
  }

  Future<void> loadGoals() async {
    final cached = _goals ?? await _cache.readGoals();
    if (cached != null && _goals == null) {
      _goals = cached;
      _deferNotify();
    }
    try {
      final value = GoalsOverview.fromJson(await _api.getGoals());
      _goals = value;
      _stale.remove('goals');
      await _cache.writeGoals(value);
    } on Object catch (e) {
      _markFailure('goals', e);
    }
    _notify();
  }

  Future<void> loadTrends() async {
    final cached = _trends ?? await _cache.readTrends();
    if (cached != null && _trends == null) {
      _trends = cached;
      _deferNotify();
    }
    try {
      final value = TrendsOverview.fromJson(await _api.getTrends());
      _trends = value;
      _stale.remove('trends');
      await _cache.writeTrends(value);
    } on Object catch (e) {
      _markFailure('trends', e);
    }
    _notify();
  }

  Future<void> loadInsights() async {
    final cached = _insights ?? await _cache.readInsights();
    if (cached != null && _insights == null) {
      _insights = cached;
      _deferNotify();
    }
    try {
      final value = InsightsOverview.fromJson(await _api.getInsights());
      _insights = value;
      _stale.remove('insights');
      await _cache.writeInsights(value);
    } on Object catch (e) {
      _markFailure('insights', e);
    }
    _notify();
  }

  Future<void> loadCapabilities(String deviceId) async {
    if (deviceId.isEmpty) return;
    final cached = _capabilities ?? await _cache.readCapabilities();
    if (cached != null && _capabilities == null && cached.deviceId == deviceId) {
      _capabilities = cached;
      _deferNotify();
    }
    try {
      final value = CapabilityList.fromJson(await _api.getCapabilities(deviceId));
      _capabilities = value;
      _stale.remove('capabilities');
      await _cache.writeCapabilities(value);
    } on Object catch (e) {
      _markFailure('capabilities', e);
    }
    _notify();
  }

  // ── Hydration writes ───────────────────────────────────────────────────

  /// Logs a drink. Returns true only when the server confirmed it.
  Future<bool> addHydration(double amount, {String? unit}) async {
    if (_saving) return false;
    _saving = true;
    _notice = null;
    _lastSyncError = null;
    notifyListeners();
    final timestamp = DateTime.now();
    try {
      await _api.addHydration(
        amount: amount,
        unit: unit,
        timestamp: timestamp,
      );
      _notice = 'Logged ${amount.round()} ${unit ?? 'ml'}.';
      await Future.wait([loadHydration(), loadGoals(), loadTrends()]);
      return true;
    } on Object catch (e) {
      return _queueOrFail(
        e,
        PendingMutationType.hydrationAdd,
        {
          'amount': amount,
          if (unit != null) 'unit': unit,
          'timestamp': timestamp.toUtc().toIso8601String(),
        },
        queuedMessage: 'Your drink is waiting to sync. '
            'It will be logged when you are back online.',
      );
    } finally {
      _saving = false;
      _notify();
    }
  }

  Future<bool> updateHydration(
    String entryId, {
    required double amount,
    String? unit,
    DateTime? timestamp,
  }) async {
    if (_saving) return false;
    _saving = true;
    _notice = null;
    notifyListeners();
    try {
      await _api.updateHydration(
        entryId,
        amount: amount,
        unit: unit,
        timestamp: timestamp,
      );
      _notice = 'Hydration entry updated.';
      await Future.wait([loadHydration(), loadGoals(), loadTrends()]);
      return true;
    } on Object catch (e) {
      return _queueOrFail(
        e,
        PendingMutationType.hydrationUpdate,
        {
          'id': entryId,
          'amount': amount,
          if (unit != null) 'unit': unit,
          if (timestamp != null)
            'timestamp': timestamp.toUtc().toIso8601String(),
        },
        queuedMessage: 'Your edit is waiting to sync.',
      );
    } finally {
      _saving = false;
      _notify();
    }
  }

  Future<bool> deleteHydration(String entryId) async {
    if (_saving) return false;
    _saving = true;
    _notice = null;
    notifyListeners();
    try {
      await _api.deleteHydration(entryId);
      _notice = 'Hydration entry removed.';
      await Future.wait([loadHydration(), loadGoals(), loadTrends()]);
      return true;
    } on Object catch (e) {
      if (_isAlreadyGone(e)) {
        // Deletion is idempotent: an entry that no longer exists is deleted.
        _notice = 'Hydration entry removed.';
        await loadHydration();
        return true;
      }
      return _queueOrFail(
        e,
        PendingMutationType.hydrationDelete,
        {'id': entryId},
        queuedMessage: 'Your deletion is waiting to sync.',
      );
    } finally {
      _saving = false;
      _notify();
    }
  }

  Future<bool> setHydrationTarget(int targetMl) async {
    if (_saving) return false;
    _saving = true;
    _notice = null;
    notifyListeners();
    try {
      final value = HydrationOverview.fromJson(
        await _api.updateHydrationTarget(targetMl),
      );
      _hydration = value;
      await _cache.writeHydration(value);
      _notice = 'Daily hydration target updated.';
      await loadGoals();
      return true;
    } on Object catch (e) {
      return _queueOrFail(
        e,
        PendingMutationType.hydrationTarget,
        {'targetMl': targetMl},
        queuedMessage: 'Your new target is waiting to sync.',
      );
    } finally {
      _saving = false;
      _notify();
    }
  }

  // ── Body writes ────────────────────────────────────────────────────────

  Future<bool> addBodyMeasurement({
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
  }) async {
    if (_saving) return false;
    _saving = true;
    _notice = null;
    _lastSyncError = null;
    notifyListeners();
    final measuredAt = DateTime.now();
    try {
      await _api.addBodyMeasurement(
        weight: weight,
        height: height,
        weightUnit: weightUnit,
        heightUnit: heightUnit,
        measuredAt: measuredAt,
      );
      _notice = 'Measurement saved.';
      await Future.wait([loadBody(), loadGoals(), loadTrends()]);
      return true;
    } on Object catch (e) {
      return _queueOrFail(
        e,
        PendingMutationType.bodyAdd,
        {
          if (weight != null) 'weight': weight,
          if (height != null) 'height': height,
          if (weightUnit != null) 'weightUnit': weightUnit,
          if (heightUnit != null) 'heightUnit': heightUnit,
          'measuredAt': measuredAt.toUtc().toIso8601String(),
        },
        queuedMessage: 'Your measurement is waiting to sync.',
      );
    } finally {
      _saving = false;
      _notify();
    }
  }

  Future<bool> deleteBodyMeasurement(String measurementId) async {
    if (_saving) return false;
    _saving = true;
    _notice = null;
    notifyListeners();
    try {
      await _api.deleteBodyMeasurement(measurementId);
      _notice = 'Measurement removed.';
      await Future.wait([loadBody(), loadGoals()]);
      return true;
    } on Object catch (e) {
      if (_isAlreadyGone(e)) {
        _notice = 'Measurement removed.';
        await loadBody();
        return true;
      }
      _notice = 'Could not remove that measurement. ${_message(e)}';
      return false;
    } finally {
      _saving = false;
      _notify();
    }
  }

  // ── Goals ──────────────────────────────────────────────────────────────

  Future<bool> saveGoals(GoalTargets targets) async {
    if (_saving) return false;
    _saving = true;
    _notice = null;
    _lastSyncError = null;
    notifyListeners();
    final payload = {
      'dailySteps': targets.dailySteps,
      'dailyActiveMinutes': targets.dailyActiveMinutes,
      'weeklyWorkoutMinutes': targets.weeklyWorkoutMinutes,
      'dailySleepMinutes': targets.dailySleepMinutes,
      'dailyHydrationMl': targets.dailyHydrationMl,
    };
    try {
      final value = GoalsOverview.fromJson(await _api.updateGoals(payload));
      _goals = value;
      await _cache.writeGoals(value);
      _notice = 'Goals updated.';
      await Future.wait([loadGoals(), loadTrends(), loadHydration()]);
      return true;
    } on Object catch (e) {
      return _queueOrFail(
        e,
        PendingMutationType.goalsUpdate,
        payload,
        queuedMessage: 'Your goal changes are waiting to sync.',
      );
    } finally {
      _saving = false;
      _notify();
    }
  }

  /// Applies AI-suggested targets and refreshes goals/trends so progress uses
  /// the persisted values. User-owned targets are preserved by the backend and
  /// reported in [AiGoalApplyResult.skipped].
  Future<AiGoalApplyResult?> applyAiGoalRecommendations(
      List<GoalTargetSuggestion> suggestions) async {
    if (_saving || suggestions.isEmpty) return null;
    _saving = true;
    _notice = null;
    _lastSyncError = null;
    notifyListeners();
    final payload = [
      for (final s in suggestions)
        {'metric': s.metric, 'value': s.value, 'rationale': s.rationale},
    ];
    try {
      final raw = await _api.applyAiGoalRecommendations(payload);
      final goalsRaw = raw['goals'];
      if (goalsRaw is Map<String, dynamic>) {
        final value = GoalsOverview.fromJson(goalsRaw);
        _goals = value;
        await _cache.writeGoals(value);
      }
      final applied = (raw['applied'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      final skipped = (raw['skipped'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      _notice = applied.isEmpty
          ? 'No AI targets were applied.'
          : 'Applied ${applied.length} AI target(s).';
      await Future.wait([loadGoals(), loadTrends(), loadHydration()]);
      return AiGoalApplyResult(applied: applied, skipped: skipped);
    } on Object catch (e) {
      _notice = _message(e);
      return null;
    } finally {
      _saving = false;
      _notify();
    }
  }

  // ── Pending mutations ──────────────────────────────────────────────────

  /// Replays queued writes oldest-first. Stops on the first retryable failure
  /// (connection/server) so ordering is preserved; drops writes the server
  /// rejected outright so they cannot block the queue forever.
  Future<void> flushMutations() async {
    _pending = await _cache.readMutations();
    if (_pending.isEmpty) return;
    _notify();
    var applied = false;
    for (final mutation in List<PendingMutation>.from(_pending)) {
      try {
        await _apply(mutation);
        await _cache.removeMutation(mutation.id);
        _pending = await _cache.readMutations();
        applied = true;
      } on Object catch (e) {
        if (_isRetryable(e)) {
          break;
        }
        _lastSyncError =
            'A queued change could not be applied: ${_message(e)}';
        await _cache.removeMutation(mutation.id);
        _pending = await _cache.readMutations();
      }
    }
    if (applied) {
      await Future.wait([
        loadHydration(),
        loadBody(),
        loadGoals(),
        loadTrends(),
      ]);
    }
    _notify();
  }

  Future<void> _apply(PendingMutation mutation) async {
    final payload = mutation.payload;
    switch (mutation.type) {
      case PendingMutationType.hydrationAdd:
        final timestamp = _parseTime(payload['timestamp']);
        // Idempotency without a server key: the client-supplied timestamp is
        // stored verbatim, so an entry already carrying it means the write
        // landed and the acknowledgement was lost.
        if (timestamp != null && await _hydrationAlreadyLogged(timestamp)) {
          return;
        }
        await _api.addHydration(
          amount: _number(payload['amount']),
          unit: payload['unit']?.toString(),
          timestamp: timestamp,
        );
      case PendingMutationType.hydrationUpdate:
        await _api.updateHydration(
          payload['id']?.toString() ?? '',
          amount: _number(payload['amount']),
          unit: payload['unit']?.toString(),
          timestamp: _parseTime(payload['timestamp']),
        );
      case PendingMutationType.hydrationDelete:
        try {
          await _api.deleteHydration(payload['id']?.toString() ?? '');
        } on Object catch (e) {
          if (!_isAlreadyGone(e)) rethrow;
        }
      case PendingMutationType.hydrationTarget:
        await _api.updateHydrationTarget(
          payload['targetMl'] is num
              ? (payload['targetMl'] as num).round()
              : int.parse(payload['targetMl'].toString()),
        );
      case PendingMutationType.bodyAdd:
        final measuredAt = _parseTime(payload['measuredAt']);
        if (measuredAt != null && await _bodyAlreadySaved(measuredAt)) {
          return;
        }
        await _api.addBodyMeasurement(
          weight: payload['weight'] == null ? null : _number(payload['weight']),
          height: payload['height'] == null ? null : _number(payload['height']),
          weightUnit: payload['weightUnit']?.toString(),
          heightUnit: payload['heightUnit']?.toString(),
          measuredAt: measuredAt,
        );
      case PendingMutationType.goalsUpdate:
        await _api.updateGoals(Map<String, dynamic>.from(payload));
    }
  }

  Future<bool> _hydrationAlreadyLogged(DateTime timestamp) async {
    try {
      final overview =
          HydrationOverview.fromJson(await _api.getHydration());
      for (final day in overview.days) {
        for (final entry in day.entries) {
          if (entry.timestamp.millisecondsSinceEpoch ==
              timestamp.millisecondsSinceEpoch) {
            return true;
          }
        }
      }
    } on Object {
      // If the check itself fails, let the write attempt decide.
    }
    return false;
  }

  Future<bool> _bodyAlreadySaved(DateTime measuredAt) async {
    try {
      final body = BodySummary.fromJson(await _api.getBody());
      for (final entry in body.history) {
        if (entry.measuredAt.millisecondsSinceEpoch ==
            measuredAt.millisecondsSinceEpoch) {
          return true;
        }
      }
    } on Object {
      // Same as above: fall through to the write attempt.
    }
    return false;
  }

  Future<bool> _queueOrFail(
    Object error,
    PendingMutationType type,
    Map<String, dynamic> payload, {
    required String queuedMessage,
  }) async {
    if (!_isRetryable(error)) {
      _notice = _message(error);
      return false;
    }
    final mutation = PendingMutation(
      id: 'm-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    );
    await _cache.enqueueMutation(mutation);
    _pending = await _cache.readMutations();
    _notice = queuedMessage;
    return false;
  }

  void clearNotice() {
    if (_notice == null && _lastSyncError == null) return;
    _notice = null;
    _lastSyncError = null;
    _notify();
  }

  // ── Internals ──────────────────────────────────────────────────────────

  /// Only connection and server-availability problems are worth retrying.
  /// A validation rejection (4xx) would fail identically forever.
  bool _isRetryable(Object error) {
    if (error is NetworkFailure) return true;
    if (error is ServerFailure) {
      final code = error.code;
      if (code == null) return false;
      final status = int.tryParse(code.replaceFirst('HTTP_', '')) ?? 0;
      return status == 408 || status == 429 || status >= 500;
    }
    if (error is Failure) return false;
    return true;
  }

  bool _isAlreadyGone(Object error) =>
      error is ServerFailure && error.code == 'HTTP_404';

  String _message(Object error) {
    if (error is Failure) return error.message;
    try {
      final mapped = mapDioError(error);
      return mapped.message;
    } on Object {
      return 'Something went wrong. Please try again.';
    }
  }

  void _markFailure(String section, Object error) {
    // A failed section silently keeps its cached value and only surfaces as a
    // generic "Offline" banner; log the real reason so it is diagnosable.
    if (kDebugMode) {
      debugPrint('[wellness] $section refresh failed: $error');
    }
    _stale.add(section);
    final hasCached = switch (section) {
      'hydration' => _hydration != null,
      'body' => _body != null,
      'goals' => _goals != null,
      'trends' => _trends != null,
      'insights' => _insights != null,
      'capabilities' => _capabilities != null,
      _ => false,
    };
    if (!hasCached) {
      _error ??= _message(error);
    }
  }

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.parse(value?.toString() ?? '0');
  }

  DateTime? _parseTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  void _deferNotify() {
    if (_disposed) return;
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Outcome of applying AI targets: what was persisted and what the backend
/// refused (user-owned, out-of-range, or unsupported).
class AiGoalApplyResult {
  const AiGoalApplyResult({required this.applied, required this.skipped});

  final List<String> applied;
  final List<String> skipped;
}
