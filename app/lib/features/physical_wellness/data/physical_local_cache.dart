import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:mindease/features/physical_wellness/data/lifestyle_models.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_models.dart';

/// Offline storage for Physical Wellness: the last-known dashboard payload,
/// the lifestyle views (hydration, body, goals, trends, insights,
/// capabilities), the registered device, a durable queue of unsynced batches,
/// and a journal of writes that have not been confirmed by the server.
///
/// Implemented on SharedPreferences (JSON-encoded strings under a
/// `physical_wellness.*` key namespace — the app's existing dotted-key
/// convention). The interface exists so tests can substitute an in-memory
/// fake; no new dependency was introduced for this.
abstract class PhysicalLocalCache {
  Future<PhysicalToday?> readToday();

  Future<void> writeToday(PhysicalToday today);

  Future<WearableDevice?> readDevice();

  Future<void> writeDevice(WearableDevice device);

  Future<void> clearDevice();

  /// Pending batches, oldest first. Each batch is the raw sync payload map
  /// destined for `POST /physical/sync`.
  Future<List<Map<String, dynamic>>> readQueue();

  Future<void> enqueueBatch(Map<String, dynamic> batch);

  /// Removes one queued batch after the server acknowledged it.
  Future<void> removeBatch(String clientSyncId);

  Future<HydrationOverview?> readHydration();

  Future<void> writeHydration(HydrationOverview value);

  Future<BodySummary?> readBody();

  Future<void> writeBody(BodySummary value);

  Future<GoalsOverview?> readGoals();

  Future<void> writeGoals(GoalsOverview value);

  Future<TrendsOverview?> readTrends();

  Future<void> writeTrends(TrendsOverview value);

  Future<InsightsOverview?> readInsights();

  Future<void> writeInsights(InsightsOverview value);

  Future<CapabilityList?> readCapabilities();

  Future<void> writeCapabilities(CapabilityList value);

  /// Writes that still need to reach the server, oldest first. They are not
  /// folded into the confirmed views, so nothing unconfirmed is shown as saved.
  Future<List<PendingMutation>> readMutations();

  Future<void> enqueueMutation(PendingMutation mutation);

  Future<void> removeMutation(String mutationId);

  Future<void> clearAll();
}

class PhysicalJsonCache implements PhysicalLocalCache {
  PhysicalJsonCache();

  static const String _kToday = 'physical_wellness.today';
  static const String _kDevice = 'physical_wellness.device';
  static const String _kQueue = 'physical_wellness.pending_batches';
  static const String _kHydration = 'physical_wellness.hydration';
  static const String _kBody = 'physical_wellness.body';
  static const String _kGoals = 'physical_wellness.goals';
  static const String _kTrends = 'physical_wellness.trends';
  static const String _kInsights = 'physical_wellness.insights';
  static const String _kCapabilities = 'physical_wellness.capabilities';
  static const String _kMutations = 'physical_wellness.pending_mutations';

  /// Bound so a long offline stretch can never grow the key without limit;
  /// the OLDEST batches are dropped first (the newest are most valuable).
  static const int _maxBatches = 20;

