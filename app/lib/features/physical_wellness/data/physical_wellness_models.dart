import 'package:flutter/foundation.dart';

/// Parsed UTC instant; returns null for missing/invalid values.
DateTime? _time(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

double? _double(Object? value) =>
    value == null ? null : (value as num?)?.toDouble();

int? _int(Object? value) => value == null ? null : (value as num?)?.toInt();

int? _long(Object? value) => value == null ? null : (value as num?)?.toInt();

String? _string(Object? value) => value?.toString();

/// Three-state metric rendered on the dashboard.
///
/// * `supported == false` — the device does not expose this metric;
/// * `supported == true, value == null` — supported, but no data yet;
/// * `value != null` — real data (a genuine zero renders as `0`).
@immutable
class MetricBlock {
  const MetricBlock({
    required this.supported,
    required this.unit,
    this.value,
    this.updatedAt,
  });

  final bool supported;
  final double? value;
  final String unit;
  final DateTime? updatedAt;

  factory MetricBlock.fromJson(Map<String, dynamic> json) => MetricBlock(
        supported: json['supported'] as bool? ?? false,
        value: _double(json['value']),
        unit: json['unit'] as String? ?? '',
        updatedAt: _time(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'supported': supported,
        'value': value,
        'unit': unit,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };
}

@immutable
class DeviceBlock {
  const DeviceBlock({
    required this.id,
    required this.provider,
    required this.connectionStatus,
    this.manufacturer,
    this.model,
    this.firmwareVersion,
    this.batteryLevel,
    this.charging,
    this.lastSyncedAt,
  });

  final String id;
  final String provider;
  final String? manufacturer;
  final String? model;
  final String? firmwareVersion;
  final String connectionStatus;
  final int? batteryLevel;
  final bool? charging;
  final DateTime? lastSyncedAt;

  String get displayName {
    final manufacturer = this.manufacturer;
    final model = this.model;
    if (manufacturer != null &&
        manufacturer.isNotEmpty &&
        model != null &&
        model.isNotEmpty) {
      // A scan name like "Watch 8" yields manufacturer "Watch"; repeating it
      // would render "Watch Watch 8".
      if (model.toLowerCase().startsWith('${manufacturer.toLowerCase()} ')) {
        return model;
      }
      return '$manufacturer $model';
    }
    return model ?? manufacturer ?? 'Watch';
  }

  factory DeviceBlock.fromJson(Map<String, dynamic> json) => DeviceBlock(
        id: json['id'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        manufacturer: _string(json['manufacturer']),
        model: _string(json['model']),
        firmwareVersion: _string(json['firmwareVersion']),
        connectionStatus: json['connectionStatus'] as String? ?? 'UNKNOWN',
        batteryLevel: _int(json['batteryLevel']),
        charging: json['charging'] as bool?,
        lastSyncedAt: _time(json['lastSyncedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider,
        'manufacturer': manufacturer,
        'model': model,
        'firmwareVersion': firmwareVersion,
        'connectionStatus': connectionStatus,
        'batteryLevel': batteryLevel,
        'charging': charging,
        'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
      };
}

@immutable
class HeartRateBlock {
  const HeartRateBlock({
    required this.supported,
    required this.unit,
    this.latest,
    this.averageToday,
    this.resting,
    this.updatedAt,
  });

  final bool supported;
  final double? latest;
  final double? averageToday;
  final double? resting;
  final String unit;
  final DateTime? updatedAt;

  factory HeartRateBlock.fromJson(Map<String, dynamic> json) => HeartRateBlock(
        supported: json['supported'] as bool? ?? false,
        latest: _double(json['latest']),
        averageToday: _double(json['averageToday']),
        resting: _double(json['resting']),
        unit: json['unit'] as String? ?? 'bpm',
        updatedAt: _time(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'supported': supported,
        'latest': latest,
        'averageToday': averageToday,
        'resting': resting,
        'unit': unit,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };
}

@immutable
class SleepBlock {
  const SleepBlock({
    required this.supported,
    this.durationMillis,
    this.bedtime,
    this.wakeTime,
    this.date,
    this.updatedAt,
    this.stageMinutes = const {},
    this.stageSource,
  });

  final bool supported;
  final int? durationMillis;
  final DateTime? bedtime;
  final DateTime? wakeTime;
  final String? date;
  final DateTime? updatedAt;

  /// Source-native stage minutes keyed by the label the device reported
  /// (e.g. `RAW_1`). Empty when the device reports no stages — stages are
  /// never inferred from total sleep.
  final Map<String, int> stageMinutes;

  /// Where [stageMinutes] came from (e.g. `FITPRO_RAW`).
  final String? stageSource;

  bool get hasStages => stageMinutes.isNotEmpty;

  factory SleepBlock.fromJson(Map<String, dynamic> json) => SleepBlock(
        supported: json['supported'] as bool? ?? false,
        durationMillis: _long(json['durationMillis']),
        bedtime: _time(json['bedtime']),
        wakeTime: _time(json['wakeTime']),
        date: _string(json['date']),
        updatedAt: _time(json['updatedAt']),
        stageMinutes: {
          for (final entry
              in ((json['stageMinutes'] as Map?) ?? const {}).entries)
            entry.key.toString(): _int(entry.value) ?? 0,
        },
        stageSource: _string(json['stageSource']),
      );

  Map<String, dynamic> toJson() => {
        'supported': supported,
        'durationMillis': durationMillis,
        'bedtime': bedtime?.toUtc().toIso8601String(),
        'wakeTime': wakeTime?.toUtc().toIso8601String(),
        'date': date,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'stageMinutes': stageMinutes,
        'stageSource': stageSource,
      };
}

@immutable
class ExerciseBlock {
  const ExerciseBlock({
    required this.supported,
    this.durationMillis,
    this.sessionCount = 0,
    this.updatedAt,
  });

  final bool supported;
  final int? durationMillis;
  final int sessionCount;
  final DateTime? updatedAt;

  factory ExerciseBlock.fromJson(Map<String, dynamic> json) => ExerciseBlock(
        supported: json['supported'] as bool? ?? false,
        durationMillis: _long(json['durationMillis']),
        sessionCount: _int(json['sessionCount']) ?? 0,
        updatedAt: _time(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'supported': supported,
        'durationMillis': durationMillis,
        'sessionCount': sessionCount,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };
}

@immutable
class SyncBlock {
  const SyncBlock({
    this.lastSyncedAt,
    this.lastAttemptedAt,
    this.lastStatus,
    this.lastError,
  });

  final DateTime? lastSyncedAt;
  final DateTime? lastAttemptedAt;
  final String? lastStatus;
  final String? lastError;

  factory SyncBlock.fromJson(Map<String, dynamic> json) => SyncBlock(
        lastSyncedAt: _time(json['lastSyncedAt']),
        lastAttemptedAt: _time(json['lastAttemptedAt']),
        lastStatus: _string(json['lastStatus']),
        lastError: _string(json['lastError']),
      );

  Map<String, dynamic> toJson() => {
        'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
        'lastAttemptedAt': lastAttemptedAt?.toUtc().toIso8601String(),
        'lastStatus': lastStatus,
        'lastError': lastError,
      };
}

/// The "today" payload the Physical Wellness dashboard renders.
@immutable
class PhysicalToday {
  const PhysicalToday({
    required this.date,
    required this.steps,
    required this.distance,
    required this.calories,
    required this.heartRate,
    required this.sleep,
    required this.exercise,
    required this.sync,
    this.device,
    this.activeMinutes = const MetricBlock(supported: false, unit: 'min'),
    this.spo2 = const MetricBlock(supported: false, unit: '%'),
    this.hrv = const MetricBlock(supported: false, unit: 'ms'),
  });

  final String date;
  final DeviceBlock? device;
  final MetricBlock steps;
  final MetricBlock distance;
  final MetricBlock calories;
  final HeartRateBlock heartRate;
  final SleepBlock sleep;
  final ExerciseBlock exercise;
  final SyncBlock sync;

  /// Active minutes are absent in the day-totals fallback, so this block stays
  /// unsupported rather than showing an inferred number.
  final MetricBlock activeMinutes;
  final MetricBlock spo2;
  final MetricBlock hrv;

  factory PhysicalToday.fromJson(Map<String, dynamic> json) => PhysicalToday(
        date: json['date'] as String? ?? '',
        device: json['device'] is Map<String, dynamic>
            ? DeviceBlock.fromJson(json['device'] as Map<String, dynamic>)
            : null,
        steps: MetricBlock.fromJson(
          (json['steps'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        distance: MetricBlock.fromJson(
          (json['distance'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        calories: MetricBlock.fromJson(
          (json['calories'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        heartRate: HeartRateBlock.fromJson(
          (json['heartRate'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        sleep: SleepBlock.fromJson(
          (json['sleep'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        exercise: ExerciseBlock.fromJson(
          (json['exercise'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        sync: SyncBlock.fromJson(
          (json['sync'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        // Older cached payloads predate these blocks; they must keep parsing
        // and still read as "not supported" instead of null or a fake value.
        activeMinutes: MetricBlock.fromJson(
          (json['activeMinutes'] as Map?)?.cast<String, dynamic>() ??
              const {'supported': false, 'unit': 'min'},
        ),
        spo2: MetricBlock.fromJson(
          (json['spo2'] as Map?)?.cast<String, dynamic>() ??
              const {'supported': false, 'unit': '%'},
        ),
        hrv: MetricBlock.fromJson(
          (json['hrv'] as Map?)?.cast<String, dynamic>() ??
              const {'supported': false, 'unit': 'ms'},
        ),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'device': device?.toJson(),
        'steps': steps.toJson(),
        'distance': distance.toJson(),
        'calories': calories.toJson(),
        'heartRate': heartRate.toJson(),
        'sleep': sleep.toJson(),
        'exercise': exercise.toJson(),
        'activeMinutes': activeMinutes.toJson(),
        'spo2': spo2.toJson(),
        'hrv': hrv.toJson(),
        'sync': sync.toJson(),
      };
}

/// Registered wearable as returned by `/wearables`.
@immutable
class WearableDevice {
  const WearableDevice({
    required this.id,
    required this.provider,
    required this.deviceIdentifier,
    required this.connectionStatus,
    this.manufacturer,
    this.model,
    this.firmwareVersion,
    this.capabilities = const [],
    this.batteryLevel,
    this.charging,
    this.lastSyncedAt,
    this.lastSeenAt,
  });

  final String id;
  final String provider;
  final String deviceIdentifier;
  final String? manufacturer;
  final String? model;
  final String? firmwareVersion;
  final List<String> capabilities;
  final String connectionStatus;
  final int? batteryLevel;
  final bool? charging;
  final DateTime? lastSyncedAt;
  final DateTime? lastSeenAt;

  String get displayName {
    final manufacturer = this.manufacturer;
    final model = this.model;
    if (manufacturer != null &&
        manufacturer.isNotEmpty &&
        model != null &&
        model.isNotEmpty) {
      // A scan name like "Watch 8" yields manufacturer "Watch"; repeating it
      // would render "Watch Watch 8".
      if (model.toLowerCase().startsWith('${manufacturer.toLowerCase()} ')) {
        return model;
      }
      return '$manufacturer $model';
    }
    return model ?? manufacturer ?? 'Watch';
  }

  factory WearableDevice.fromJson(Map<String, dynamic> json) => WearableDevice(
        id: json['id'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        deviceIdentifier: json['deviceIdentifier'] as String? ?? '',
        manufacturer: _string(json['manufacturer']),
        model: _string(json['model']),
        firmwareVersion: _string(json['firmwareVersion']),
        capabilities: [
          for (final item in (json['capabilities'] as List?) ?? const [])
            item.toString(),
        ],
        connectionStatus: json['connectionStatus'] as String? ?? 'UNKNOWN',
        batteryLevel: _int(json['batteryLevel']),
        charging: json['charging'] as bool?,
        lastSyncedAt: _time(json['lastSyncedAt']),
        lastSeenAt: _time(json['lastSeenAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider,
        'deviceIdentifier': deviceIdentifier,
        'manufacturer': manufacturer,
        'model': model,
        'firmwareVersion': firmwareVersion,
        'capabilities': capabilities,
        'connectionStatus': connectionStatus,
        'batteryLevel': batteryLevel,
        'charging': charging,
        'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
        'lastSeenAt': lastSeenAt?.toUtc().toIso8601String(),
      };
}

@immutable
class ActivityDay {
  const ActivityDay({
    required this.date,
    this.steps,
    this.distanceMeters,
    this.caloriesKcal,
    this.activeMinutes,
  });

  final String date;
  final int? steps;
  final double? distanceMeters;
  final double? caloriesKcal;
  final int? activeMinutes;

  factory ActivityDay.fromJson(Map<String, dynamic> json) => ActivityDay(
        date: json['date'] as String? ?? '',
        steps: _int(json['steps']),
        distanceMeters: _double(json['distanceMeters']),
        caloriesKcal: _double(json['caloriesKcal']),
        activeMinutes: _int(json['activeMinutes']),
      );
}

/// Weekly trend payload from `/physical/summary`. Aggregates are nullable:
/// null means the source data never arrived, never "zero".
@immutable
class WeeklySummary {
  const WeeklySummary({
    required this.periodStart,
    required this.periodEnd,
    required this.daysWithData,
    this.totalSteps,
    this.averageSteps,
    this.totalDistanceMeters,
    this.totalCaloriesKcal,
    this.bestStepDay,
    this.bestStepDate,
    this.sleepSessions = 0,
    this.averageSleepMillis,
    this.days = const [],
  });

  final String periodStart;
  final String periodEnd;
  final int daysWithData;
  final int? totalSteps;
  final double? averageSteps;
  final double? totalDistanceMeters;
  final double? totalCaloriesKcal;
  final int? bestStepDay;
  final String? bestStepDate;
  final int sleepSessions;
  final int? averageSleepMillis;
  final List<ActivityDay> days;

  factory WeeklySummary.fromJson(Map<String, dynamic> json) => WeeklySummary(
        periodStart: json['periodStart'] as String? ?? '',
        periodEnd: json['periodEnd'] as String? ?? '',
        daysWithData: _int(json['daysWithData']) ?? 0,
        totalSteps: _int(json['totalSteps']),
        averageSteps: _double(json['averageSteps']),
        totalDistanceMeters: _double(json['totalDistanceMeters']),
        totalCaloriesKcal: _double(json['totalCaloriesKcal']),
        bestStepDay: _int(json['bestStepDay']),
        bestStepDate: _string(json['bestStepDate']),
        sleepSessions: _int(json['sleepSessions']) ?? 0,
        averageSleepMillis: _long(json['averageSleepMillis']),
        days: [
          for (final item in (json['days'] as List?) ?? const [])
            if (item is Map<String, dynamic>) ActivityDay.fromJson(item),
        ],
      );
}

@immutable
class SyncRejection {
  const SyncRejection({
    required this.category,
    required this.index,
    required this.reason,
  });

  final String category;
  final int index;
  final String reason;

  factory SyncRejection.fromJson(Map<String, dynamic> json) => SyncRejection(
        category: json['category'] as String? ?? '',
        index: _int(json['index']) ?? 0,
        reason: json['reason'] as String? ?? '',
      );
}

@immutable
class SyncResult {
  const SyncResult({
    required this.status,
    required this.received,
    required this.accepted,
    required this.duplicates,
    required this.rejected,
    this.syncSessionId,
    this.rejections = const [],
  });

  final String? syncSessionId;
  final String status;
  final int received;
  final int accepted;
  final int duplicates;
  final int rejected;
  final List<SyncRejection> rejections;

  bool get isFullyAccepted => rejected == 0 && status != 'FAILED';

  factory SyncResult.fromJson(Map<String, dynamic> json) => SyncResult(
        syncSessionId: _string(json['syncSessionId']),
        status: json['status'] as String? ?? 'UNKNOWN',
        received: _int(json['received']) ?? 0,
        accepted: _int(json['accepted']) ?? 0,
        duplicates: _int(json['duplicates']) ?? 0,
        rejected: _int(json['rejected']) ?? 0,
        rejections: [
          for (final item in (json['rejections'] as List?) ?? const [])
            if (item is Map<String, dynamic>) SyncRejection.fromJson(item),
        ],
      );
}
