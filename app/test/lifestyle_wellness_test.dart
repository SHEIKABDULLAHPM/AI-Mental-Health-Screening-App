import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/core/error/failures.dart';
import 'package:mindease/features/physical_wellness/data/lifestyle_models.dart';
import 'package:mindease/features/physical_wellness/data/physical_local_cache.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_api.dart';
import 'package:mindease/features/physical_wellness/data/physical_wellness_models.dart';
import 'package:mindease/features/physical_wellness/presentation/state/lifestyle_wellness_controller.dart';

// ── Test doubles ──────────────────────────────────────────────────────────

class RecordingLifestyleApi implements PhysicalWellnessApi {
  Map<String, dynamic> hydrationBody = hydrationJson();
  Map<String, dynamic> bodyBody = bodyJson();
  Map<String, dynamic> goalsBody = goalsJson();
  Map<String, dynamic> trendsBody = trendsJson();
  Map<String, dynamic> insightsBody = insightsJson();
  Map<String, dynamic> capabilitiesBody = capabilitiesJson();

  Object? hydrationError;
  Object? bodyError;
  Object? goalsError;
  Object? trendsError;
  Object? insightsError;
  Object? capabilitiesError;
  Object? addHydrationError;
  Object? addBodyError;
  Object? deleteHydrationError;

  final List<Map<String, dynamic>> hydrationAdds = [];
  final List<Map<String, dynamic>> hydrationUpdates = [];
  final List<String> hydrationDeletes = [];
  final List<int> hydrationTargets = [];
  final List<Map<String, dynamic>> bodyAdds = [];
  final List<Map<String, dynamic>> goalUpdates = [];
  final List<List<Map<String, dynamic>>> aiGoalUpdates = [];
  int hydrationReads = 0;
  int goalsReads = 0;

  void _throwIfSet(Object? error) {
    if (error != null) throw error;
  }

  @override
  Future<Map<String, dynamic>> getHydration({int? days}) async {
    hydrationReads++;
    _throwIfSet(hydrationError);
    return hydrationBody;
  }

  @override
  Future<Map<String, dynamic>> addHydration({
    required double amount,
    String? unit,
    DateTime? timestamp,
  }) async {
    _throwIfSet(addHydrationError);
    hydrationAdds.add({
      'amount': amount,
      'unit': unit,
      'timestamp': timestamp?.toUtc().toIso8601String(),
    });
    return {
      'id': 'e-new',
      'date': '2026-10-25',
      'amountMl': amount,
      'timestamp': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
      'source': 'USER_ENTERED',
    };
  }

  @override
  Future<Map<String, dynamic>> updateHydration(
    String entryId, {
    required double amount,
    String? unit,
    DateTime? timestamp,
  }) async {
    hydrationUpdates.add({'id': entryId, 'amount': amount, 'unit': unit});
    return {
      'id': entryId,
      'date': '2026-10-25',
      'amountMl': amount,
      'timestamp': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
      'source': 'USER_ENTERED',
    };
  }

  @override
  Future<void> deleteHydration(String entryId) async {
    _throwIfSet(deleteHydrationError);
    hydrationDeletes.add(entryId);
  }

  @override
  Future<Map<String, dynamic>> updateHydrationTarget(int targetMl) async {
    hydrationTargets.add(targetMl);
    return hydrationBody;
  }

  @override
  Future<Map<String, dynamic>> getBody({int? limit}) async {
    _throwIfSet(bodyError);
    return bodyBody;
  }

  @override
  Future<Map<String, dynamic>> addBodyMeasurement({
    double? weight,
    double? height,
    String? weightUnit,
    String? heightUnit,
    DateTime? measuredAt,
  }) async {
    _throwIfSet(addBodyError);
    bodyAdds.add({
      'weight': weight,
      'height': height,
      'weightUnit': weightUnit,
      'heightUnit': heightUnit,
      'measuredAt': measuredAt?.toUtc().toIso8601String(),
    });
    return const {};
  }

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
  Future<Map<String, dynamic>> getGoals() async {
    goalsReads++;
    _throwIfSet(goalsError);
    return goalsBody;
  }

