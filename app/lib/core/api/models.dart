/// Authenticated caller projection returned by the backend.
class MindeaseUser {
  const MindeaseUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.onboardingStatus,
    this.consentStatus,
    this.screeningStatus,
  });

  final String id;
  final String email;
  final String fullName;
  final String? onboardingStatus;
  final String? consentStatus;
  final String? screeningStatus;

  factory MindeaseUser.fromJson(Map<String, dynamic> json) => MindeaseUser(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        onboardingStatus: json['onboardingStatus'] as String?,
        consentStatus: json['consentStatus'] as String?,
        screeningStatus: json['screeningStatus'] as String?,
      );
}

/// Token pair plus the caller profile returned by register/login/refresh.
class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  final MindeaseUser user;
  final String accessToken;
  final String refreshToken;
}

/// Wellness profile projection. AI-derived fields stay null while analysis
/// is pending; they are only populated once the backend sets COMPLETED.
/// Mood fields are the integrated Mood Check-In summary: user-provided
/// (moodMood/moodEmotion/moodIntensity), calculated (moodScore/trend/history)
/// and camera supporting signal (cameraEmotion/cameraConfidence/
/// signalAgreement) — all null when unavailable (older profiles, no
/// onboarding mood, or skipped/unclear camera).
class MindeaseProfile {
  const MindeaseProfile({
    required this.id,
    required this.status,
    this.wellnessScore,
    this.stressLevel,
    this.lifestyleScore,
    this.sleepQuality,
    this.primaryFocus,
    this.aiInsight,
    this.moodMood,
    this.moodEmotion,
    this.moodIntensity,
    this.moodScore,
    this.moodTrendDirection,
    this.moodTrendDescription,
    this.moodHistoryCount,
    this.cameraEmotion,
    this.cameraConfidence,
    this.signalAgreement,
    this.safetyFlag = false,
  });

  final String id;
  final String status;
  final int? wellnessScore;
  final String? stressLevel;
  final int? lifestyleScore;
  final String? sleepQuality;
  final String? primaryFocus;
  final String? aiInsight;
  final String? moodMood;
  final String? moodEmotion;
  final int? moodIntensity;
  final int? moodScore;
  final String? moodTrendDirection;
  final String? moodTrendDescription;
  final int? moodHistoryCount;
  final String? cameraEmotion;
  final double? cameraConfidence;
  final String? signalAgreement;

  /// Server-derived safety escalation from PHQ-9 item 9.
  ///
  /// Any non-zero answer to the self-harm ideation item is a positive screen.
  /// This is not a diagnosis; it only unlocks an explicit support affordance.
  final bool safetyFlag;

  /// True while the AI insight has not arrived yet.
  ///
  /// This says nothing about the scores: they are computed server-side from the
  /// stored questionnaire answers and are published at submission time, so they
  /// are readable while the insight is still pending. Use [hasScores] to decide
  /// whether there is anything to display.
  bool get isPending => status == 'AI_ANALYSIS_PENDING';

  /// Whether the deterministic scores have been published.
  ///
  /// These are final and never change once present - the AI job can only add
  /// [aiInsight], never revise a score.
  bool get hasScores => wellnessScore != null;

  /// Whether the personalised insight narrative has been generated.
  bool get hasInsight => aiInsight != null && aiInsight!.isNotEmpty;

  /// Whether the profile carries an onboarding mood assessment.
  bool get hasMood => moodMood != null && moodMood!.isNotEmpty;

  /// Whether a usable camera supporting signal is attached.
  bool get hasCameraSignal =>
      cameraEmotion != null &&
      cameraEmotion!.isNotEmpty &&
      cameraEmotion != 'unknown' &&
      signalAgreement != null &&
      signalAgreement != 'noSignal';

  factory MindeaseProfile.fromJson(Map<String, dynamic> json) =>
      MindeaseProfile(
        id: json['id'] as String? ?? '',
        status: json['status'] as String? ?? 'AI_ANALYSIS_PENDING',
        wellnessScore: json['wellnessScore'] as int?,
        stressLevel: json['stressLevel'] as String?,
        lifestyleScore: json['lifestyleScore'] as int?,
        sleepQuality: json['sleepQuality'] as String?,
        primaryFocus: json['primaryFocus'] as String?,
        aiInsight: json['aiInsight'] as String?,
        moodMood: json['moodMood'] as String?,
        moodEmotion: json['moodEmotion'] as String?,
        moodIntensity: (json['moodIntensity'] as num?)?.toInt(),
        moodScore: (json['moodScore'] as num?)?.toInt(),
        moodTrendDirection: json['moodTrendDirection'] as String?,
        moodTrendDescription: json['moodTrendDescription'] as String?,
        moodHistoryCount: (json['moodHistoryCount'] as num?)?.toInt(),
        cameraEmotion: json['cameraEmotion'] as String?,
        cameraConfidence: (json['cameraConfidence'] as num?)?.toDouble(),
        signalAgreement: json['signalAgreement'] as String?,
        safetyFlag: json['safetyFlag'] as bool? ?? false,
      );
}

