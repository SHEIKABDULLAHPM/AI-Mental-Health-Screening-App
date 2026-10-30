import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/physical_wellness/data/lifestyle_models.dart';
import 'package:mindease/features/physical_wellness/data/physical_local_cache.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_api.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_models.dart';
import 'package:mindease/features/physical_wellness/data/wearable_gateway.dart';
import 'package:mindease/features/physical_wellness/presentation/screens/physical_wellness_screen.dart';
import 'package:mindease/features/physical_wellness/presentation/state/physical_wellness_controller.dart';

// ── Test doubles ──────────────────────────────────────────────────────────

class StubPhysicalWellnessApi implements PhysicalWellnessApi {
  Map<String, dynamic>? todayBody;
  Object? todayError;
  Map<String, dynamic> summaryBody = const {};
  Object? summaryError;
  Map<String, dynamic> syncBody = const {'status': 'SUCCESS'};
  Object? syncError;
  /// Optional per-batch failure injection (e.g. a 404 for one poisoned batch).
  Object? Function(Map<String, dynamic> batch)? syncErrorSelector;
  Map<String, dynamic> registerBody = const {};
  Object? registerError;
  final List<Map<String, dynamic>> syncedBatches = [];
  final List<String> deletedDevices = [];

  void _throwIfSet(Object? error) {
    if (error != null) throw error;
  }

  @override
  Future<Map<String, dynamic>> getPhysicalToday() async {
    _throwIfSet(todayError);
    return todayBody ?? const {};
  }

  @override
  Future<Map<String, dynamic>> getPhysicalSummary() async {
    _throwIfSet(summaryError);
    return summaryBody;
  }

  @override
  Future<Map<String, dynamic>> syncPhysical(Map<String, dynamic> payload) async {
    final scripted = syncErrorSelector?.call(payload);
    if (scripted != null) throw scripted;
    _throwIfSet(syncError);
    syncedBatches.add(payload);
    return syncBody;
  }

  @override
  Future<Map<String, dynamic>> registerDevice({
    required String provider,
    required String deviceIdentifier,
    String? manufacturer,
    String? model,
    String? firmwareVersion,
    List<String>? capabilities,
    int? batteryLevel,
  }) async {
    _throwIfSet(registerError);
    return registerBody.isEmpty
        ? {
            'id': 'dev-1',
            'provider': provider,
            'deviceIdentifier': deviceIdentifier,
            'model': model,
            'connectionStatus': 'CONNECTED',
            'capabilities': capabilities ?? const <String>[],
          }
        : registerBody;
  }

  @override
  Future<void> deleteDevice(String deviceId) async {
    deletedDevices.add(deviceId);
  }

  @override
  Future<List<Map<String, dynamic>>> listDevices() async => const [];

  @override
  Future<Map<String, dynamic>> updateDeviceStatus(
    String deviceId, {
    int? batteryLevel,
    bool? charging,
    String? connectionStatus,
    String? firmwareVersion,
  }) async =>
      const {};