  @override
  Future<Map<String, dynamic>> updateGoals(Map<String, dynamic> targets) async {
    _throwIfSet(goalsError);
    goalUpdates.add(Map<String, dynamic>.from(targets));
    return goalsBody;
  }

  @override
  Future<Map<String, dynamic>> applyAiGoalRecommendations(
      List<Map<String, dynamic>> recommendations) async {
    _throwIfSet(goalsError);
    aiGoalUpdates.add(recommendations);
    return {
      'goals': goalsBody,
      'applied': [for (final r in recommendations) '${r['metric']}=${r['value']}'],
      'skipped': const [],
    };
  }

  @override
  Future<Map<String, dynamic>> getTrends({int? days}) async {
    _throwIfSet(trendsError);
    return trendsBody;
  }

  @override
  Future<Map<String, dynamic>> getInsights() async {
    _throwIfSet(insightsError);
    return insightsBody;
  }

  @override
  Future<Map<String, dynamic>> getCapabilities(String deviceId) async {
    _throwIfSet(capabilitiesError);
    return capabilitiesBody;
  }

  @override
  Future<Map<String, dynamic>> reportCapabilities(
    String deviceId,
    List<Map<String, dynamic>> capabilities,
  ) async =>
      capabilitiesBody;

  // Not exercised by these tests.
  @override
  Future<Map<String, dynamic>> registerDevice({
    required String provider,
    required String deviceIdentifier,
    String? manufacturer,
    String? model,
    String? firmwareVersion,
    List<String>? capabilities,
    int? batteryLevel,
  }) async =>
      const {};

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
  Future<void> deleteDevice(String deviceId) async {}

  @override
  Future<Map<String, dynamic>> getPhysicalToday() async => const {};

  @override
  Future<Map<String, dynamic>> getPhysicalActivity({int? days}) async =>
      const {};

  @override
  Future<Map<String, dynamic>> getPhysicalHeartRate({int? hours}) async =>
      const {};

  @override
  Future<Map<String, dynamic>> getPhysicalSleep({int? limit}) async =>
      const {};

  @override
  Future<Map<String, dynamic>> getPhysicalExercise({int? limit}) async =>
      const {};

  @override
  Future<Map<String, dynamic>> getPhysicalSummary() async => const {};

  @override
  Future<Map<String, dynamic>> syncPhysical(Map<String, dynamic> payload) async =>
      const {};
}

class MemoryLifestyleCache implements PhysicalLocalCache {
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
  Future<List<Map<String, dynamic>>> readQueue() async => List.unmodifiable(queue);
  @override
  Future<void> enqueueBatch(Map<String, dynamic> batch) async => queue.add(batch);
  @override
  Future<void> removeBatch(String clientSyncId) async =>
      queue.removeWhere((b) => b['clientSyncId'] == clientSyncId);
  @override
  Future<HydrationOverview?> readHydration() async => hydration;
  @override
  Future<void> writeHydration(HydrationOverview value) async => hydration = value;
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
    hydration = null;
    body = null;
    goals = null;
    trends = null;
    insights = null;
    capabilities = null;
    mutations.clear();
    queue.clear();
  }
}

// ── Payload builders ──────────────────────────────────────────────────────

Map<String, dynamic> entryJson({
  String id = 'e1',
  double amountMl = 250,
  String timestamp = '2026-10-25T08:00:00Z',
}) =>
    {
      'id': id,
      'date': '2026-10-25',
      'amountMl': amountMl,
      'timestamp': timestamp,
      'source': 'USER_ENTERED',
    };