/// One selectable scale option (value 0..max with a human label).
class MindeaseScaleOption {
  const MindeaseScaleOption({required this.value, required this.label});

  final int value;
  final String label;

  factory MindeaseScaleOption.fromJson(Map<String, dynamic> json) =>
      MindeaseScaleOption(
        value: (json['value'] as num?)?.toInt() ?? 0,
        label: json['label'] as String? ?? '',
      );
}

/// One clinical questionnaire: shared instruction + scale options + ordered
/// question texts.
class MindeaseQuestionnaire {
  const MindeaseQuestionnaire({
    required this.code,
    required this.title,
    required this.instruction,
    required this.options,
    required this.items,
  });

  final String code;
  final String title;
  final String instruction;
  final List<MindeaseScaleOption> options;
  final List<String> items;

  factory MindeaseQuestionnaire.fromJson(Map<String, dynamic> json) =>
      MindeaseQuestionnaire(
        code: json['code'] as String? ?? '',
        title: json['title'] as String? ?? '',
        instruction: json['instruction'] as String? ?? '',
        options: _scaleOptions(json['options']),
        items: (json['items'] as List?)?.cast<String>() ?? const [],
      );
}

/// One lifestyle question (slider or choice) served by the catalog.
class MindeaseLifestyleQuestion {
  const MindeaseLifestyleQuestion({
    required this.field,
    required this.label,
    required this.title,
    required this.hint,
    required this.type,
    this.min = 0,
    this.max = 0,
    this.step = 1,
    this.unit = '',
    this.choices = const [],
  });

  final String field;
  final String label;
  final String title;
  final String hint;
  final String type;
  final double min;
  final double max;
  final double step;
  final String unit;
  final List<MindeaseScaleOption> choices;

  factory MindeaseLifestyleQuestion.fromJson(Map<String, dynamic> json) =>
      MindeaseLifestyleQuestion(
        field: json['field'] as String? ?? '',
        label: json['label'] as String? ?? '',
        title: json['title'] as String? ?? '',
        hint: json['hint'] as String? ?? '',
        type: json['type'] as String? ?? 'slider',
        min: (json['min'] as num?)?.toDouble() ?? 0,
        max: (json['max'] as num?)?.toDouble() ?? 0,
        step: (json['step'] as num?)?.toDouble() ?? 1,
        unit: json['unit'] as String? ?? '',
        choices: _scaleOptions(json['choices']),
      );
}

/// The questionnaire catalog served by GET /screenings/questions. It is the
/// single source of truth for every question, option and picker choice the
/// screening flow renders.
class MindeaseCatalog {
  const MindeaseCatalog({
    required this.version,
    required this.questionnaires,
    required this.lifestyle,
    required this.genderOptions,
    required this.occupationOptions,
  });

  final String version;
  final List<MindeaseQuestionnaire> questionnaires;
  final List<MindeaseLifestyleQuestion> lifestyle;
  final List<String> genderOptions;
  final List<String> occupationOptions;

  MindeaseQuestionnaire? byCode(String code) {
    for (final q in questionnaires) {
      if (q.code == code) return q;
    }
    return null;
  }

  factory MindeaseCatalog.fromJson(Map<String, dynamic> json) =>
      MindeaseCatalog(
        version: json['version'] as String? ?? '',
        questionnaires: [
          for (final q in (json['questionnaires'] as List?) ?? const [])
            if (q is Map<String, dynamic>) MindeaseQuestionnaire.fromJson(q),
        ],
        lifestyle: [
          for (final q in (json['lifestyle'] as List?) ?? const [])
            if (q is Map<String, dynamic>)
              MindeaseLifestyleQuestion.fromJson(q),
        ],
        genderOptions:
            (json['genderOptions'] as List?)?.cast<String>() ?? const [],
        occupationOptions:
            (json['occupationOptions'] as List?)?.cast<String>() ?? const [],
      );
}

List<MindeaseScaleOption> _scaleOptions(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map<String, dynamic>) MindeaseScaleOption.fromJson(item),
  ];
}

/// Dashboard aggregate from GET /dashboard.
class MindeaseDashboard {
  const MindeaseDashboard({
    required this.name,
    required this.aiReady,
    required this.aiStatus,
    this.wellnessScore,
    this.todayInsight,
    this.safetyFlag = false,
    this.mood,
  });

  final String name;
  final bool aiReady;
  final String aiStatus;
  final int? wellnessScore;
  final String? todayInsight;

  /// Positive PHQ-9 item-9 screen; unlocks the dashboard support card.
  final bool safetyFlag;

  /// Authoritative mood progress from the backend (never recalculated here).
  final MindeaseMoodSummary? mood;