  @override
  Future<Map<String, dynamic>> getPhysicalActivity({int? days}) async =>
      const {'available': false, 'days': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> getPhysicalHeartRate({int? hours}) async =>
      const {};

  @override
  Future<Map<String, dynamic>> getPhysicalSleep({int? limit}) async =>
      const {'available': false, 'sessions': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> getPhysicalExercise({int? limit}) async =>
      const {'available': false, 'sessions': <dynamic>[]};

  // Lifestyle endpoints: the existing controller tests never call these; the
  // lifestyle tests use their own recording stub.
  Map<String, dynamic> hydrationBody = const {};
  Map<String, dynamic> bodyBody = const {};
  Map<String, dynamic> goalsBody = const {};
  Map<String, dynamic> trendsBody = const {};
  Map<String, dynamic> insightsBody = const {};
  Map<String, dynamic> capabilitiesBody = const {};
  final List<List<Map<String, dynamic>>> reportedCapabilities = [];

  @override
  Future<Map<String, dynamic>> getHydration({int? days}) async => hydrationBody;

  @override
  Future<Map<String, dynamic>> addHydration({
    required double amount,
    String? unit,
    DateTime? timestamp,
  }) async =>
      const {};

  @override
  Future<Map<String, dynamic>> updateHydration(
    String entryId, {
    required double amount,
    String? unit,
    DateTime? timestamp,
  }) async =>
      const {};

  @override
  Future<void> deleteHydration(String entryId) async {}

  @override
  Future<Map<String, dynamic>> updateHydrationTarget(int targetMl) async =>
      hydrationBody;

  @override
  Future<Map<String, dynamic>> getBody({int? limit}) async => bodyBody;

  @override
  Future<Map<String, dynamic>> addBodyMeasurement({
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    DateTime? measuredAt,
  }) async =>
      const {};

  @override
  Future<Map<String, dynamic>> updateBodyMeasurement(
    String measurementId, {
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    DateTime? measuredAt,
  }) async =>
      const {};

  @override
  Future<void> deleteBodyMeasurement(String measurementId) async {}

  @override
  Future<Map<String, dynamic>> getGoals() async => goalsBody;

  @override
  Future<Map<String, dynamic>> updateGoals(Map<String, dynamic> targets) async =>
      goalsBody;

  @override
  Future<Map<String, dynamic>> applyAiGoalRecommendations(
          List<Map<String, dynamic>> recommendations) async =>
      {'goals': goalsBody, 'applied': const [], 'skipped': const []};

  @override
  Future<Map<String, dynamic>> getTrends({int? days}) async => trendsBody;

  @override
  Future<Map<String, dynamic>> getInsights() async => insightsBody;

  @override
  Future<Map<String, dynamic>> getCapabilities(String deviceId) async =>
      capabilitiesBody;

  @override
  Future<Map<String, dynamic>> reportCapabilities(
    String deviceId,
    List<Map<String, dynamic>> capabilities,
  ) async {
    reportedCapabilities.add(capabilities);
    return capabilitiesBody;
  }
}

class FakeWearableGateway implements WearableGateway {
  bool available = true;
  String bluetoothStateValue = 'on';
  bool permissions = true;
  bool connectResult = true;
  final List<bool> connectScript = [];
  List<WearableScanResult> scanResults = [
    const WearableScanResult(deviceIdentifier: 'AA:BB:CC', name: 'FitPro Watch 8'),
  ];
  WearableSnapshot? snapshot;
  WearableException? scanError;
  WearableException? connectError;
  WearableException? snapshotError;
  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];
  bool startMonitorResult = true;
  bool stopMonitorResult = true;
  bool monitorRunning = false;
  int startMonitorCalls = 0;
  final StreamController<LiveHeartRateSample> liveSamples =
      StreamController<LiveHeartRateSample>.broadcast();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String> bluetoothState() async => bluetoothStateValue;

  @override
  Future<bool> hasPermissions() async => permissions;

  @override
  Future<bool> requestPermissions() async => permissions;

  @override
  Future<List<WearableScanResult>> scan({Duration timeout = const Duration(seconds: 6)}) async {
    if (scanError != null) throw scanError!;
    return scanResults;
  }

  @override
  Future<bool> connect(String deviceIdentifier) async {
    connectCalls.add(deviceIdentifier);
    if (connectError != null) throw connectError!;
    if (connectScript.isNotEmpty) return connectScript.removeAt(0);
    return connectResult;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls.add('disconnect');
  }

  @override
  Future<WearableSnapshot?> readSnapshot() async {
    if (snapshotError != null) throw snapshotError!;
    return snapshot;
  }

  @override
  Future<bool> startHeartRateMonitor() async {
    startMonitorCalls++;
    if (!startMonitorResult) return false;
    monitorRunning = true;
    return true;
  }

  @override
  Future<bool> stopHeartRateMonitor() async {
    monitorRunning = false;
    return stopMonitorResult;
  }

  @override
  Stream<LiveHeartRateSample> get liveHeartRate => liveSamples.stream;
}

class FakePhysicalLocalCache implements PhysicalLocalCache {
  PhysicalToday? today;
  WearableDevice? device;
  HydrationOverview? hydration;
  BodySummary? body;
  GoalsOverview? goals;
  TrendsOverview? trends;
  InsightsOverview? insights;
  CapabilityList? capabilities;
  final List<PendingMutation> mutations = [];
  final List<Map<String, dynamic>> queue = [];

  @override
  Future<PhysicalToday?> readToday() async => today;

  @override
  Future<void> writeToday(PhysicalToday value) async => today = value;

  @override
  Future<WearableDevice?> readDevice() async => device;

  @override
  Future<void> writeDevice(WearableDevice value) async => device = value;

  @override
  Future<void> clearDevice() async => device = null;

  @override
  Future<List<Map<String, dynamic>>> readQueue() async =>
      List.unmodifiable(queue);

  @override
  Future<void> enqueueBatch(Map<String, dynamic> batch) async =>
      queue.add(batch);

  @override
  Future<void> removeBatch(String clientSyncId) async =>
      queue.removeWhere((b) => b['clientSyncId'] == clientSyncId);

  @override
  Future<HydrationOverview?> readHydration() async => hydration;

  @override
  Future<void> writeHydration(HydrationOverview value) async =>
      hydration = value;

  @override
  Future<BodySummary?> readBody() async => body;

  @override
  Future<void> writeBody(BodySummary value) async => body = value;

  @override
  Future<GoalsOverview?> readGoals() async => goals;

  @override
  Future<void> writeGoals(GoalsOverview value) async => goals = value;

  @override
  Future<TrendsOverview?> readTrends() async => trends;

  @override
  Future<void> writeTrends(TrendsOverview value) async => trends = value;

  @override
  Future<InsightsOverview?> readInsights() async => insights;

  @override
  Future<void> writeInsights(InsightsOverview value) async => insights = value;

  @override
  Future<CapabilityList?> readCapabilities() async => capabilities;

  @override
  Future<void> writeCapabilities(CapabilityList value) async =>
      capabilities = value;

  @override
  Future<List<PendingMutation>> readMutations() async =>
      List.unmodifiable(mutations);

  @override
  Future<void> enqueueMutation(PendingMutation mutation) async =>
      mutations.add(mutation);

  @override
  Future<void> removeMutation(String mutationId) async =>
      mutations.removeWhere((m) => m.id == mutationId);