Map<String, dynamic> hydrationJson({
  double total = 500,
  int entryCount = 2,
  List<Map<String, dynamic>> entries = const [],
  int target = 2000,
  bool customized = false,
}) =>
    {
      'unit': 'ml',
      'targetMl': target,
      'targetCustomized': customized,
      'today': {
        'date': '2026-10-25',
        'totalMl': total,
        'entryCount': entryCount,
        'entries': entries,
      },
      'days': entryCount == 0
          ? <Map<String, dynamic>>[]
          : [
              {
                'date': '2026-10-25',
                'totalMl': total,
                'entryCount': entryCount,
                'entries': entries,
              },
            ],
      'guidance': 'Hydration needs vary with activity and climate.',
    };

Map<String, dynamic> bodyJson({double? weightKg = 74.5, double? bmi = 23.0}) =>
    {
      'weightUnit': 'kg',
      'heightUnit': 'cm',
      'latest': weightKg == null
          ? null
          : {
              'id': 'm1',
              'date': '2026-10-24',
              'weightKg': weightKg,
              'heightCm': null,
              'measuredAt': '2026-10-24T07:00:00Z',
              'source': 'USER_ENTERED',
              'deviceId': null,
            },
      'bmi': bmi == null
          ? null
          : {
              'value': bmi,
              'category': 'REFERENCE_RANGE',
              'label': 'Within the reference range',
              'disclaimer':
                  'BMI is a limited screening measure. It is not a diagnosis.',
              'weightKg': weightKg,
              'heightCm': 180.0,
              'calculatedFrom': '2026-10-24T07:00:00Z',
            },
      'trend': {
        'latestKg': weightKg,
        'previousKg': 76.0,
        'changeKg': -1.5,
        'daysWithData': 2,
        'windowDays': 30,
      },
      'history': weightKg == null
          ? <dynamic>[]
          : [
              {
                'id': 'm1',
                'date': '2026-10-24',
                'weightKg': weightKg,
                'heightCm': null,
                'measuredAt': '2026-10-24T07:00:00Z',
                'source': 'USER_ENTERED',
                'deviceId': null,
              },
            ],
      'limitations': [
        'Body-fat percentage and muscle mass are not shown.',
      ],
    };

Map<String, dynamic> goalsJson({
  int? steps,
  int? water,
  bool customized = false,
}) =>
    {
      'goals': {
        'dailySteps': steps,
        'dailyActiveMinutes': null,
        'weeklyWorkoutMinutes': null,
        'dailySleepMinutes': null,
        'dailyHydrationMl': water,
      },
      'customized': customized,
      'progress': [
        {
          'metric': 'steps',
          'label': 'Steps',
          'unit': 'steps',
          'period': 'today',
          'target': steps,
          'current': steps == null ? null : 6000.0,
          'remaining': steps == null ? null : 2000.0,
          'progress': steps == null ? null : 0.75,
          'met': steps == null ? null : false,
          'dataAvailable': steps != null,
          'source': 'WEARABLE',
          'note': steps == null ? 'No step target set.' : null,
        },
      ],
      'streaks': {
        'hydration': {
          'metric': 'hydration',
          'currentStreak': 2,
          'longestStreak': 3,
          'daysEvaluated': 7,
          'daysWithData': 5,
          'note': 'Excludes today in progress.',
        },
      },
      'suggestedDefaults': {
        'dailySteps': 7000,
        'dailyActiveMinutes': 30,
        'weeklyWorkoutMinutes': 120,
        'dailySleepMinutes': 480,
        'dailyHydrationMl': 2000,
      },
      'guidance': ['Goals are personal starting points, not medical advice.'],
    };

