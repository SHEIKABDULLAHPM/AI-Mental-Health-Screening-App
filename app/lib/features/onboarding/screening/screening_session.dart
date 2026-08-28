import 'package:mindease/features/onboarding/screening/data/questionnaires.dart';
import 'package:mindease/features/onboarding/screening/screening_controller.dart';

/// Shared in-memory state for a single screening run.
///
/// [screeningId] is the backend draft owned by the authenticated user. The
/// wellness report is never fabricated client-side — it is fetched from the
/// backend (GET /wellness-profile) by the profile screen.
class ScreeningSession {
  ScreeningSession._();

  static final ScreeningController controller = ScreeningController();

  /// Remembered first name used to greet the user in review steps.
  static String? firstName;

  /// Id of the in-progress/server draft for the current user, if any.
  static String? screeningId;

  /// Server-reported AI analysis status after submission
  /// (AI_ANALYSIS_PENDING while analysis is paused).
  static String? submissionAiStatus;

  /// Id of the queued AI analysis job returned at submission, if any.
  static String? aiJobId;

  /// Builds the exact payload the backend expects for create/update.
  static Map<String, dynamic> payload(ScreeningController c) {
    final lifestyle = <String, dynamic>{};
    if (c.lifestyle[LifestyleField.sleepHours] != null) {
      lifestyle['sleepHours'] = c.lifestyle[LifestyleField.sleepHours]!;
    }
    if (c.lifestyle[LifestyleField.exercise] != null) {
      lifestyle['exerciseFrequency'] =
          c.lifestyle[LifestyleField.exercise]!.round();
    }
    if (c.lifestyle[LifestyleField.water] != null) {
      lifestyle['waterIntake'] = c.lifestyle[LifestyleField.water]!.round();
    }
    if (c.lifestyle[LifestyleField.screenTime] != null) {
      lifestyle['screenTime'] = c.lifestyle[LifestyleField.screenTime]!;
    }
    if (c.lifestyle[LifestyleField.workingHours] != null) {
      lifestyle['workingHours'] = c.lifestyle[LifestyleField.workingHours]!;
    }

    return <String, dynamic>{
      'personal': <String, dynamic>{
        'age': int.tryParse(c.personal.age.trim()),
        'gender':
            c.personal.gender.trim().isEmpty ? null : c.personal.gender.trim(),
        'occupation': c.personal.occupation.trim().isEmpty
            ? null
            : c.personal.occupation.trim(),
      },
      'lifestyle': lifestyle,
      'assessments': <String, dynamic>{
        'phq9': _answeredPrefix(c.phq),
        'gad7': _answeredPrefix(c.gad),
        'pss10': _answeredPrefix(c.pss),
        'who5': _answeredPrefix(c.who),
      }..removeWhere((_, v) => (v as List).isEmpty),
    };
  }

  static List<int> _answeredPrefix(List<int> answers) {
    final out = <int>[];
    for (final value in answers) {
      if (value < 0) break;
      out.add(value);
    }
    return out;
  }

  static void reset() {
    _clearAnswers();
    controller.stepIndex = 0;
    controller.questionIndex = 0;
    screeningId = null;
    submissionAiStatus = null;
    aiJobId = null;
  }

  /// Fresh run from the wellness-profile screen: clears the questionnaire but
  /// keeps the remembered first name and the loaded catalog.
  static void retake() {
    _clearAnswers();
    controller.jumpToStep(0);
    screeningId = null;
    submissionAiStatus = null;
    aiJobId = null;
  }

  static void _clearAnswers() {
    controller.personal.age = '';
    controller.personal.gender = '';
    controller.personal.occupation = '';
    controller.lifestyle.clear();
    _clearTo(controller.phq);
    _clearTo(controller.gad);
    _clearTo(controller.pss);
    _clearTo(controller.who);
  }

  static void _clearTo(List<int> list) {
    for (var i = 0; i < list.length; i++) {
      list[i] = -1;
    }
  }
}