  /// Same bound for unconfirmed writes. Dropping the oldest is preferable to
  /// unbounded growth, and the UI always reports how many are waiting.
  static const int _maxMutations = 50;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Cache access must never throw: on platforms without the plugin
  /// (widget tests, headless runs) every read degrades to its default and
  /// every write is a no-op, so the controller still functions online.
  Future<T?> _safe<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } on Object {
      return null;
    }
  }

  Future<void> _safeWrite(Future<bool> Function() body) async {
    try {
      await body();
    } on Object {
      // Best-effort persistence; losing a cache write is not fatal.
    }
  }

  Future<T?> _read<T>(String key, T Function(Map<String, dynamic>) fromJson) =>
      _safe(() async {
        final raw = (await _prefs).getString(key);
        if (raw == null) return null;
        return _decode(raw, fromJson);
      });

  Future<void> _write(String key, Map<String, dynamic> json) =>
      _safeWrite(() async {
        return (await _prefs).setString(key, jsonEncode(json));
      });

  @override
  Future<PhysicalToday?> readToday() => _read(_kToday, PhysicalToday.fromJson);

  @override
  Future<void> writeToday(PhysicalToday today) => _write(_kToday, today.toJson());

  @override
  Future<WearableDevice?> readDevice() =>
      _read(_kDevice, WearableDevice.fromJson);

  @override
  Future<void> writeDevice(WearableDevice device) =>
      _write(_kDevice, device.toJson());

  @override
  Future<void> clearDevice() =>
      _safeWrite(() async => (await _prefs).remove(_kDevice));

  @override
  Future<List<Map<String, dynamic>>> readQueue() async {
    try {
      final raw = (await _prefs).getString(_kQueue);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) item.cast<String, dynamic>(),
      ];
    } on Object {
      // Missing plugin or corrupt queue: a broken entry must never block
      // future syncs.
      return const [];
    }
  }

  @override
  Future<void> enqueueBatch(Map<String, dynamic> batch) => _safeWrite(() async {
        final queue = [...await readQueue(), batch];
        final trimmed = queue.length > _maxBatches
            ? queue.sublist(queue.length - _maxBatches)
            : queue;
        return (await _prefs).setString(_kQueue, jsonEncode(trimmed));
      });

  @override
  Future<void> removeBatch(String clientSyncId) => _safeWrite(() async {
        final queue = await readQueue();
        queue.retainWhere((batch) => batch['clientSyncId'] != clientSyncId);
        if (queue.isEmpty) {
          return (await _prefs).remove(_kQueue);
        }
        return (await _prefs).setString(_kQueue, jsonEncode(queue));
      });

  @override
  Future<HydrationOverview?> readHydration() =>
      _read(_kHydration, HydrationOverview.fromJson);

  @override
  Future<void> writeHydration(HydrationOverview value) =>
      _write(_kHydration, value.toJson());

  @override
  Future<BodySummary?> readBody() => _read(_kBody, BodySummary.fromJson);

  @override
  Future<void> writeBody(BodySummary value) => _write(_kBody, value.toJson());

  @override
  Future<GoalsOverview?> readGoals() => _read(_kGoals, GoalsOverview.fromJson);

  @override
  Future<void> writeGoals(GoalsOverview value) =>
      _write(_kGoals, value.toJson());

  @override
  Future<TrendsOverview?> readTrends() =>
      _read(_kTrends, TrendsOverview.fromJson);

  @override
  Future<void> writeTrends(TrendsOverview value) =>
      _write(_kTrends, value.toJson());

  @override
  Future<InsightsOverview?> readInsights() =>
      _read(_kInsights, InsightsOverview.fromJson);

  @override
  Future<void> writeInsights(InsightsOverview value) =>
      _write(_kInsights, value.toJson());

  @override
  Future<CapabilityList?> readCapabilities() =>
      _read(_kCapabilities, CapabilityList.fromJson);

  @override
  Future<void> writeCapabilities(CapabilityList value) =>
      _write(_kCapabilities, value.toJson());

  @override
  Future<List<PendingMutation>> readMutations() async {
    try {
      final raw = (await _prefs).getString(_kMutations);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) PendingMutation.fromJson(item.cast<String, dynamic>()),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> enqueueMutation(PendingMutation mutation) => _safeWrite(() async {
        final queue = [...await readMutations(), mutation];
        final trimmed = queue.length > _maxMutations
            ? queue.sublist(queue.length - _maxMutations)
            : queue;
        return (await _prefs).setString(_kMutations, jsonEncode(trimmed));
      });

  @override
  Future<void> removeMutation(String mutationId) => _safeWrite(() async {
        final queue = await readMutations();
        queue.retainWhere((mutation) => mutation.id != mutationId);
        if (queue.isEmpty) {
          return (await _prefs).remove(_kMutations);
        }
        return (await _prefs).setString(_kMutations, jsonEncode(queue));
      });

  @override
  Future<void> clearAll() => _safeWrite(() async {
        final prefs = await _prefs;
        for (final key in [
          _kToday,
          _kDevice,
          _kQueue,
          _kHydration,
          _kBody,
          _kGoals,
          _kTrends,
          _kInsights,
          _kCapabilities,
          _kMutations,
        ]) {
          await prefs.remove(key);
        }
        return true;
      });

  T? _decode<T>(String raw, T Function(Map<String, dynamic>) fromJson) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(decoded.cast<String, dynamic>());
    } on FormatException {
      return null;
    }
  }
}