Map<String, dynamic> trendsJson() => {
      'from': '2026-10-19',
      'to': '2026-10-25',
      'windowDays': 7,
      'previousWindowDays': 7,
      'metrics': [
        {
          'metric': 'steps',
          'label': 'Steps',
          'unit': 'steps',
          'aggregation': 'daily_total',
          'points': [
            {'date': '2026-10-23', 'value': 4000.0, 'source': 'WEARABLE'},
            {'date': '2026-10-25', 'value': 6000.0, 'source': 'WEARABLE'},
          ],
          'average': 5000.0,
          'previousAverage': 4500.0,
          'changePercent': 11.0,
          'daysWithData': 2,
          'windowDays': 7,
          'quality': 'DEVICE_MEASURED',
          'note': null,
        },
        {
          'metric': 'hrv',
          'label': 'HRV',
          'unit': 'ms',
          'aggregation': 'daily_average',
          'points': <dynamic>[],
          'average': null,
          'previousAverage': null,
          'changePercent': null,
          'daysWithData': 0,
          'windowDays': 7,
          'quality': null,
          'note': 'Only present when the device provides it.',
        },
      ],
      'coverageNotes': ['Steps: 2 of 7 days.'],
    };

Map<String, dynamic> insightsJson({bool aiEnhanced = false}) => {
      'generatedAt': '2026-10-25T09:00:00Z',
      'windowDays': 14,
      'sufficientData': true,
      'insights': [
        {
          'id': 'sleep_below_baseline',
          'title': 'Sleep is shorter than your baseline',
          'summary': 'Recent nights are shorter than the weeks before.',
          'severity': 'ATTENTION',
          'confidence': 'MEDIUM',
          'evidence': [
            {
              'source': 'SLEEP',
              'metric': 'sleep_duration',
              'current': 360.0,
              'baseline': 480.0,
              'unit': 'min',
              'windowDays': 14,
              'coverageDays': 9,
              'comparison': 'below_baseline',
            },
          ],
          'coverage': {
            'windowDays': 14,
            'daysWithActivity': 10,
            'daysWithSleep': 9,
            'daysWithHydration': 5,
            'moodCheckins': 6,
            'heartRateDays': 4,
            'missingSources': <dynamic>[],
          },
          'disclaimer': 'Patterns are descriptive and cannot show cause.',
        },
      ],
      'recommendations': [
        {
          'id': 'sleep_wind_down',
          'title': 'Keep a wind-down routine',
          'description': 'A consistent routine may support sleep.',
          'category': 'SLEEP',
          'source': 'RULE_ENGINE',
        },
      ],
      'aiEnhanced': aiEnhanced,
      'coverage': {
        'windowDays': 14,
        'daysWithActivity': 10,
        'daysWithSleep': 9,
        'daysWithHydration': 5,
        'moodCheckins': 6,
        'heartRateDays': 4,
        'missingSources': ['SPO2'],
      },
      'limitations': ['Weight is intentionally excluded from patterns.'],
      'disclaimer': 'Patterns are descriptive and cannot show cause.',
    };

Map<String, dynamic> capabilitiesJson() => {
      'deviceId': 'dev-1',
      'deviceModel': 'Watch 8',
      'firmwareVersion': 'V15183',
      'capabilities': [
        {
          'metric': 'STEPS',
          'label': 'Steps',
          'unit': 'steps',
          'supportStatus': 'SUPPORTED_UNVERIFIED',
          'retrievalMethod': 'VENDOR_PROTOCOL',
          'verificationStatus': 'UNVERIFIED',
          'limitations': 'Not yet confirmed against the vendor app.',
          'lastVerifiedAt': null,
          'updatedAt': '2026-10-25T09:00:00Z',
        },
        {
          'metric': 'SPO2',
          'label': 'Blood oxygen (SpO2)',
          'unit': '%',
          'supportStatus': 'UNSUPPORTED',
          'retrievalMethod': 'NONE',
          'verificationStatus': 'NOT_SUPPORTED',
          'limitations': 'The SpO2 byte semantics are unverified.',
          'lastVerifiedAt': null,
          'updatedAt': '2026-10-25T09:00:00Z',
        },
      ],
      'notes': ['No capability has been verified on this firmware.'],
    };

LifestyleWellnessController makeController({
  RecordingLifestyleApi? api,
  MemoryLifestyleCache? cache,
}) =>
    LifestyleWellnessController(
      api ?? RecordingLifestyleApi(),
      cache: cache ?? MemoryLifestyleCache(),
    );