  @override
  Future<void> clearAll() async {
    today = null;
    device = null;
    queue.clear();
    hydration = null;
    body = null;
    goals = null;
    trends = null;
    insights = null;
    capabilities = null;
    mutations.clear();
  }
}

// ── Payload builders ──────────────────────────────────────────────────────

Map<String, dynamic> todayJson({
  double? stepsValue,
  bool stepsSupported = true,
  double? distanceValue,
  bool deviceAttached = true,
}) =>
    {
      'date': '2026-10-06',
      if (deviceAttached)
        'device': {
          'id': 'dev-1',
          'provider': 'FITPRO',
          'model': 'Watch 8',
          'connectionStatus': 'CONNECTED',
          'batteryLevel': 82,
          'charging': false,
        },
      'steps': {
        'supported': stepsSupported,
        'value': stepsValue,
        'unit': 'count',
        'updatedAt': '2026-10-06T10:00:00Z',
      },
      'distance': {'supported': true, 'value': distanceValue, 'unit': 'm'},
      'calories': {'supported': true, 'value': 1840.0, 'unit': 'kcal'},
      'heartRate': {
        'supported': true,
        'latest': 72.0,
        'averageToday': 75.0,
        'resting': 58.0,
        'unit': 'bpm',
      },
      'sleep': {
        'supported': true,
        'durationMillis': 26400000,
        'bedtime': '2026-10-05T22:30:00Z',
        'wakeTime': '2026-10-06T06:00:00Z',
        'date': '2026-10-06',
      },
      'exercise': {'supported': true, 'durationMillis': 1800000, 'sessionCount': 1},
      'sync': {
        'lastSyncedAt': '2026-10-06T09:00:00Z',
        'lastStatus': 'SUCCESS',
      },
    };

WearableSnapshot watchSnapshot() => WearableSnapshot(
      deviceIdentifier: 'AA:BB:CC',
      firmwareVersion: 'V15183',
      batteryLevel: 82,
      charging: false,
      capabilities: const ['STEPS', 'DISTANCE', 'CALORIES', 'HEART_RATE'],
      readings: [
        WearableReading(
          metricType: 'HEART_RATE',
          value: 71,
          timestamp: DateTime.utc(2026, 10, 6, 8, 30),
          unit: 'bpm',
        ),
        WearableReading(
          metricType: 'STEPS',
          value: 1200,
          timestamp: DateTime.utc(2026, 10, 6, 9, 0),
          unit: 'steps',
        ),
      ],
      dailyActivity: const {
        'date': '2026-10-06',
        'steps': 4200,
        'distance': 3.1,
        'distanceUnit': 'km',
        'calories': 400.0,
        'activeMinutes': 55,
      },
      sleepSessions: const [
        {
          'startTime': '2026-10-05T22:30:00Z',
          'endTime': '2026-10-06T06:00:00Z',
          'durationMillis': 26400000,
        },
      ],
      exerciseSessions: const [],
      recordedAt: DateTime.utc(2026, 10, 6, 9, 30),
    );

PhysicalWellnessController makeController({
  StubPhysicalWellnessApi? api,
  FakeWearableGateway? gateway,
  FakePhysicalLocalCache? cache,
}) =>
    PhysicalWellnessController(
      api ?? StubPhysicalWellnessApi(),
      gateway: gateway ?? FakeWearableGateway(),
      cache: cache ?? FakePhysicalLocalCache(),
    );

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('distanceLabel', () {
    test('short distances stay in metres', () {
      // The watch reports 42 m; "0.04 km" was ellipsised in the stat tile.
      expect(distanceLabel(42), '42 m');
      expect(distanceLabel(0), '0 m');
      expect(distanceLabel(999), '999 m');
    });

    test('a kilometre and up uses two decimal places', () {
      expect(distanceLabel(1000), '1.00 km');
      expect(distanceLabel(4840), '4.84 km');
    });
  });

  group('MetricBlock three-state parsing', () {
    test('supported=false with null value means the device lacks it', () {
      final block = MetricBlock.fromJson(const {'supported': false, 'unit': 'count'});
      expect(block.supported, isFalse);
      expect(block.value, isNull);
    });

    test('supported=true with null value means no data yet', () {
      final block = MetricBlock.fromJson(const {'supported': true, 'unit': 'count'});
      expect(block.supported, isTrue);
      expect(block.value, isNull);
    });

    test('a genuine zero is preserved, never dropped', () {
      final block = MetricBlock.fromJson(const {
        'supported': true,
        'value': 0,
        'unit': 'count',
      });
      expect(block.value, 0);
    });
  });

  group('PhysicalToday.fromJson', () {
    test('maps every block from a server payload', () {
      final today = PhysicalToday.fromJson(todayJson(stepsValue: 4200));
      expect(today.date, '2026-10-06');
      expect(today.steps.value, 4200);
      expect(today.device!.batteryLevel, 82);
      expect(today.heartRate.latest, 72.0);
      expect(today.sleep.durationMillis, 26400000);
      expect(today.exercise.sessionCount, 1);
      expect(today.sync.lastStatus, 'SUCCESS');
    });

    test('missing device key becomes null, not a placeholder', () {
      final today = PhysicalToday.fromJson(todayJson(deviceAttached: false));
      expect(today.device, isNull);
    });

    test('round-trips through toJson for the offline cache', () {
      final original = PhysicalToday.fromJson(todayJson(stepsValue: 4200));
      final restored = PhysicalToday.fromJson(original.toJson());
      expect(restored.date, original.date);
      expect(restored.steps.value, original.steps.value);
      expect(restored.heartRate.resting, original.heartRate.resting);
      expect(restored.device?.batteryLevel, original.device?.batteryLevel);
    });
  });

