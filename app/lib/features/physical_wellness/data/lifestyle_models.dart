import 'package:flutter/foundation.dart';

/// Parsed UTC instant; returns null for missing/invalid values.
DateTime? _time(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

double? _double(Object? value) =>
    value == null ? null : (value as num?)?.toDouble();

int? _int(Object? value) => value == null ? null : (value as num?)?.toInt();

String? _string(Object? value) => value?.toString();

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

List<Map<String, dynamic>> _maps(Object? value) => [
      for (final item in (value as List?) ?? const [])
        if (item is Map) item.cast<String, dynamic>(),
    ];

// ─────────────────────────────────────────────────────────────── hydration

@immutable
class HydrationEntry {
  const HydrationEntry({
    required this.id,
    required this.date,
    required this.amountMl,
    required this.timestamp,
    required this.source,
  });

  final String id;
  final String date;
  final double amountMl;
  final DateTime timestamp;
  final String source;

  factory HydrationEntry.fromJson(Map<String, dynamic> json) => HydrationEntry(
        id: json['id'] as String? ?? '',
        date: json['date'] as String? ?? '',
        amountMl: _double(json['amountMl']) ?? 0,
        timestamp: _time(json['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        source: json['source'] as String? ?? 'USER_ENTERED',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'amountMl': amountMl,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'source': source,
      };
}

/// One calendar day of hydration. [entryCount] zero means nothing was logged:
/// the day's 0 ml is the sum of no entries, not a measurement.
@immutable
class HydrationDay {
  const HydrationDay({
    required this.date,
    required this.totalMl,
    required this.entryCount,
    this.entries = const [],
  });

  final String date;
  final double totalMl;
  final int entryCount;
  final List<HydrationEntry> entries;

  bool get hasEntries => entryCount > 0;

  factory HydrationDay.fromJson(Map<String, dynamic> json) => HydrationDay(
        date: json['date'] as String? ?? '',
        totalMl: _double(json['totalMl']) ?? 0,
        entryCount: _int(json['entryCount']) ?? 0,
        entries: [
          for (final item in _maps(json['entries'])) HydrationEntry.fromJson(item),
        ],
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'totalMl': totalMl,
        'entryCount': entryCount,
        'entries': [for (final entry in entries) entry.toJson()],
      };
}

@immutable
class HydrationOverview {
  const HydrationOverview({
    required this.unit,
    required this.targetMl,
    required this.targetCustomized,
    required this.today,
    this.days = const [],
    this.guidance,
  });

  final String unit;
  final int targetMl;
  final bool targetCustomized;
  final HydrationDay today;
  final List<HydrationDay> days;
  final String? guidance;

  /// Fraction of today's target, capped at 1 so over-drinking still reads as
  /// "met" rather than 140 %. Null when no target has been set.
  double? get progress {
    if (targetMl <= 0) return null;
    return (today.totalMl / targetMl).clamp(0.0, 1.0);
  }

  int? get remainingMl {
    if (targetMl <= 0) return null;
    final remaining = targetMl - today.totalMl;
    return remaining <= 0 ? 0 : remaining.round();
  }

  factory HydrationOverview.fromJson(Map<String, dynamic> json) =>
      HydrationOverview(
        unit: json['unit'] as String? ?? 'ml',
        targetMl: _int(json['targetMl']) ?? 0,
        targetCustomized: json['targetCustomized'] as bool? ?? false,
        today: HydrationDay.fromJson(_map(json['today'])),
        days: [
          for (final item in _maps(json['days'])) HydrationDay.fromJson(item),
        ],
        guidance: _string(json['guidance']),
      );

  Map<String, dynamic> toJson() => {
        'unit': unit,
        'targetMl': targetMl,
        'targetCustomized': targetCustomized,
        'today': today.toJson(),
        'days': [for (final day in days) day.toJson()],
        'guidance': guidance,
      };
}

// ──────────────────────────────────────────────────────── body + weight

@immutable
class BodyMeasurementEntry {
  const BodyMeasurementEntry({
    required this.id,
    required this.date,
    required this.measuredAt,
    required this.source,
    this.weightKg,
    this.heightCm,
    this.deviceId,
  });

  final String id;
  final String date;
  final DateTime measuredAt;
  final String source;
  final double? weightKg;
  final double? heightCm;
  final String? deviceId;

  factory BodyMeasurementEntry.fromJson(Map<String, dynamic> json) =>
      BodyMeasurementEntry(
        id: json['id'] as String? ?? '',
        date: json['date'] as String? ?? '',
        measuredAt: _time(json['measuredAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        source: json['source'] as String? ?? 'USER_ENTERED',
        weightKg: _double(json['weightKg']),
        heightCm: _double(json['heightCm']),
        deviceId: _string(json['deviceId']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'measuredAt': measuredAt.toUtc().toIso8601String(),
        'source': source,
        'weightKg': weightKg,
        'heightCm': heightCm,
        'deviceId': deviceId,
      };
}

/// BMI is a screening number, not a diagnosis. [disclaimer] must be rendered
/// wherever [value] is shown.
@immutable
class BmiBlock {
  const BmiBlock({
    required this.value,
    required this.category,
    required this.label,
    required this.disclaimer,
    this.weightKg,
    this.heightCm,
    this.calculatedFrom,
  });

  final double value;
  final String category;
  final String label;
  final String disclaimer;
  final double? weightKg;
  final double? heightCm;
  final DateTime? calculatedFrom;

  factory BmiBlock.fromJson(Map<String, dynamic> json) => BmiBlock(
        value: _double(json['value']) ?? 0,
        category: json['category'] as String? ?? '',
        label: json['label'] as String? ?? '',
        disclaimer: json['disclaimer'] as String? ?? '',
        weightKg: _double(json['weightKg']),
        heightCm: _double(json['heightCm']),
        calculatedFrom: _time(json['calculatedFrom']),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'category': category,
        'label': label,
        'disclaimer': disclaimer,
        'weightKg': weightKg,
        'heightCm': heightCm,
        'calculatedFrom': calculatedFrom?.toUtc().toIso8601String(),
      };
}

@immutable
class WeightTrend {
  const WeightTrend({
    this.latestKg,
    this.previousKg,
    this.changeKg,
    this.daysWithData = 0,
    this.windowDays = 30,
  });

  final double? latestKg;
  final double? previousKg;
  final double? changeKg;
  final int daysWithData;
  final int windowDays;

  factory WeightTrend.fromJson(Map<String, dynamic> json) => WeightTrend(
        latestKg: _double(json['latestKg']),
        previousKg: _double(json['previousKg']),
        changeKg: _double(json['changeKg']),
        daysWithData: _int(json['daysWithData']) ?? 0,
        windowDays: _int(json['windowDays']) ?? 30,
      );

  Map<String, dynamic> toJson() => {
        'latestKg': latestKg,
        'previousKg': previousKg,
        'changeKg': changeKg,
        'daysWithData': daysWithData,
        'windowDays': windowDays,
      };
}

@immutable
class BodySummary {
  const BodySummary({
    required this.weightUnit,
    required this.heightUnit,
    required this.trend,
    this.latest,
    this.bmi,
    this.history = const [],
    this.limitations = const [],
  });

  final String weightUnit;
  final String heightUnit;
  final BodyMeasurementEntry? latest;
  final BmiBlock? bmi;
  final WeightTrend trend;
  final List<BodyMeasurementEntry> history;
  final List<String> limitations;

  /// Limitations that add information beyond the BMI disclaimer.
  ///
  /// The server returns the BMI disclaimer as the first item of
  /// [limitations] as well as in `bmi.disclaimer`. Rendering both duplicates
  /// the same sentence and hides the useful body-composition caveat, so the
  /// UI shows this filtered list instead.
  List<String> get additionalLimitations => [
        for (final text in limitations)
          if (bmi?.disclaimer != text) text,
      ];

  factory BodySummary.fromJson(Map<String, dynamic> json) => BodySummary(
        weightUnit: json['weightUnit'] as String? ?? 'kg',
        heightUnit: json['heightUnit'] as String? ?? 'cm',
        latest: json['latest'] is Map
            ? BodyMeasurementEntry.fromJson(_map(json['latest']))
            : null,
        bmi: json['bmi'] is Map ? BmiBlock.fromJson(_map(json['bmi'])) : null,
        trend: WeightTrend.fromJson(_map(json['trend'])),
        history: [
          for (final item in _maps(json['history']))
            BodyMeasurementEntry.fromJson(item),
        ],
        limitations: [
          for (final item in (json['limitations'] as List?) ?? const [])
            item.toString(),
        ],
      );

  Map<String, dynamic> toJson() => {
        'weightUnit': weightUnit,
        'heightUnit': heightUnit,
        'latest': latest?.toJson(),
        'bmi': bmi?.toJson(),
        'trend': trend.toJson(),
        'history': [for (final item in history) item.toJson()],
        'limitations': limitations,
      };
}

// ─────────────────────────────────────────────────────────────── goals

@immutable
class GoalTargets {
  const GoalTargets({
    this.dailySteps,
    this.dailyActiveMinutes,
    this.weeklyWorkoutMinutes,
    this.dailySleepMinutes,
    this.dailyHydrationMl,
  });

  /// Null means the user has not chosen a target — never a fabricated default.
  final int? dailySteps;
  final int? dailyActiveMinutes;
  final int? weeklyWorkoutMinutes;
  final int? dailySleepMinutes;
  final int? dailyHydrationMl;

  bool get isEmpty =>
      dailySteps == null &&
      dailyActiveMinutes == null &&
      weeklyWorkoutMinutes == null &&
      dailySleepMinutes == null &&
      dailyHydrationMl == null;

  factory GoalTargets.fromJson(Map<String, dynamic> json) => GoalTargets(
        dailySteps: _int(json['dailySteps']),
        dailyActiveMinutes: _int(json['dailyActiveMinutes']),
        weeklyWorkoutMinutes: _int(json['weeklyWorkoutMinutes']),
        dailySleepMinutes: _int(json['dailySleepMinutes']),
        dailyHydrationMl: _int(json['dailyHydrationMl']),
      );

  Map<String, dynamic> toJson() => {
        'dailySteps': dailySteps,
        'dailyActiveMinutes': dailyActiveMinutes,
        'weeklyWorkoutMinutes': weeklyWorkoutMinutes,
        'dailySleepMinutes': dailySleepMinutes,
        'dailyHydrationMl': dailyHydrationMl,
      };
}

@immutable
class GoalProgress {
  const GoalProgress({
    required this.metric,
    required this.label,
    required this.unit,
    required this.period,
    required this.dataAvailable,
    this.target,
    this.current,
    this.remaining,
    this.progress,
    this.met,
    this.source,
    this.note,
    this.targetSource,
  });

  final String metric;
  final String label;
  final String unit;
  final String period;
  final int? target;
  final double? current;
  final double? remaining;
  final double? progress;
  final bool? met;
  final bool dataAvailable;
  final String? source;
  final String? note;

  /// USER, AI_RECOMMENDED, or null when no target is set. Legacy goals with no
  /// provenance are reported as USER by the backend.
  final String? targetSource;

  bool get isAiTarget => targetSource == 'AI_RECOMMENDED';

  factory GoalProgress.fromJson(Map<String, dynamic> json) => GoalProgress(
        metric: json['metric'] as String? ?? '',
        label: json['label'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        period: json['period'] as String? ?? '',
        target: _int(json['target']),
        current: _double(json['current']),
        remaining: _double(json['remaining']),
        progress: _double(json['progress']),
        met: json['met'] as bool?,
        dataAvailable: json['dataAvailable'] as bool? ?? false,
        source: _string(json['source']),
        note: _string(json['note']),
        targetSource: _string(json['targetSource']),
      );

  Map<String, dynamic> toJson() => {
        'metric': metric,
        'label': label,
        'unit': unit,
        'period': period,
        'target': target,
        'current': current,
        'remaining': remaining,
        'progress': progress,
        'met': met,
        'dataAvailable': dataAvailable,
        'source': source,
        'note': note,
        'targetSource': targetSource,
      };
}

@immutable
class StreakResult {
  const StreakResult({
    required this.metric,
    required this.currentStreak,
    required this.longestStreak,
    required this.daysEvaluated,
    required this.daysWithData,
    this.note,
  });

  final String metric;
  final int currentStreak;
  final int longestStreak;
  final int daysEvaluated;
  final int daysWithData;
  final String? note;

  factory StreakResult.fromJson(Map<String, dynamic> json) => StreakResult(
        metric: json['metric'] as String? ?? '',
        currentStreak: _int(json['currentStreak']) ?? 0,
        longestStreak: _int(json['longestStreak']) ?? 0,
        daysEvaluated: _int(json['daysEvaluated']) ?? 0,
        daysWithData: _int(json['daysWithData']) ?? 0,
        note: _string(json['note']),
      );

  Map<String, dynamic> toJson() => {
        'metric': metric,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'daysEvaluated': daysEvaluated,
        'daysWithData': daysWithData,
        'note': note,
      };
}

@immutable
class GoalsOverview {
  const GoalsOverview({
    required this.goals,
    required this.customized,
    required this.suggestedDefaults,
    this.progress = const [],
    this.streaks = const {},
    this.guidance = const [],
  });

  final GoalTargets goals;
  final bool customized;
  final List<GoalProgress> progress;
  final Map<String, StreakResult> streaks;

  /// Suggestions are clearly separate from the user's own targets, so the UI
  /// can offer them without pretending they were chosen.
  final GoalTargets suggestedDefaults;
  final List<String> guidance;

  factory GoalsOverview.fromJson(Map<String, dynamic> json) => GoalsOverview(
        goals: GoalTargets.fromJson(_map(json['goals'])),
        customized: json['customized'] as bool? ?? false,
        progress: [
          for (final item in _maps(json['progress']))
            GoalProgress.fromJson(item),
        ],
        streaks: {
          for (final entry in _map(json['streaks']).entries)
            entry.key: StreakResult.fromJson(_map(entry.value)),
        },
        suggestedDefaults:
            GoalTargets.fromJson(_map(json['suggestedDefaults'])),
        guidance: [
          for (final item in (json['guidance'] as List?) ?? const [])
            item.toString(),
        ],
      );

  Map<String, dynamic> toJson() => {
        'goals': goals.toJson(),
        'customized': customized,
        'progress': [for (final item in progress) item.toJson()],
        'streaks': {
          for (final entry in streaks.entries) entry.key: entry.value.toJson(),
        },
        'suggestedDefaults': suggestedDefaults.toJson(),
        'guidance': guidance,
      };
}

// ─────────────────────────────────────────────────────────────── trends

@immutable
class TrendPoint {
  const TrendPoint({required this.date, required this.value, this.source});

  final String date;
  final double value;
  final String? source;

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
        date: json['date'] as String? ?? '',
        value: _double(json['value']) ?? 0,
        source: _string(json['source']),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'value': value,
        'source': source,
      };
}

@immutable
class MetricTrend {
  const MetricTrend({
    required this.metric,
    required this.label,
    required this.unit,
    required this.aggregation,
    required this.daysWithData,
    required this.windowDays,
    this.points = const [],
    this.average,
    this.previousAverage,
    this.changePercent,
    this.quality,
    this.note,
  });

  final String metric;
  final String label;
  final String unit;
  final String aggregation;
  final List<TrendPoint> points;
  final double? average;
  final double? previousAverage;
  final double? changePercent;
  final int daysWithData;
  final int windowDays;
  final String? quality;
  final String? note;

  bool get hasData => points.isNotEmpty;

  factory MetricTrend.fromJson(Map<String, dynamic> json) => MetricTrend(
        metric: json['metric'] as String? ?? '',
        label: json['label'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        aggregation: json['aggregation'] as String? ?? '',
        points: [
          for (final item in _maps(json['points'])) TrendPoint.fromJson(item),
        ],
        average: _double(json['average']),
        previousAverage: _double(json['previousAverage']),
        changePercent: _double(json['changePercent']),
        daysWithData: _int(json['daysWithData']) ?? 0,
        windowDays: _int(json['windowDays']) ?? 7,
        quality: _string(json['quality']),
        note: _string(json['note']),
      );

  Map<String, dynamic> toJson() => {
        'metric': metric,
        'label': label,
        'unit': unit,
        'aggregation': aggregation,
        'points': [for (final point in points) point.toJson()],
        'average': average,
        'previousAverage': previousAverage,
        'changePercent': changePercent,
        'daysWithData': daysWithData,
        'windowDays': windowDays,
        'quality': quality,
        'note': note,
      };
}

@immutable
class TrendsOverview {
  const TrendsOverview({
    required this.from,
    required this.to,
    required this.windowDays,
    required this.previousWindowDays,
    this.metrics = const [],
    this.coverageNotes = const [],
  });

  final String from;
  final String to;
  final int windowDays;
  final int previousWindowDays;
  final List<MetricTrend> metrics;
  final List<String> coverageNotes;

  factory TrendsOverview.fromJson(Map<String, dynamic> json) => TrendsOverview(
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        windowDays: _int(json['windowDays']) ?? 7,
        previousWindowDays: _int(json['previousWindowDays']) ?? 7,
        metrics: [
          for (final item in _maps(json['metrics'])) MetricTrend.fromJson(item),
        ],
        coverageNotes: [
          for (final item in (json['coverageNotes'] as List?) ?? const [])
            item.toString(),
        ],
      );

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'windowDays': windowDays,
        'previousWindowDays': previousWindowDays,
        'metrics': [for (final metric in metrics) metric.toJson()],
        'coverageNotes': coverageNotes,
      };
}

// ─────────────────────────────────────────────────────────────── insights

@immutable
class InsightEvidence {
  const InsightEvidence({
    required this.source,
    required this.metric,
    required this.windowDays,
    required this.coverageDays,
    required this.comparison,
    this.current,
    this.baseline,
    this.unit,
  });

  final String source;
  final String metric;
  final double? current;
  final double? baseline;
  final String? unit;
  final int windowDays;
  final int coverageDays;
  final String comparison;

  factory InsightEvidence.fromJson(Map<String, dynamic> json) =>
      InsightEvidence(
        source: json['source'] as String? ?? '',
        metric: json['metric'] as String? ?? '',
        current: _double(json['current']),
        baseline: _double(json['baseline']),
        unit: _string(json['unit']),
        windowDays: _int(json['windowDays']) ?? 0,
        coverageDays: _int(json['coverageDays']) ?? 0,
        comparison: json['comparison'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'source': source,
        'metric': metric,
        'current': current,
        'baseline': baseline,
        'unit': unit,
        'windowDays': windowDays,
        'coverageDays': coverageDays,
        'comparison': comparison,
      };
}

@immutable
class InsightCoverage {
  const InsightCoverage({
    required this.windowDays,
    required this.daysWithActivity,
    required this.daysWithSleep,
    required this.daysWithHydration,
    required this.moodCheckins,
    required this.heartRateDays,
    this.missingSources = const [],
  });

  final int windowDays;
  final int daysWithActivity;
  final int daysWithSleep;
  final int daysWithHydration;
  final int moodCheckins;
  final int heartRateDays;
  final List<String> missingSources;

  factory InsightCoverage.fromJson(Map<String, dynamic> json) =>
      InsightCoverage(
        windowDays: _int(json['windowDays']) ?? 0,
        daysWithActivity: _int(json['daysWithActivity']) ?? 0,
        daysWithSleep: _int(json['daysWithSleep']) ?? 0,
        daysWithHydration: _int(json['daysWithHydration']) ?? 0,
        moodCheckins: _int(json['moodCheckins']) ?? 0,
        heartRateDays: _int(json['heartRateDays']) ?? 0,
        missingSources: [
          for (final item in (json['missingSources'] as List?) ?? const [])
            item.toString(),
        ],
      );

  Map<String, dynamic> toJson() => {
        'windowDays': windowDays,
        'daysWithActivity': daysWithActivity,
        'daysWithSleep': daysWithSleep,
        'daysWithHydration': daysWithHydration,
        'moodCheckins': moodCheckins,
        'heartRateDays': heartRateDays,
        'missingSources': missingSources,
      };
}

/// A descriptive pattern. [summary] must never be rephrased as a diagnosis and
/// [disclaimer] must accompany it in the UI.
@immutable
class PatternInsight {
  const PatternInsight({
    required this.id,
    required this.title,
    required this.summary,
    required this.severity,
    required this.confidence,
    required this.disclaimer,
    this.evidence = const [],
    this.coverage,
  });

  final String id;
  final String title;
  final String summary;
  final String severity;
  final String confidence;
  final List<InsightEvidence> evidence;
  final InsightCoverage? coverage;
  final String disclaimer;

  factory PatternInsight.fromJson(Map<String, dynamic> json) => PatternInsight(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        severity: json['severity'] as String? ?? 'INFO',
        confidence: json['confidence'] as String? ?? 'LOW',
        evidence: [
          for (final item in _maps(json['evidence']))
            InsightEvidence.fromJson(item),
        ],
        coverage: json['coverage'] is Map
            ? InsightCoverage.fromJson(_map(json['coverage']))
            : null,
        disclaimer: json['disclaimer'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'severity': severity,
        'confidence': confidence,
        'evidence': [for (final item in evidence) item.toJson()],
        'coverage': coverage?.toJson(),
        'disclaimer': disclaimer,
      };
}

@immutable
class WellnessRecommendation {
  const WellnessRecommendation({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.source,
  });

  final String id;
  final String title;
  final String description;
  final String category;

  /// `RULE_ENGINE` or `AI_SERVICE` — shown so wording provenance is explicit.
  final String source;

  factory WellnessRecommendation.fromJson(Map<String, dynamic> json) =>
      WellnessRecommendation(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? '',
        source: json['source'] as String? ?? 'RULE_ENGINE',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category,
        'source': source,
      };
}

@immutable
class InsightsOverview {
  const InsightsOverview({
    required this.windowDays,
    required this.sufficientData,
    required this.aiEnhanced,
    required this.disclaimer,
    this.generatedAt,
    this.insights = const [],
    this.recommendations = const [],
    this.coverage,
    this.limitations = const [],
  });

  final DateTime? generatedAt;
  final int windowDays;
  final bool sufficientData;
  final List<PatternInsight> insights;
  final List<WellnessRecommendation> recommendations;
  final bool aiEnhanced;
  final InsightCoverage? coverage;
  final List<String> limitations;
  final String disclaimer;

  factory InsightsOverview.fromJson(Map<String, dynamic> json) =>
      InsightsOverview(
        generatedAt: _time(json['generatedAt']),
        windowDays: _int(json['windowDays']) ?? 14,
        sufficientData: json['sufficientData'] as bool? ?? false,
        insights: [
          for (final item in _maps(json['insights']))
            PatternInsight.fromJson(item),
        ],
        recommendations: [
          for (final item in _maps(json['recommendations']))
            WellnessRecommendation.fromJson(item),
        ],
        aiEnhanced: json['aiEnhanced'] as bool? ?? false,
        coverage: json['coverage'] is Map
            ? InsightCoverage.fromJson(_map(json['coverage']))
            : null,
        limitations: [
          for (final item in (json['limitations'] as List?) ?? const [])
            item.toString(),
        ],
        disclaimer: json['disclaimer'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt?.toUtc().toIso8601String(),
        'windowDays': windowDays,
        'sufficientData': sufficientData,
        'insights': [for (final item in insights) item.toJson()],
        'recommendations': [
          for (final item in recommendations) item.toJson(),
        ],
        'aiEnhanced': aiEnhanced,
        'coverage': coverage?.toJson(),
        'limitations': limitations,
        'disclaimer': disclaimer,
      };
}

// ──────────────────────────────────────────────────────── capabilities

@immutable
class DeviceCapabilityInfo {
  const DeviceCapabilityInfo({
    required this.metric,
    required this.label,
    required this.unit,
    required this.supportStatus,
    required this.retrievalMethod,
    required this.verificationStatus,
    this.limitations,
    this.lastVerifiedAt,
    this.updatedAt,
  });

  final String metric;
  final String label;
  final String unit;
  final String supportStatus;
  final String retrievalMethod;
  final String verificationStatus;
  final String? limitations;
  final DateTime? lastVerifiedAt;
  final DateTime? updatedAt;

  bool get isSupported =>
      supportStatus == 'SUPPORTED_VERIFIED' ||
      supportStatus == 'SUPPORTED_UNVERIFIED';

  /// Only the server can set this, after a documented on-device validation.
  bool get isVerified => verificationStatus == 'VERIFIED_ON_DEVICE';

  factory DeviceCapabilityInfo.fromJson(Map<String, dynamic> json) =>
      DeviceCapabilityInfo(
        metric: json['metric'] as String? ?? '',
        label: json['label'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        supportStatus: json['supportStatus'] as String? ?? 'UNKNOWN',
        retrievalMethod: json['retrievalMethod'] as String? ?? 'NONE',
        verificationStatus: json['verificationStatus'] as String? ?? 'UNKNOWN',
        limitations: _string(json['limitations']),
        lastVerifiedAt: _time(json['lastVerifiedAt']),
        updatedAt: _time(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'metric': metric,
        'label': label,
        'unit': unit,
        'supportStatus': supportStatus,
        'retrievalMethod': retrievalMethod,
        'verificationStatus': verificationStatus,
        'limitations': limitations,
        'lastVerifiedAt': lastVerifiedAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };
}

@immutable
class CapabilityList {
  const CapabilityList({
    required this.deviceId,
    required this.capabilities,
    this.deviceModel,
    this.firmwareVersion,
    this.notes = const [],
  });

  final String deviceId;
  final String? deviceModel;
  final String? firmwareVersion;
  final List<DeviceCapabilityInfo> capabilities;
  final List<String> notes;

  DeviceCapabilityInfo? find(String metric) {
    for (final item in capabilities) {
      if (item.metric == metric) return item;
    }
    return null;
  }

  factory CapabilityList.fromJson(Map<String, dynamic> json) => CapabilityList(
        deviceId: json['deviceId'] as String? ?? '',
        deviceModel: _string(json['deviceModel']),
        firmwareVersion: _string(json['firmwareVersion']),
        capabilities: [
          for (final item in _maps(json['capabilities']))
            DeviceCapabilityInfo.fromJson(item),
        ],
        notes: [
          for (final item in (json['notes'] as List?) ?? const [])
            item.toString(),
        ],
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceModel': deviceModel,
        'firmwareVersion': firmwareVersion,
        'capabilities': [for (final item in capabilities) item.toJson()],
        'notes': notes,
      };
}

// ──────────────────────────────────────────────────── pending mutations

/// A write that has not been confirmed by the server yet.
///
/// It is queued instead of being applied to the confirmed state, so the UI can
/// say "waiting to sync" rather than reporting an unconfirmed write as saved.
enum PendingMutationType {
  hydrationAdd,
  hydrationUpdate,
  hydrationDelete,
  hydrationTarget,
  bodyAdd,
  goalsUpdate;

  static PendingMutationType? fromName(String? name) {
    for (final type in PendingMutationType.values) {
      if (type.name == name) return type;
    }
    return null;
  }
}

@immutable
class PendingMutation {
  const PendingMutation({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final PendingMutationType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  String? get entryId => payload['id']?.toString();

  factory PendingMutation.fromJson(Map<String, dynamic> json) =>
      PendingMutation(
        id: json['id'] as String? ?? '',
        type: PendingMutationType.fromName(json['type']?.toString()) ??
            PendingMutationType.hydrationAdd,
        payload: _map(json['payload']),
        createdAt: _time(json['createdAt']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'payload': payload,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}