void main() {
  group('HydrationOverview parsing', () {
    test('totals, target and progress are derived from real entries', () {
      final value = HydrationOverview.fromJson(hydrationJson());

      expect(value.today.totalMl, 500);
      expect(value.targetMl, 2000);
      expect(value.progress, 0.25);
      expect(value.remainingMl, 1500);
      expect(value.today.hasEntries, isTrue);
    });

    test('a day with no entries is not treated as a measured zero', () {
      final value = HydrationOverview.fromJson(
        hydrationJson(total: 0, entryCount: 0),
      );

      expect(value.today.hasEntries, isFalse);
      expect(value.days, isEmpty);
    });

    test('over-target progress is capped, never above 100%', () {
      final value = HydrationOverview.fromJson(
        hydrationJson(total: 4000, entryCount: 3),
      );

      expect(value.progress, 1.0);
      expect(value.remainingMl, 0);
    });

    test('round-trips through the cache encoding', () {
      final original = HydrationOverview.fromJson(hydrationJson());
      final restored = HydrationOverview.fromJson(original.toJson());

      expect(restored.today.totalMl, original.today.totalMl);
      expect(restored.targetMl, original.targetMl);
    });
  });

  group('Body / goals / trends / insights models', () {
    test('BMI keeps its disclaimer and inputs', () {
      final value = BodySummary.fromJson(bodyJson());

      expect(value.bmi!.value, 23.0);
      expect(value.bmi!.disclaimer.toLowerCase(), contains('not a diagnosis'));
      expect(value.bmi!.heightCm, 180.0);
      expect(value.trend.changeKg, -1.5);
    });

    test('BMI is null when no verified inputs exist', () {
      final value = BodySummary.fromJson(bodyJson(bmi: null));
      expect(value.bmi, isNull);
    });

    test('the BMI disclaimer is not repeated by the limitations list', () {
      final json = bodyJson();
      final disclaimer = (json['bmi'] as Map)['disclaimer'];
      // The real server includes the same sentence in both places.
      json['limitations'] = [
        disclaimer,
        'Body-fat percentage and muscle mass are not shown.',
      ];

      final value = BodySummary.fromJson(json);

      expect(value.limitations, hasLength(2));
      expect(value.additionalLimitations, hasLength(1));
      expect(value.additionalLimitations.single, contains('Body-fat'));
    });

    test('limitations survive when there is no BMI', () {
      final json = bodyJson(bmi: null);
      json['limitations'] = [
        'Body-fat percentage and muscle mass are not shown.',
      ];

      final value = BodySummary.fromJson(json);

      expect(value.additionalLimitations, hasLength(1));
    });

    test('goal targets stay null and suggestions stay separate', () {
      final value = GoalsOverview.fromJson(goalsJson());

      expect(value.customized, isFalse);
      expect(value.goals.dailySteps, isNull);
      expect(value.goals.isEmpty, isTrue);
      expect(value.suggestedDefaults.dailySteps, 7000);
      expect(value.progress.single.dataAvailable, isFalse);
      expect(value.streaks['hydration']!.currentStreak, 2);
    });

    test('trend points only include recorded days', () {
      final value = TrendsOverview.fromJson(trendsJson());
      final steps = value.metrics.first;

      expect(steps.points, hasLength(2));
      expect(steps.daysWithData, 2);
      expect(steps.windowDays, 7);
      expect(value.metrics.last.hasData, isFalse);
    });

    test('insights carry evidence, coverage and provenance', () {
      final value = InsightsOverview.fromJson(
        insightsJson(aiEnhanced: false),
      );

      expect(value.sufficientData, isTrue);
      expect(value.insights.single.evidence.single.baseline, 480.0);
      expect(value.insights.single.disclaimer, contains('cannot show cause'));
      expect(value.recommendations.single.source, 'RULE_ENGINE');
      expect(value.aiEnhanced, isFalse);
    });

    test('capabilities are never verified unless the server says so', () {
      final value = CapabilityList.fromJson(capabilitiesJson());

      final steps = value.find('STEPS')!;
      final spo2 = value.find('SPO2')!;
      expect(steps.isSupported, isTrue);
      expect(steps.isVerified, isFalse);
      expect(spo2.isSupported, isFalse);
      expect(spo2.limitations, contains('unverified'));
    });

    test('pending mutation survives the cache encoding', () {
      final original = PendingMutation(
        id: 'm-1',
        type: PendingMutationType.hydrationAdd,
        payload: const {'amount': 250, 'timestamp': '2026-10-25T08:00:00Z'},
        createdAt: DateTime.utc(2026, 10, 25, 8),
      );
      final restored = PendingMutation.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.type, PendingMutationType.hydrationAdd);
      expect(restored.payload['amount'], 250);
    });
  });

  group('LifestyleWellnessController reads', () {
    test('init paints from cache before the network responds', () async {
      final cache = MemoryLifestyleCache()
        ..hydration = HydrationOverview.fromJson(hydrationJson(total: 250));
      final api = RecordingLifestyleApi()
        ..hydrationError = const NetworkFailure('offline');
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.init();

      expect(ctrl.hydration?.today.totalMl, 250);
      expect(ctrl.offline, isTrue);
      expect(ctrl.staleSections, contains('hydration'));
    });

    test('a failed section without cache surfaces an error', () async {
      final api = RecordingLifestyleApi()
        ..hydrationError = const NetworkFailure('down');
      final ctrl = makeController(api: api);

      await ctrl.init();

      expect(ctrl.hydration, isNull);
      expect(ctrl.error, isNotNull);
    });

    test('successful reads populate every section and clear stale flags', () async {
      final ctrl = makeController();

      await ctrl.init(deviceId: 'dev-1');

      expect(ctrl.hydration, isNotNull);
      expect(ctrl.body, isNotNull);
      expect(ctrl.goals, isNotNull);
      expect(ctrl.trends, isNotNull);
      expect(ctrl.insights, isNotNull);
      expect(ctrl.capabilities?.deviceId, 'dev-1');
      expect(ctrl.staleSections, isEmpty);
      expect(ctrl.offline, isFalse);
    });

    test('capabilities are skipped without a device id', () async {
      final api = RecordingLifestyleApi();
      final ctrl = makeController(api: api);

      await ctrl.init();

      expect(ctrl.capabilities, isNull);
    });
  });

  group('LifestyleWellnessController writes', () {
    test('a confirmed drink updates the view and does not queue', () async {
      final api = RecordingLifestyleApi();
      final cache = MemoryLifestyleCache();
      final ctrl = makeController(api: api, cache: cache);

      final ok = await ctrl.addHydration(300, unit: 'ml');

      expect(ok, isTrue);
      expect(api.hydrationAdds.single['amount'], 300);
      expect(cache.mutations, isEmpty);
      expect(ctrl.pendingCount, 0);
      expect(ctrl.notice, contains('Logged'));
    });

    test('an offline drink is queued, not reported as saved', () async {
      final api = RecordingLifestyleApi()
        ..addHydrationError = const NetworkFailure('offline');
      final cache = MemoryLifestyleCache();
      final ctrl = makeController(api: api, cache: cache);

      final ok = await ctrl.addHydration(500, unit: 'ml');

      expect(ok, isFalse);
      expect(cache.mutations, hasLength(1));
      expect(cache.mutations.single.type, PendingMutationType.hydrationAdd);
      expect(ctrl.pendingCount, 1);
      expect(ctrl.notice, contains('waiting to sync'));
      expect(ctrl.notice, isNot(contains('Logged')));
    });

    test('a validation rejection is shown, never queued', () async {
      final api = RecordingLifestyleApi()
        ..addHydrationError =
            const ServerFailure('a single entry cannot exceed 5000 ml',
                code: 'HTTP_400');
      final cache = MemoryLifestyleCache();
      final ctrl = makeController(api: api, cache: cache);

      final ok = await ctrl.addHydration(9000, unit: 'ml');

      expect(ok, isFalse);
      expect(cache.mutations, isEmpty);
      expect(ctrl.notice, contains('5000'));
    });

    test('double taps cannot submit two drinks', () async {
      final api = RecordingLifestyleApi();
      final ctrl = makeController(api: api);

      final results = await Future.wait([
        ctrl.addHydration(250, unit: 'ml'),
        ctrl.addHydration(250, unit: 'ml'),
      ]);

      expect(results.where((ok) => ok), hasLength(1));
      expect(api.hydrationAdds, hasLength(1));
    });

    test('deleting an already-removed entry is treated as success', () async {
      final api = RecordingLifestyleApi()
        ..deleteHydrationError =
            const ServerFailure('Hydration entry not found', code: 'HTTP_404');
      final cache = MemoryLifestyleCache();
      final ctrl = makeController(api: api, cache: cache);

      final ok = await ctrl.deleteHydration('e1');

      expect(ok, isTrue);
      expect(cache.mutations, isEmpty);
    });

    test('saving goals forwards every field, including cleared ones', () async {
      final api = RecordingLifestyleApi();
      final ctrl = makeController(api: api);

      final ok = await ctrl.saveGoals(
        const GoalTargets(dailySteps: 9000, dailyHydrationMl: 2500),
      );

      expect(ok, isTrue);
      expect(api.goalUpdates.single, {
        'dailySteps': 9000,
        'dailyActiveMinutes': null,
        'weeklyWorkoutMinutes': null,
        'dailySleepMinutes': null,
        'dailyHydrationMl': 2500,
      });
    });

    test('an offline goal change is queued with the exact payload', () async {
      final api = RecordingLifestyleApi()
        ..goalsError = const NetworkFailure('offline');
      final cache = MemoryLifestyleCache();
      final ctrl = makeController(api: api, cache: cache);

      final ok = await ctrl.saveGoals(const GoalTargets(dailySteps: 8000));

      expect(ok, isFalse);
      expect(cache.mutations.single.type, PendingMutationType.goalsUpdate);
      expect(cache.mutations.single.payload['dailySteps'], 8000);
    });

    test('body measurement offline is queued with its measuring time', () async {
      final api = RecordingLifestyleApi()
        ..addBodyError = const NetworkFailure('offline');
      final cache = MemoryLifestyleCache();
      final ctrl = makeController(api: api, cache: cache);

      final ok = await ctrl.addBodyMeasurement(weight: 74, weightUnit: 'kg');

      expect(ok, isFalse);
      expect(cache.mutations.single.type, PendingMutationType.bodyAdd);
      expect(cache.mutations.single.payload['measuredAt'], isNotNull);
    });
  });

  group('LifestyleWellnessController.flushMutations', () {
    test('replays a queued drink once and clears the journal', () async {
      final api = RecordingLifestyleApi();
      final cache = MemoryLifestyleCache()
        ..mutations.add(
          PendingMutation(
            id: 'm-1',
            type: PendingMutationType.hydrationAdd,
            payload: const {
              'amount': 250,
              'unit': 'ml',
              'timestamp': '2026-10-25T08:00:00Z',
            },
            createdAt: DateTime.utc(2026, 10, 25, 8),
          ),
        );
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.flushMutations();

      expect(api.hydrationAdds, hasLength(1));
      expect(cache.mutations, isEmpty);
      expect(ctrl.pendingCount, 0);
    });

    test('does not duplicate a write whose acknowledgement was lost', () async {
      final api = RecordingLifestyleApi()
        ..hydrationBody = hydrationJson(
          entries: [
            entryJson(timestamp: '2026-10-25T08:00:00Z'),
          ],
        );
      final cache = MemoryLifestyleCache()
        ..mutations.add(
          PendingMutation(
            id: 'm-1',
            type: PendingMutationType.hydrationAdd,
            payload: const {
              'amount': 250,
              'unit': 'ml',
              'timestamp': '2026-10-25T08:00:00Z',
            },
            createdAt: DateTime.utc(2026, 10, 25, 8),
          ),
        );
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.flushMutations();

      expect(api.hydrationAdds, isEmpty);
      expect(cache.mutations, isEmpty);
      expect(ctrl.pendingCount, 0);
    });

    test('stops on a retryable failure and keeps the journal intact', () async {
      final api = RecordingLifestyleApi()
        ..addHydrationError = const NetworkFailure('still offline');
      final cache = MemoryLifestyleCache()
        ..mutations.add(
          PendingMutation(
            id: 'm-1',
            type: PendingMutationType.hydrationAdd,
            payload: const {
              'amount': 250,
              'unit': 'ml',
              'timestamp': '2026-10-25T08:00:00Z',
            },
            createdAt: DateTime.utc(2026, 10, 25, 8),
          ),
        );
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.flushMutations();

      expect(cache.mutations, hasLength(1));
      expect(ctrl.pendingCount, 1);
    });

    test('drops a permanently rejected write so the queue cannot wedge', () async {
      final api = RecordingLifestyleApi()
        ..addHydrationError =
            const ServerFailure('amount must be at least 1', code: 'HTTP_400');
      final cache = MemoryLifestyleCache()
        ..mutations.add(
          PendingMutation(
            id: 'm-1',
            type: PendingMutationType.hydrationAdd,
            payload: const {
              'amount': 0,
              'unit': 'ml',
              'timestamp': '2026-10-25T08:00:00Z',
            },
            createdAt: DateTime.utc(2026, 10, 25, 8),
          ),
        );
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.flushMutations();

      expect(cache.mutations, isEmpty);
      expect(ctrl.lastSyncError, contains('could not be applied'));
      expect(ctrl.pendingCount, 0);
    });

    test('hydrating a target replays as an integer', () async {
      final api = RecordingLifestyleApi();
      final cache = MemoryLifestyleCache()
        ..mutations.add(
          PendingMutation(
            id: 'm-1',
            type: PendingMutationType.hydrationTarget,
            payload: const {'targetMl': 2600},
            createdAt: DateTime.utc(2026, 10, 25, 8),
          ),
        );
      final ctrl = makeController(api: api, cache: cache);

      await ctrl.flushMutations();

      expect(api.hydrationTargets, [2600]);
      expect(cache.mutations, isEmpty);
    });
  });

  group('Lifestyle cache round-trip', () {
    test('lifestyle views and mutations survive the JSON encoding', () async {
      // The real PhysicalJsonCache is exercised through its encode/decode
      // contract without a platform plugin: each model must round-trip.
      final hydration = HydrationOverview.fromJson(hydrationJson());
      final restored = HydrationOverview.fromJson(hydration.toJson());
      expect(restored.toJson(), hydration.toJson());

      final goals = GoalsOverview.fromJson(goalsJson(steps: 8000, water: 2200));
      expect(GoalsOverview.fromJson(goals.toJson()).toJson(), goals.toJson());

      final insights = InsightsOverview.fromJson(insightsJson());
      expect(
        InsightsOverview.fromJson(insights.toJson()).toJson(),
        insights.toJson(),
      );
    });

    test('clearing the cache also clears lifestyle data and mutations', () async {
      final cache = MemoryLifestyleCache()
        ..hydration = HydrationOverview.fromJson(hydrationJson())
        ..mutations.add(
          PendingMutation(
            id: 'm-1',
            type: PendingMutationType.hydrationAdd,
            payload: const {'amount': 250},
            createdAt: DateTime.utc(2026, 10, 25),
          ),
        );

      await cache.clearAll();

      expect(cache.hydration, isNull);
      expect(cache.mutations, isEmpty);
    });
  });
}