  group('PhysicalWellnessController.loadToday', () {
    test('success replaces state and persists to cache', () async {
      final api = StubPhysicalWellnessApi()
        ..todayBody = todayJson(stepsValue: 4200);
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.loadToday();

      expect(ctrl.today?.steps.value, 4200);
      expect(ctrl.offline, isFalse);
      expect(ctrl.error, isNull);
      expect(cache.today?.steps.value, 4200);
    });

    test('network failure with cached data degrades offline, no error', () async {
      final api = StubPhysicalWellnessApi()..todayError = const ServerFailure('down');
      final cache = FakePhysicalLocalCache()
        ..today = PhysicalToday.fromJson(todayJson(stepsValue: 1111));
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.loadToday();

      expect(ctrl.today?.steps.value, 1111);
      expect(ctrl.offline, isTrue);
      expect(ctrl.error, isNull);
    });

    test('network failure with no cache surfaces the failure message', () async {
      final api = StubPhysicalWellnessApi()..todayError = const ServerFailure('boom');
      final ctrl = makeController(api: api);

      await ctrl.loadToday();

      expect(ctrl.today, isNull);
      expect(ctrl.error, 'boom');
    });
  });

  group('PhysicalWellnessController.init automatic refresh', () {
    Future<void> settle() async {
      // The auto-sync is deliberately unawaited. The manual/auto reconnect
      // path drops any stale GATT handle and pauses briefly before dialling,
      // so give it that pause plus a few macrotask yields to finish
      // deterministically.
      await Future<void>.delayed(const Duration(milliseconds: 320));
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    WearableDevice pairedDevice() => WearableDevice.fromJson(const {
          'id': 'dev-1',
          'provider': 'FITPRO',
          'deviceIdentifier': 'AA:BB:CC',
          'model': 'FitPro Watch 8',
          'connectionStatus': 'CONNECTED',
        });

    test('fetches the paired watch once per session, without a banner', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final cache = FakePhysicalLocalCache()..device = pairedDevice();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.init();
      await settle();

      // The cached paired watch is read and uploaded automatically on open.
      expect(api.syncedBatches, hasLength(1));
      expect(cache.queue, isEmpty);
      // Quiet pipeline: a healthy background refresh raises no notice and
      // still starts from the cached dashboard.
      expect(ctrl.notice, isNull);
      expect(gateway.connectCalls, contains('AA:BB:CC'));

      // Re-entering the screen within the same session must not re-read the
      // watch: one automatic fetch per session, no battery-sapping polling.
      await ctrl.init();
      await settle();
      expect(api.syncedBatches, hasLength(1));
    });

    test('skips silently when Bluetooth is off or permissions are missing', () async {
      final api = StubPhysicalWellnessApi();
      final cache = FakePhysicalLocalCache()..device = pairedDevice();

      final offGateway = FakeWearableGateway()..bluetoothStateValue = 'off';
      final offCtrl = makeController(api: api, gateway: offGateway, cache: cache);
      await offCtrl.init();
      await settle();

      final noPermissionCtrl = makeController(
        api: api,
        gateway: FakeWearableGateway()..permissions = false,
        cache: cache,
      );
      await noPermissionCtrl.init();
      await settle();

      // Background preconditions require user action and belong to the
      // pairing flow, so the quiet pipeline skips them without banners.
      expect(api.syncedBatches, isEmpty);
      expect(offGateway.connectCalls, isEmpty);
      expect(offCtrl.notice, isNull);
      expect(noPermissionCtrl.notice, isNull);
    });
  });

  group('PhysicalWellnessController.syncNow', () {
    test('snapshot is enqueued, flushed and the queue drains', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson(stepsValue: 4200);
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      // Pairing already pulled the first batch; "Sync now" reads and
      // uploads another one on top.
      await ctrl.syncNow();

      expect(api.syncedBatches, hasLength(2));
      expect(cache.queue, isEmpty);
      expect(ctrl.pendingBatches, 0);
      expect(gateway.connectCalls, contains('AA:BB:CC'));
    });

    test('manual sync drops a stale GATT handle before reconnecting', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final ctrl = makeController(
        api: api,
        gateway: gateway,
        cache: FakePhysicalLocalCache(),
      );

      await ctrl.connectDevice();
      expect(gateway.disconnectCalls, isEmpty);
      await ctrl.syncNow();

      // Android reports a zombie GATT as "already connected", so the manual
      // path must close it first or the fetch writes into a dead link.
      expect(gateway.disconnectCalls, hasLength(1));
      expect(gateway.connectCalls.last, 'AA:BB:CC');
    });

    test('failed upload keeps the batch for a later retry', () async {
      final api = StubPhysicalWellnessApi()
        ..todayBody = todayJson(stepsValue: 1)
        ..syncError = const NetworkFailure('offline');
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      await ctrl.syncNow();

      // Pairing's automatic first batch plus the manual one both sit in the
      // durable queue while uploads fail.
      expect(cache.queue, hasLength(2));
      expect(ctrl.pendingBatches, 2);

      // Connection restored: the queued batches drain without another read.
      api.syncError = null;
      await ctrl.flushQueue();

      expect(cache.queue, isEmpty);
      expect(api.syncedBatches, hasLength(2));
    });