  factory MindeaseDashboard.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map
        ? MindeaseUser.fromJson(json['user'] as Map<String, dynamic>)
        : null;
    final full = user?.fullName.trim() ?? '';
    return MindeaseDashboard(
      name: full.isEmpty ? 'there' : full.split(RegExp(r'\s+')).first,
      aiReady: json['aiReady'] as bool? ?? false,
      aiStatus: json['aiStatus'] as String? ?? 'AI_ANALYSIS_PENDING',
      wellnessScore: json['wellnessScore'] as int?,
      todayInsight: json['todayInsight'] as String?,
      safetyFlag: json['safetyFlag'] as bool? ?? false,
      mood: json['mood'] is Map
          ? MindeaseMoodSummary.fromJson(json['mood'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Authoritative mood progress summary for the dashboard home tab.
/// Display as-is; trend direction is computed server-side.
class MindeaseMoodSummary {
  const MindeaseMoodSummary({
    required this.hasHistory,
    this.currentMood,
    this.moodEmotion,
    this.moodScore,
    this.trendDirection,
    this.trendDescription,
    this.historyCount,
    this.cameraEmotion,
    this.signalAgreement,
  });

  final bool hasHistory;
  final String? currentMood;
  final String? moodEmotion;
  final int? moodScore;
  final String? trendDirection;
  final String? trendDescription;
  final int? historyCount;

  /// Camera supporting signal from the latest completed profile, if any.
  final String? cameraEmotion;
  final String? signalAgreement;

  /// Whether a usable camera signal is attached for display.
  bool get hasCameraSignal =>
      cameraEmotion != null &&
      cameraEmotion!.isNotEmpty &&
      cameraEmotion != 'unknown' &&
      signalAgreement != null &&
      signalAgreement != 'noSignal';

  factory MindeaseMoodSummary.fromJson(Map<String, dynamic> json) =>
      MindeaseMoodSummary(
        hasHistory: json['hasHistory'] as bool? ?? false,
        currentMood: json['currentMood'] as String?,
        moodEmotion: json['moodEmotion'] as String?,
        moodScore: (json['moodScore'] as num?)?.toInt(),
        trendDirection: json['trendDirection'] as String?,
        trendDescription: json['trendDescription'] as String?,
        historyCount: (json['historyCount'] as num?)?.toInt(),
        cameraEmotion: json['cameraEmotion'] as String?,
        signalAgreement: json['signalAgreement'] as String?,
      );

  static const empty = MindeaseMoodSummary(hasHistory: false);
}

/// Plain-language camera-signal line for mood cards, or null when no usable
/// signal is attached. Display names come from [displayName]; agreement copy
/// never overrides the self-report. Numbers and internals are never shown.
String? cameraSignalLine(
  String? cameraEmotion,
  String? signalAgreement,
  String Function(String canonical) displayName,
) {
  if (cameraEmotion == null ||
      cameraEmotion.isEmpty ||
      cameraEmotion == 'unknown' ||
      signalAgreement == null ||
      signalAgreement == 'noSignal') {
    return null;
  }
  final label = displayName(cameraEmotion);
  return switch (signalAgreement) {
    'agree' => 'Camera check-in showed $label — in line with your selection.',
    'close' => 'Camera check-in showed $label — close to your selection.',
    'differs' =>
      'Camera check-in showed $label — different from your selection; your selection stays primary.',
    _ => null,
  };
}

/// One stored assessment from `GET /screenings/me`.
///
/// Only metadata and the answered questionnaire codes are exposed. Clinical
/// scores are computed and owned by the backend; the client never recalculates
/// or infers them from the raw answers.
class MindeaseAssessmentSummary {
  const MindeaseAssessmentSummary({
    required this.id,
    required this.status,
    this.startedAt,
    this.updatedAt,
    this.completedAt,
    this.questionnaireCodes = const [],
  });

  final String id;
  final String status;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final List<String> questionnaireCodes;

  bool get isCompleted => status == 'COMPLETED';

  /// Best timestamp to display, newest known first.
  DateTime? get recordedAt => completedAt ?? updatedAt ?? startedAt;

  factory MindeaseAssessmentSummary.fromJson(Map<String, dynamic> json) {
    final assessments = json['assessments'];
    final codes = <String>[];
    if (assessments is Map) {
      for (final entry in assessments.entries) {
        final answers = entry.value;
        if (answers is List && answers.isNotEmpty) {
          codes.add(entry.key.toString());
        }
      }
    }
    return MindeaseAssessmentSummary(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'IN_PROGRESS',
      startedAt: _parseInstant(json['startedAt']),
      updatedAt: _parseInstant(json['updatedAt']),
      completedAt: _parseInstant(json['completedAt']),
      questionnaireCodes: codes,
    );
  }
}

/// Combined mental + physical insight from `GET /wellness/combined-insight`.
///
/// [generatedBy] is `llm` only when the AI service produced validated wording;
/// it is `rules` for the deterministic composer. The UI must label those cases
/// differently instead of claiming AI authorship for rule-based text.
class MindeaseCombinedInsight {
  const MindeaseCombinedInsight({
    required this.available,
    this.narrative,
    this.suggestions = const [],
    this.generatedBy,
    this.safetyFlag = false,
    this.note,
    this.cached = false,
    this.coverage,
  });

  final bool available;
  final String? narrative;
  final List<MindeaseInsightSuggestion> suggestions;
  final String? generatedBy;
  final bool safetyFlag;
  final String? note;
  final bool cached;
  final MindeaseInsightCoverage? coverage;

  bool get isAiWording => available && generatedBy == 'llm';

  factory MindeaseCombinedInsight.fromJson(Map<String, dynamic> json) {
    return MindeaseCombinedInsight(
      available: json['available'] as bool? ?? false,
      narrative: json['narrative'] as String?,
      suggestions: [
        for (final item in (json['suggestions'] as List?) ?? const [])
          if (item is Map<String, dynamic>)
            MindeaseInsightSuggestion.fromJson(item),
      ],
      generatedBy: json['generatedBy'] as String?,
      safetyFlag: json['safetyFlag'] as bool? ?? false,
      note: json['note'] as String?,
      cached: json['cached'] as bool? ?? false,
      coverage: json['coverage'] is Map<String, dynamic>
          ? MindeaseInsightCoverage.fromJson(
              json['coverage'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  static const unavailable = MindeaseCombinedInsight(available: false);
}

class MindeaseInsightSuggestion {
  const MindeaseInsightSuggestion({
    required this.title,
    required this.description,
    this.category,
  });

  final String title;
  final String description;
  final String? category;

  factory MindeaseInsightSuggestion.fromJson(Map<String, dynamic> json) =>
      MindeaseInsightSuggestion(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: json['category'] as String?,
      );
}

class MindeaseInsightCoverage {
  const MindeaseInsightCoverage({
    required this.windowDays,
    required this.daysWithActivity,
    required this.daysWithSleep,
    required this.daysWithHydration,
    required this.moodCheckins,
  });

  final int windowDays;
  final int daysWithActivity;
  final int daysWithSleep;
  final int daysWithHydration;
  final int moodCheckins;

  factory MindeaseInsightCoverage.fromJson(Map<String, dynamic> json) =>
      MindeaseInsightCoverage(
        windowDays: (json['windowDays'] as num?)?.toInt() ?? 0,
        daysWithActivity: (json['daysWithActivity'] as num?)?.toInt() ?? 0,
        daysWithSleep: (json['daysWithSleep'] as num?)?.toInt() ?? 0,
        daysWithHydration: (json['daysWithHydration'] as num?)?.toInt() ?? 0,
        moodCheckins: (json['moodCheckins'] as num?)?.toInt() ?? 0,
      );
}

DateTime? _parseInstant(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}


/// One actionable suggestion returned with an analysis.
/// A validated, data-supported target suggested by an analysis. Applying it is
/// always an explicit user action and never silently overwrites a user target.
class GoalTargetSuggestion {
  const GoalTargetSuggestion({
    required this.metric,
    required this.value,
    required this.unit,
    required this.rationale,
  });

  /// Backend goal field name, e.g. `dailySteps`.
  final String metric;
  final int value;
  final String unit;
  final String rationale;

  factory GoalTargetSuggestion.fromJson(Map<String, dynamic> json) {
    return GoalTargetSuggestion(
      metric: json['metric'] as String? ?? '',
      value: (json['value'] as num?)?.toInt() ?? 0,
      unit: json['unit'] as String? ?? '',
      rationale: json['rationale'] as String? ?? '',
    );
  }
}

class WellnessAnalysisAdvice {
  const WellnessAnalysisAdvice({
    required this.title,
    required this.description,
    this.category,
  });

  final String title;
  final String description;
  final String? category;

  factory WellnessAnalysisAdvice.fromJson(Map<String, dynamic> json) {
    return WellnessAnalysisAdvice(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String?,
    );
  }
}

/// One aspect diffed between the previous analysis and this one.
class WellnessComparisonChange {
  const WellnessComparisonChange({
    required this.aspect,
    required this.previous,
    required this.current,
    required this.direction,
    this.explanation,
  });

  final String aspect;
  final String previous;
  final String current;

  /// IMPROVED, DECLINED or UNCHANGED.
  final String direction;
  final String? explanation;

  factory WellnessComparisonChange.fromJson(Map<String, dynamic> json) {
    return WellnessComparisonChange(
      aspect: json['aspect'] as String? ?? '',
      previous: json['previous'] as String? ?? '—',
      current: json['current'] as String? ?? '—',
      direction: json['direction'] as String? ?? 'UNCHANGED',
      explanation: json['explanation'] as String?,
    );
  }
}

/// Deterministic comparison against the previous stored analysis.
class WellnessAnalysisComparison {
  const WellnessAnalysisComparison({
    required this.hasPrevious,
    this.previousAnalyzedAt,
    this.daysSincePrevious,
    this.overall,
    this.summary,
    required this.changes,
    required this.improved,
    required this.declined,
    required this.unchanged,
    required this.habitInsights,
    required this.nextActions,
  });

  final bool hasPrevious;
  final DateTime? previousAnalyzedAt;
  final int? daysSincePrevious;
  final String? overall;
  final String? summary;
  final List<WellnessComparisonChange> changes;
  final List<String> improved;
  final List<String> declined;
  final List<String> unchanged;
  final List<String> habitInsights;
  final List<String> nextActions;

  factory WellnessAnalysisComparison.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return WellnessAnalysisComparison(
      hasPrevious: json['hasPrevious'] as bool? ?? false,
      previousAnalyzedAt: json['previousAnalyzedAt'] == null
          ? null
          : DateTime.parse(json['previousAnalyzedAt'] as String).toUtc(),
      daysSincePrevious: (json['daysSincePrevious'] as num?)?.toInt(),
      overall: json['overall'] as String?,
      summary: json['summary'] as String?,
      changes: (json['changes'] as List?)
              ?.map((e) => WellnessComparisonChange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      improved: strings('improved'),
      declined: strings('declined'),
      unchanged: strings('unchanged'),
      habitInsights: strings('habitInsights'),
      nextActions: strings('nextActions'),
    );
  }
}

List<WellnessAnalysisAdvice> _adviceFrom(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(WellnessAnalysisAdvice.fromJson)
      .toList();
}

List<String> _stringListFrom(Object? raw) =>
    (raw as List?)?.map((e) => e.toString()).toList() ?? const [];

List<GoalTargetSuggestion> _goalSuggestionsFrom(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(GoalTargetSuggestion.fromJson)
      .toList();
}

class MentalWellnessAnalysis {
  const MentalWellnessAnalysis({
    required this.analysisId,
    required this.type,
    required this.analyzedAt,
    required this.available,
    this.wellnessScore,
    this.stressLevel,
    this.lifestyleScore,
    this.sleepQuality,
    this.primaryFocus,
    this.insight,
    required this.recommendations,
    required this.generatedBy,
    required this.safetyFlag,
    required this.cached,
    this.note,
    this.inputSummary,
    this.provenance,
    this.advice = const [],
    this.focusAreas = const [],
    this.nextActions = const [],
    this.comparison,
    this.goalTargetSuggestions = const [],
  });

  final String? analysisId;
  final String? type;
  final DateTime analyzedAt;
  final bool available;
  final int? wellnessScore;
  final String? stressLevel;
  final int? lifestyleScore;
  final String? sleepQuality;
  final String? primaryFocus;
  final String? insight;
  final List<String> recommendations;
  final String generatedBy;
  final bool safetyFlag;
  final bool cached;
  final String? note;
  final MentalAnalysisInputSummary? inputSummary;
  final MentalAnalysisProvenance? provenance;
  final List<WellnessAnalysisAdvice> advice;
  final List<String> focusAreas;
  final List<String> nextActions;
  final WellnessAnalysisComparison? comparison;
  final List<GoalTargetSuggestion> goalTargetSuggestions;

  factory MentalWellnessAnalysis.fromJson(Map<String, dynamic> json) {
    return MentalWellnessAnalysis(
      analysisId: json['analysisId'] as String?,
      type: json['type'] as String?,
      analyzedAt: json['analyzedAt'] == null
          ? DateTime.now().toUtc()
          : DateTime.parse(json['analyzedAt'] as String).toUtc(),
      available: json['available'] as bool? ?? false,
      wellnessScore: json['wellnessScore'] as int?,
      stressLevel: json['stressLevel'] as String?,
      lifestyleScore: json['lifestyleScore'] as int?,
      sleepQuality: json['sleepQuality'] as String?,
      primaryFocus: json['primaryFocus'] as String?,
      insight: json['insight'] as String?,
      recommendations: (json['recommendations'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      generatedBy: json['generatedBy'] as String? ?? 'rules',
      safetyFlag: json['safetyFlag'] as bool? ?? false,
      cached: json['cached'] as bool? ?? false,
      note: json['note'] as String?,
      inputSummary: json['inputSummary'] == null
          ? null
          : MentalAnalysisInputSummary.fromJson(
              json['inputSummary'] as Map<String, dynamic>),
      provenance: json['provenance'] == null
          ? null
          : MentalAnalysisProvenance.fromJson(
              json['provenance'] as Map<String, dynamic>),
      advice: _adviceFrom(json['advice']),
      focusAreas: _stringListFrom(json['focusAreas']),
      nextActions: _stringListFrom(json['nextActions']),
      comparison: json['comparison'] == null
          ? null
          : WellnessAnalysisComparison.fromJson(
              json['comparison'] as Map<String, dynamic>),
      goalTargetSuggestions: _goalSuggestionsFrom(json['goalTargetSuggestions']),
    );
  }
}

class MentalAnalysisInputSummary {
  const MentalAnalysisInputSummary({
    required this.hasWellnessProfile,
    required this.hasRecentAssessment,
    required this.hasMoodData,
    this.assessmentCount,
    this.latestAssessmentAt,
    this.latestMoodAt,
  });

  final bool hasWellnessProfile;
  final bool hasRecentAssessment;
  final bool hasMoodData;
  final int? assessmentCount;
  final DateTime? latestAssessmentAt;
  final DateTime? latestMoodAt;

  factory MentalAnalysisInputSummary.fromJson(Map<String, dynamic> json) {
    return MentalAnalysisInputSummary(
      hasWellnessProfile: json['hasWellnessProfile'] as bool? ?? false,
      hasRecentAssessment: json['hasRecentAssessment'] as bool? ?? false,
      hasMoodData: json['hasMoodData'] as bool? ?? false,
      assessmentCount: json['assessmentCount'] as int?,
      latestAssessmentAt: json['latestAssessmentAt'] == null
          ? null
          : DateTime.parse(json['latestAssessmentAt'] as String).toUtc(),
      latestMoodAt: json['latestMoodAt'] == null
          ? null
          : DateTime.parse(json['latestMoodAt'] as String).toUtc(),
    );
  }
}

class MentalAnalysisProvenance {
  const MentalAnalysisProvenance({
    required this.source,
    required this.schemaVersion,
    required this.inputReferences,
    required this.analyzedAt,
  });

  final String source;
  final String schemaVersion;
  final List<String> inputReferences;
  final DateTime analyzedAt;

  factory MentalAnalysisProvenance.fromJson(Map<String, dynamic> json) {
    return MentalAnalysisProvenance(
      source: json['source'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as String? ?? '1.0',
      inputReferences: (json['inputReferences'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      analyzedAt: json['analyzedAt'] == null
          ? DateTime.now().toUtc()
          : DateTime.parse(json['analyzedAt'] as String).toUtc(),
    );
  }
}

class PhysicalWellnessAnalysis {
  const PhysicalWellnessAnalysis({
    required this.analysisId,
    required this.type,
    required this.analyzedAt,
    required this.available,
    this.status,
    this.metrics,
    required this.patterns,
    required this.recommendations,
    required this.generatedBy,
    required this.cached,
    this.note,
    this.inputSummary,
    this.provenance,
    this.advice = const [],
    this.focusAreas = const [],
    this.nextActions = const [],
    this.comparison,
    this.narrative,
    this.goalTargetSuggestions = const [],
  });

  final String? analysisId;
  final String? type;
  final DateTime analyzedAt;
  final bool available;
  final String? status;
  final PhysicalAnalysisMetrics? metrics;
  final List<String> patterns;
  final List<String> recommendations;
  final String generatedBy;
  final bool cached;
  final String? note;
  final PhysicalAnalysisInputSummary? inputSummary;
  final PhysicalAnalysisProvenance? provenance;
  final List<WellnessAnalysisAdvice> advice;
  final List<String> focusAreas;
  final List<String> nextActions;
  final WellnessAnalysisComparison? comparison;

  /// Personalised summary produced by the analysis; the pattern list is shown
  /// only when the service returned no narrative.
  final String? narrative;
  final List<GoalTargetSuggestion> goalTargetSuggestions;

  factory PhysicalWellnessAnalysis.fromJson(Map<String, dynamic> json) {
    return PhysicalWellnessAnalysis(
      analysisId: json['analysisId'] as String?,
      type: json['type'] as String?,
      analyzedAt: json['analyzedAt'] == null
          ? DateTime.now().toUtc()
          : DateTime.parse(json['analyzedAt'] as String).toUtc(),
      available: json['available'] as bool? ?? false,
      status: json['status'] as String?,
      metrics: json['metrics'] == null
          ? null
          : PhysicalAnalysisMetrics.fromJson(
              json['metrics'] as Map<String, dynamic>),
      patterns: (json['patterns'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      recommendations: (json['recommendations'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      generatedBy: json['generatedBy'] as String? ?? 'rules',
      cached: json['cached'] as bool? ?? false,
      note: json['note'] as String?,
      inputSummary: json['inputSummary'] == null
          ? null
          : PhysicalAnalysisInputSummary.fromJson(
              json['inputSummary'] as Map<String, dynamic>),
      provenance: json['provenance'] == null
          ? null
          : PhysicalAnalysisProvenance.fromJson(
              json['provenance'] as Map<String, dynamic>),
      advice: _adviceFrom(json['advice']),
      focusAreas: _stringListFrom(json['focusAreas']),
      nextActions: _stringListFrom(json['nextActions']),
      comparison: json['comparison'] == null
          ? null
          : WellnessAnalysisComparison.fromJson(
              json['comparison'] as Map<String, dynamic>),
      narrative: json['narrative'] as String?,
      goalTargetSuggestions: _goalSuggestionsFrom(json['goalTargetSuggestions']),
    );
  }
}

class PhysicalAnalysisMetrics {
  const PhysicalAnalysisMetrics({
    this.stepsAverage,
    this.distanceKmAverage,
    this.caloriesAverage,
    this.activeMinutesAverage,
    this.sleepHoursAverage,
    this.sleepMinutesAverage,
    this.heartRateAverage,
    this.spo2Average,
    this.hrvAverage,
    this.hydrationMlAverage,
  });

  final int? stepsAverage;
  final double? distanceKmAverage;
  final int? caloriesAverage;
  final int? activeMinutesAverage;
  final int? sleepHoursAverage;
  final int? sleepMinutesAverage;
  final double? heartRateAverage;
  final double? spo2Average;
  final double? hrvAverage;
  final int? hydrationMlAverage;

  factory PhysicalAnalysisMetrics.fromJson(Map<String, dynamic> json) {
    return PhysicalAnalysisMetrics(
      stepsAverage: json['stepsAverage'] as int?,
      distanceKmAverage: (json['distanceKmAverage'] as num?)?.toDouble(),
      caloriesAverage: json['caloriesAverage'] as int?,
      activeMinutesAverage: json['activeMinutesAverage'] as int?,
      sleepHoursAverage: json['sleepHoursAverage'] as int?,
      sleepMinutesAverage: json['sleepMinutesAverage'] as int?,
      heartRateAverage: (json['heartRateAverage'] as num?)?.toDouble(),
      spo2Average: (json['spo2Average'] as num?)?.toDouble(),
      hrvAverage: (json['hrvAverage'] as num?)?.toDouble(),
      hydrationMlAverage: json['hydrationMlAverage'] as int?,
    );
  }
}

class PhysicalAnalysisInputSummary {
  const PhysicalAnalysisInputSummary({
    required this.hasWearableData,
    required this.hasRecentSync,
    required this.hasActivityData,
    required this.hasSleepData,
    required this.hasHeartRateData,
    this.daysOfActivity,
    this.daysOfSleep,
    this.latestReadingAt,
    this.latestSyncAt,
  });

  final bool hasWearableData;
  final bool hasRecentSync;
  final bool hasActivityData;
  final bool hasSleepData;
  final bool hasHeartRateData;
  final int? daysOfActivity;
  final int? daysOfSleep;
  final DateTime? latestReadingAt;
  final DateTime? latestSyncAt;

  factory PhysicalAnalysisInputSummary.fromJson(Map<String, dynamic> json) {
    return PhysicalAnalysisInputSummary(
      hasWearableData: json['hasWearableData'] as bool? ?? false,
      hasRecentSync: json['hasRecentSync'] as bool? ?? false,
      hasActivityData: json['hasActivityData'] as bool? ?? false,
      hasSleepData: json['hasSleepData'] as bool? ?? false,
      hasHeartRateData: json['hasHeartRateData'] as bool? ?? false,
      daysOfActivity: json['daysOfActivity'] as int?,
      daysOfSleep: json['daysOfSleep'] as int?,
      latestReadingAt: json['latestReadingAt'] == null
          ? null
          : DateTime.parse(json['latestReadingAt'] as String).toUtc(),
      latestSyncAt: json['latestSyncAt'] == null
          ? null
          : DateTime.parse(json['latestSyncAt'] as String).toUtc(),
    );
  }
}

class PhysicalAnalysisProvenance {
  const PhysicalAnalysisProvenance({
    required this.source,
    required this.schemaVersion,
    required this.inputReferences,
    required this.analyzedAt,
  });

  final String source;
  final String schemaVersion;
  final List<String> inputReferences;
  final DateTime analyzedAt;

  factory PhysicalAnalysisProvenance.fromJson(Map<String, dynamic> json) {
    return PhysicalAnalysisProvenance(
      source: json['source'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as String? ?? '1.0',
      inputReferences: (json['inputReferences'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      analyzedAt: json['analyzedAt'] == null
          ? DateTime.now().toUtc()
          : DateTime.parse(json['analyzedAt'] as String).toUtc(),
    );
  }
}

class CombinedWellnessAnalysis {
  const CombinedWellnessAnalysis({
    required this.analysisId,
    required this.type,
    required this.analyzedAt,
    required this.available,
    this.overallStatus,
    this.narrative,
    required this.suggestions,
    required this.correlations,
    required this.cautions,
    required this.generatedBy,
    required this.safetyFlag,
    required this.cached,
    this.note,
    this.inputSummary,
    this.provenance,
    this.advice = const [],
    this.focusAreas = const [],
    this.nextActions = const [],
    this.comparison,
    this.goalTargetSuggestions = const [],
  });

  final String? analysisId;
  final String? type;
  final DateTime analyzedAt;
  final bool available;
  final String? overallStatus;
  final String? narrative;
  final List<CombinedAnalysisSuggestion> suggestions;
  final List<String> correlations;
  final List<String> cautions;
  final String generatedBy;
  final bool safetyFlag;
  final bool cached;
  final String? note;
  final CombinedAnalysisInputSummary? inputSummary;
  final CombinedAnalysisProvenance? provenance;
  final List<WellnessAnalysisAdvice> advice;
  final List<String> focusAreas;
  final List<String> nextActions;
  final WellnessAnalysisComparison? comparison;
  final List<GoalTargetSuggestion> goalTargetSuggestions;

  factory CombinedWellnessAnalysis.fromJson(Map<String, dynamic> json) {
    return CombinedWellnessAnalysis(
      analysisId: json['analysisId'] as String?,
      type: json['type'] as String?,
      analyzedAt: json['analyzedAt'] == null
          ? DateTime.now().toUtc()
          : DateTime.parse(json['analyzedAt'] as String).toUtc(),
      available: json['available'] as bool? ?? false,
      overallStatus: json['overallStatus'] as String?,
      narrative: json['narrative'] as String?,
      suggestions: (json['suggestions'] as List?)
              ?.map((e) => CombinedAnalysisSuggestion.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      correlations: (json['correlations'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      cautions: (json['cautions'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      generatedBy: json['generatedBy'] as String? ?? 'rules',
      safetyFlag: json['safetyFlag'] as bool? ?? false,
      cached: json['cached'] as bool? ?? false,
      note: json['note'] as String?,
      inputSummary: json['inputSummary'] == null
          ? null
          : CombinedAnalysisInputSummary.fromJson(
              json['inputSummary'] as Map<String, dynamic>),
      provenance: json['provenance'] == null
          ? null
          : CombinedAnalysisProvenance.fromJson(
              json['provenance'] as Map<String, dynamic>),
      advice: _adviceFrom(json['advice']),
      focusAreas: _stringListFrom(json['focusAreas']),
      nextActions: _stringListFrom(json['nextActions']),
      comparison: json['comparison'] == null
          ? null
          : WellnessAnalysisComparison.fromJson(
              json['comparison'] as Map<String, dynamic>),
      goalTargetSuggestions: _goalSuggestionsFrom(json['goalTargetSuggestions']),
    );
  }
}

class CombinedAnalysisSuggestion {
  const CombinedAnalysisSuggestion({
    required this.title,
    required this.description,
    this.category,
  });

  final String title;
  final String description;
  final String? category;

  factory CombinedAnalysisSuggestion.fromJson(Map<String, dynamic> json) {
    return CombinedAnalysisSuggestion(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String?,
    );
  }
}

class CombinedAnalysisInputSummary {
  const CombinedAnalysisInputSummary({
    required this.mentalAvailable,
    required this.physicalAvailable,
    required this.hasSufficientData,
    this.mentalWellnessScore,
    this.physicalDataDays,
    this.latestMentalAt,
    this.latestPhysicalAt,
  });

  final bool mentalAvailable;
  final bool physicalAvailable;
  final bool hasSufficientData;
  final int? mentalWellnessScore;
  final int? physicalDataDays;
  final DateTime? latestMentalAt;
  final DateTime? latestPhysicalAt;

  factory CombinedAnalysisInputSummary.fromJson(Map<String, dynamic> json) {
    return CombinedAnalysisInputSummary(
      mentalAvailable: json['mentalAvailable'] as bool? ?? false,
      physicalAvailable: json['physicalAvailable'] as bool? ?? false,
      hasSufficientData: json['hasSufficientData'] as bool? ?? false,
      mentalWellnessScore: json['mentalWellnessScore'] as int?,
      physicalDataDays: json['physicalDataDays'] as int?,
      latestMentalAt: json['latestMentalAt'] == null
          ? null
          : DateTime.parse(json['latestMentalAt'] as String).toUtc(),
      latestPhysicalAt: json['latestPhysicalAt'] == null
          ? null
          : DateTime.parse(json['latestPhysicalAt'] as String).toUtc(),
    );
  }
}

class CombinedAnalysisProvenance {
  const CombinedAnalysisProvenance({
    required this.source,
    required this.schemaVersion,
    required this.inputReferences,
    required this.analyzedAt,
  });

  final String source;
  final String schemaVersion;
  final List<String> inputReferences;
  final DateTime analyzedAt;

  factory CombinedAnalysisProvenance.fromJson(Map<String, dynamic> json) {
    return CombinedAnalysisProvenance(
      source: json['source'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as String? ?? '1.0',
      inputReferences: (json['inputReferences'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      analyzedAt: json['analyzedAt'] == null
          ? DateTime.now().toUtc()
          : DateTime.parse(json['analyzedAt'] as String).toUtc(),
    );
  }
}
