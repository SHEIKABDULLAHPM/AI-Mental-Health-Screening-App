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
  });

  final String id;
  final String status;
  final int? wellnessScore;
  final String? stressLevel;
  final int? lifestyleScore;
  final String? sleepQuality;
  final String? primaryFocus;
  final String? aiInsight;

  bool get isPending => status == 'AI_ANALYSIS_PENDING';

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
            if (q is Map<String, dynamic>)
              MindeaseQuestionnaire.fromJson(q),
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
  });

  final String name;
  final bool aiReady;
  final String aiStatus;
  final int? wellnessScore;
  final String? todayInsight;

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
    );
  }
}