    test('a server-rejected batch is surfaced instead of vanishing', () async {
      final api = StubPhysicalWellnessApi()
        ..syncBody = const {
          'status': 'FAILED',
          'received': 2,
          'accepted': 0,
          'duplicates': 0,
          'rejected': 2,
          'rejections': [
            {
              'category': 'sleepSessions',
              'index': 0,
              'reason': 'end must be after start',
            },
          ],
        };
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      await ctrl.syncNow();

      // The invalid batch cannot be fixed by retrying, so it is dropped —
      // but the user learns exactly what the server said.
      expect(cache.queue, isEmpty);
      expect(api.syncedBatches, hasLength(2));
      expect(ctrl.notice, contains('rejected'));
      expect(ctrl.notice, contains('Reason: end must be after start'));
    });

    test('without a registered watch, sync is refused with a notice', () async {
      final ctrl = makeController();

      await ctrl.syncNow();

      expect(ctrl.notice, contains('Connect your watch first'));
    });
  });

  group('PhysicalWellnessController.syncIfStale', () {
    test('throttles repeat reads inside the minimum interval', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final ctrl = makeController(
        api: api,
        gateway: gateway,
        cache: FakePhysicalLocalCache(),
      );

      await ctrl.connectDevice();
      await ctrl.syncIfStale(minInterval: Duration.zero);
      final afterFirst = api.syncedBatches.length;

      // A second tick within 90 s must not reconnect or re-upload.
      await ctrl.syncIfStale();
      expect(api.syncedBatches, hasLength(afterFirst));
      // A recent healthy link is reused; only the manual path force-drops it.
      expect(gateway.disconnectCalls, isEmpty);
    });

    test('never interleaves a fetch with a live measurement session', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final ctrl = makeController(
        api: api,
        gateway: gateway,
        cache: FakePhysicalLocalCache(),
      );
      await ctrl.connectDevice();
      await ctrl.startHeartRateMonitor();
      final baseline = api.syncedBatches.length;

      await ctrl.syncIfStale(minInterval: Duration.zero);

      expect(api.syncedBatches, hasLength(baseline));
      expect(gateway.disconnectCalls, isEmpty);
      await ctrl.stopHeartRateMonitor();
    });

    test('does nothing when no watch is paired', () async {
      final gateway = FakeWearableGateway();
      final ctrl = makeController(gateway: gateway);

      await ctrl.syncIfStale(minInterval: Duration.zero);

      expect(gateway.connectCalls, isEmpty);
    });
  });

  group('buildBatch payload', () {
    test('mirrors the backend sync contract', () {
      final ctrl = makeController();
      final device = WearableDevice.fromJson(const {
        'id': 'dev-1',
        'provider': 'FITPRO',
        'deviceIdentifier': 'AA:BB:CC',
        'connectionStatus': 'CONNECTED',
      });

      final batch = ctrl.buildBatch(device, watchSnapshot());

      expect(batch['clientSyncId'], startsWith('c-'));
      expect(batch['deviceId'], 'dev-1');
      expect(batch['deviceStatus'], {
        'connectionStatus': 'CONNECTED',
        'batteryLevel': 82,
        'charging': false,
        'firmwareVersion': 'V15183',
      });
      final readings = batch['readings'] as List;
      expect(readings, hasLength(2));
      expect((readings.first as Map)['timestamp'], isNotNull);
      expect(batch['dailyActivity'], hasLength(1));
      expect(
        ((batch['dailyActivity'] as List).first as Map)['aggregation'],
        'INTERVAL_DELTA',
      );
      expect(batch['sleepSessions'], hasLength(1));
      expect(batch['exerciseSessions'], isEmpty);
    });
  });

  group('PhysicalWellnessController.connectDevice', () {
    test('registers the first scan candidate and caches it', () async {
      final api = StubPhysicalWellnessApi();
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();

      expect(ctrl.device?.deviceIdentifier, 'AA:BB:CC');
      expect(cache.device?.deviceIdentifier, 'AA:BB:CC');
      // Pairing automatically pulls the first data batch, so the outcome the
      // user sees is "paired AND data flowing".
      expect(api.syncedBatches, hasLength(1));
      expect(ctrl.notice, contains('connected'));
    });

    test('empty scan reports a friendly notice, not an error', () async {
      final gateway = FakeWearableGateway()..scanResults = const [];
      final ctrl = makeController(gateway: gateway);

      await ctrl.connectDevice();

      expect(ctrl.device, isNull);
      expect(ctrl.notice, contains('No watch found'));
      expect(ctrl.error, isNull);
    });

    test('missing permission is surfaced before any scan', () async {
      final gateway = FakeWearableGateway()..permissions = false;
      final ctrl = makeController(gateway: gateway);

      await ctrl.connectDevice();

      expect(ctrl.device, isNull);
      expect(ctrl.notice, contains('permission'));
    });
  });

  group('WearableCompatibility.pickCandidate', () {
    test('prefers the strongest watch-like device', () {
      final pick = WearableCompatibility.pickCandidate(const [
        WearableScanResult(deviceIdentifier: 'TV', name: 'Living Room TV', rssi: -40),
        WearableScanResult(deviceIdentifier: 'W1', name: 'FitPro Watch 8', rssi: -80),
        WearableScanResult(deviceIdentifier: 'W2', name: 'Amazfit GTS', rssi: -60),
      ]);
      expect(pick?.deviceIdentifier, 'W2');
    });

    test('ignores peripherals that are not watches', () {
      final pick = WearableCompatibility.pickCandidate(const [
        WearableScanResult(deviceIdentifier: 'TV', name: 'Living Room TV', rssi: -40),
        WearableScanResult(deviceIdentifier: 'HP', name: 'Headphones X', rssi: -50),
      ]);
      expect(pick, isNull);
    });

    test('skips entries without an address', () {
      final pick = WearableCompatibility.pickCandidate(const [
        WearableScanResult(deviceIdentifier: '', name: 'FitPro Watch', rssi: -40),
      ]);
      expect(pick, isNull);
    });
  });

  group('PhysicalWellnessController.connectDevice states', () {
    test('bluetooth off is reported before any scan', () async {
      final gateway = FakeWearableGateway()..bluetoothStateValue = 'off';
      final ctrl = makeController(gateway: gateway);

      await ctrl.connectDevice();

      expect(ctrl.device, isNull);
      expect(ctrl.notice, contains('turned off'));
      expect(gateway.connectCalls, isEmpty);
    });

    test('unsupported hardware is reported distinctly', () async {
      final gateway = FakeWearableGateway()..bluetoothStateValue = 'unsupported';
      final ctrl = makeController(gateway: gateway);

      await ctrl.connectDevice();

      expect(ctrl.device, isNull);
      expect(ctrl.notice, contains('does not support'));
    });

    test('incompatible-only scan refuses to pair with a random peripheral', () async {
      final gateway = FakeWearableGateway()
        ..scanResults = const [
          WearableScanResult(deviceIdentifier: 'TV:11', name: 'Living Room TV', rssi: -40),
        ];
      final ctrl = makeController(gateway: gateway);

      await ctrl.connectDevice();

      expect(ctrl.device, isNull);
      expect(ctrl.notice, contains('none looks like'));
      expect(gateway.connectCalls, isEmpty);
    });

    test('native scan failure maps to an actionable notice', () async {
      final gateway = FakeWearableGateway()
        ..scanError = const WearableException('BLUETOOTH_OFF');
      final ctrl = makeController(gateway: gateway);

      await ctrl.connectDevice();

      expect(ctrl.device, isNull);
      expect(ctrl.notice, contains('turned off'));
    });

    test('native connect failure maps to an actionable notice', () async {
      final gateway = FakeWearableGateway()
        ..connectError = const WearableException('BUSY');
      final ctrl = makeController(gateway: gateway);

      await ctrl.connectDevice();

      expect(ctrl.device, isNull);
      expect(ctrl.notice, contains('already in progress'));
    });
  });

  group('PhysicalWellnessController.syncNow guards', () {
    test('aborts when the reconnect fails instead of reading anyway', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson(stepsValue: 1);
      final gateway = FakeWearableGateway()
        ..snapshot = watchSnapshot()
        ..connectScript.addAll([true, false, false, false]);
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      expect(ctrl.device, isNotNull);
      gateway.connectCalls.clear();
      await ctrl.syncNow();

      expect(ctrl.notice, contains('Lost connection'));
      // Pairing's automatic first upload already succeeded.
      expect(api.syncedBatches, hasLength(1));
      expect(cache.queue, isEmpty);
    });

    test('snapshot NOT_CONNECTED maps to a reconnect hint', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson(stepsValue: 1);
      final gateway = FakeWearableGateway()
        ..snapshotError = const WearableException('NOT_CONNECTED');
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      await ctrl.syncNow();

      expect(ctrl.notice, contains('Move it closer'));
      expect(api.syncedBatches, isEmpty);
    });

    test('transient reconnect failure is retried, then sync proceeds', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson(stepsValue: 9);
      final gateway = FakeWearableGateway()
        ..snapshot = watchSnapshot()
        ..connectScript.addAll([true, false, true]);
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      final callsAfterConnect = gateway.connectCalls.length;
      await ctrl.syncNow();

      expect(gateway.connectCalls.length, callsAfterConnect + 2);
      // Pairing's automatic batch plus the manual one.
      expect(api.syncedBatches, hasLength(2));
      expect(cache.queue, isEmpty);
    });

    test('persistent reconnect failure gives up after three attempts', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson(stepsValue: 1);
      final gateway = FakeWearableGateway()
        ..snapshot = watchSnapshot()
        ..connectScript.addAll([true, false, false, false, false]);
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      final callsAfterConnect = gateway.connectCalls.length;
      await ctrl.syncNow();

      // Bounded: exactly three tries for "Sync now", then an actionable
      // notice — and no upload from the manual pass itself.
      expect(gateway.connectCalls.length, callsAfterConnect + 3);
      expect(ctrl.notice, contains('Lost connection'));
      // Only pairing's automatic first upload made it through.
      expect(api.syncedBatches, hasLength(1));
      expect(cache.queue, isEmpty);
    });

    test('non-retryable connect errors are not retried', () async {
      final gateway = FakeWearableGateway()
        ..connectError = const WearableException('BLUETOOTH_OFF');
      final ctrl = makeController(gateway: gateway);

      await ctrl.connectDevice();

      expect(gateway.connectCalls, hasLength(1));
      expect(ctrl.device, isNull);
      expect(ctrl.notice, contains('turned off'));
    });
  });

  group('PhysicalWellnessController.onForeground', () {
    test('retries the durable queue and refreshes the dashboard', () async {
      final api = StubPhysicalWellnessApi()
        ..todayBody = todayJson(stepsValue: 4200)
        ..syncError = const NetworkFailure('offline');
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      await ctrl.syncNow();
      // Pairing's automatic batch plus the manual one, both stuck offline.
      expect(cache.queue, hasLength(2));

      // Still offline: the batches survive the resume.
      await ctrl.onForeground();
      expect(cache.queue, hasLength(2));

      // Back online: the resume drains it and refreshes today.
      api.syncError = null;
      await ctrl.onForeground();

      expect(cache.queue, isEmpty);
      expect(ctrl.pendingBatches, 0);
      expect(ctrl.today?.steps.value, 4200);
    });
  });
  group('PhysicalWellnessController.forgetDevice', () {
    test('disconnects the GATT session before clearing state', () async {
      final api = StubPhysicalWellnessApi();
      final gateway = FakeWearableGateway();
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      expect(ctrl.device, isNotNull);

      await ctrl.forgetDevice();

      expect(gateway.disconnectCalls, hasLength(1));
      expect(ctrl.device, isNull);
      expect(cache.device, isNull);
      expect(api.deletedDevices, contains('dev-1'));
    });
  });

  group('offline cache queue', () {
    test('batches survive a fresh cache instance round-trip', () async {
      // PhysicalJsonCache is exercised only when SharedPreferences exists;
      // here we verify the queue contract the controller relies on.
      final cache = FakePhysicalLocalCache();
      await cache.enqueueBatch({'clientSyncId': 'c-1', 'deviceId': 'dev-1'});
      await cache.enqueueBatch({'clientSyncId': 'c-2', 'deviceId': 'dev-1'});

      expect(await cache.readQueue(), hasLength(2));

      await cache.removeBatch('c-1');
      final remaining = await cache.readQueue();
      expect(remaining, hasLength(1));
      expect(remaining.single['clientSyncId'], 'c-2');
    });
  });

  group('Device display names', () {
    test('a manufacturer that prefixes the model is not repeated', () {
      final device = WearableDevice.fromJson(const {
        'id': 'dev-1',
        'provider': 'FITPRO',
        'deviceIdentifier': 'AA:BB:CC',
        'manufacturer': 'Watch',
        'model': 'Watch 8',
        'connectionStatus': 'CONNECTED',
      });
      expect(device.displayName, 'Watch 8');
    });

    test('a genuine manufacturer is kept', () {
      final device = WearableDevice.fromJson(const {
        'id': 'dev-1',
        'provider': 'FITPRO',
        'deviceIdentifier': 'AA:BB:CC',
        'manufacturer': 'FitPro',
        'model': 'Watch 8',
        'connectionStatus': 'CONNECTED',
      });
      expect(device.displayName, 'FitPro Watch 8');
    });
  });

  group('PhysicalWellnessController live heart rate', () {
    test('saves live samples as device-measured readings and syncs them',
        () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();
      final baseline = api.syncedBatches.length;

      final saved = await ctrl.saveLiveHeartRate([
        LiveHeartRateSample(
          bpm: 68,
          timestamp: DateTime.utc(2026, 10, 26, 12, 0, 1),
          recordedAt: DateTime.utc(2026, 10, 26, 12, 0, 2),
          measurementType: 'DEVICE_MEASURED',
        ),
        LiveHeartRateSample(
          bpm: 71,
          timestamp: DateTime.utc(2026, 10, 26, 12, 0, 3),
          recordedAt: DateTime.utc(2026, 10, 26, 12, 0, 4),
          measurementType: 'DEVICE_MEASURED',
        ),
      ]);

      expect(saved, 2);
      expect(api.syncedBatches, hasLength(baseline + 1));
      final batch = api.syncedBatches.last;
      expect(batch['deviceId'], 'dev-1');
      final readings = (batch['readings'] as List).cast<Map>();
      expect(readings, hasLength(2));
      expect(readings.first['metricType'], 'HEART_RATE');
      expect(readings.first['measurementType'], 'DEVICE_MEASURED');
      expect(readings.first['unit'], 'bpm');
      expect(readings.first['value'], 68.0);
      expect(readings.first['timestamp'], '2026-10-26T12:00:01.000Z');
      expect(cache.queue, isEmpty);
      // The live samples are evidence the optical sensor works, so the
      // capability registry is updated without inventing verification.
      final reported = api.reportedCapabilities
          .expand((entry) => entry)
          .where((entry) => entry['metric'] == 'HEART_RATE')
          .toList();
      expect(reported, isNotEmpty);
      expect(reported.last['supportStatus'], 'SUPPORTED_UNVERIFIED');
      expect(reported.last['supportStatus'], isNot('SUPPORTED_VERIFIED'));
    });

    test('live SpO2 from the same frame is saved and reported', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final ctrl = makeController(
        api: api,
        gateway: gateway,
        cache: FakePhysicalLocalCache(),
      );
      await ctrl.connectDevice();

      final saved = await ctrl.saveLiveHeartRate([
        LiveHeartRateSample(
          bpm: 70,
          spo2: 97,
          timestamp: DateTime.utc(2026, 10, 26, 12, 0, 1),
          recordedAt: DateTime.utc(2026, 10, 26, 12, 0, 2),
        ),
      ]);

      expect(saved, 2);
      final readings = (api.syncedBatches.last['readings'] as List).cast<Map>();
      expect(readings.map((r) => r['metricType']), ['HEART_RATE', 'SPO2']);
      final spo2 = readings.last;
      expect(spo2['value'], 97.0);
      expect(spo2['unit'], '%');
      final reported = api.reportedCapabilities
          .expand((entry) => entry)
          .where((entry) => entry['metric'] == 'SPO2');
      expect(reported, isNotEmpty);
      expect(reported.last['supportStatus'], 'SUPPORTED_UNVERIFIED');
    });

    test('an empty live session is not enqueued', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);
      await ctrl.connectDevice();
      final baseline = api.syncedBatches.length;

      expect(await ctrl.saveLiveHeartRate(const []), isNull);
      expect(api.syncedBatches, hasLength(baseline));
      expect(cache.queue, isEmpty);
    });

    test('without a paired watch the monitor is refused honestly', () async {
      final ctrl = makeController();

      expect(await ctrl.startHeartRateMonitor(), 'Connect your watch first.');
    });

    test('a rejected start command returns an actionable message', () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()
        ..snapshot = watchSnapshot()
        ..startMonitorResult = false;
      final ctrl = makeController(
        api: api,
        gateway: gateway,
        cache: FakePhysicalLocalCache(),
      );
      await ctrl.connectDevice();

      final error = await ctrl.startHeartRateMonitor();
      expect(error, isNotNull);
      expect(error, contains('Could not start live measurement'));
      expect(gateway.startMonitorCalls, 1);
    });
  });

  group('PhysicalWellnessController queue recovery', () {
    Map<String, dynamic> batch(String id, String deviceId) => {
          'clientSyncId': id,
          'deviceId': deviceId,
          'deviceStatus': const {'connectionStatus': 'CONNECTED'},
          'readings': const [
            {
              'metricType': 'HEART_RATE',
              'value': 70,
              'unit': 'bpm',
              'timestamp': '2026-10-26T10:00:00Z',
              'measurementType': 'DEVICE_MEASURED',
            },
          ],
          'dailyActivity': const <dynamic>[],
          'sleepSessions': const <dynamic>[],
          'exerciseSessions': const <dynamic>[],
        };

    test('a permanently rejected batch cannot block later batches', () async {
      final api = StubPhysicalWellnessApi()
        ..syncErrorSelector = ((payload) =>
            payload['clientSyncId'] == 'poison'
                ? const ServerFailure(
                    'Wearable device not found',
                    code: 'HTTP_404',
                  )
                : null);
      final cache = FakePhysicalLocalCache();
      cache.queue.addAll([
        batch('poison', 'dev-1'),
        batch('fresh', 'dev-1'),
      ]);
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.flushQueue();

      // The stale batch is dropped with a notice; the healthy one still goes.
      expect(cache.queue, isEmpty);
      expect(api.syncedBatches.single['clientSyncId'], 'fresh');
      expect(ctrl.pendingBatches, 0);
      expect(ctrl.notice, contains('could not be accepted'));
      expect(ctrl.notice, contains('removed'));
    });

    test('a transient failure keeps the queue intact for a later retry',
        () async {
      final api = StubPhysicalWellnessApi()
        ..syncErrorSelector =
            ((_) => const NetworkFailure('Unable to reach the server.'));
      final cache = FakePhysicalLocalCache();
      cache.queue.addAll([
        batch('one', 'dev-1'),
        batch('two', 'dev-1'),
      ]);
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.flushQueue();

      expect(cache.queue, hasLength(2));
      expect(api.syncedBatches, isEmpty);
      expect(ctrl.pendingBatches, 2);
      expect(ctrl.notice, isNull);
    });

    test('batches from an earlier device registration are discarded',
        () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()..snapshot = watchSnapshot();
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);
      await ctrl.connectDevice();
      cache.queue.addAll([
        batch('stale', 'old-registration'),
        batch('current', 'dev-1'),
      ]);

      await ctrl.flushQueue();

      expect(cache.queue, isEmpty);
      expect(api.syncedBatches.last['clientSyncId'], 'current');
      expect(ctrl.notice, contains('earlier watch registration'));
    });

    test('a battery-only snapshot is never enqueued as a successful sync',
        () async {
      final api = StubPhysicalWellnessApi()..todayBody = todayJson();
      final gateway = FakeWearableGateway()
        ..snapshot = WearableSnapshot(
          deviceIdentifier: 'AA:BB:CC',
          firmwareVersion: 'V15183',
          batteryLevel: 54,
          recordedAt: DateTime.utc(2026, 10, 26, 12),
        );
      final cache = FakePhysicalLocalCache();
      final ctrl = makeController(api: api, gateway: gateway, cache: cache);

      await ctrl.connectDevice();

      expect(api.syncedBatches, isEmpty);
      expect(cache.queue, isEmpty);
      expect(ctrl.pendingBatches, 0);
      // The honest "connected but silent" reason survives pairing.
      expect(ctrl.notice, contains('no new health data'));
    });
  });
}
