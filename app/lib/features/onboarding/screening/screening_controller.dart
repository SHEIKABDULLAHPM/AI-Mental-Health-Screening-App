import 'package:flutter/foundation.dart';

import 'data/questionnaires.dart';

enum ScreeningArea { personal, lifestyle, phq, gad, pss, who, review }

class PersonalInfoData {
  String age = '';
  String gender = '';
  String occupation = '';

  bool get isComplete =>
      age.trim().isNotEmpty &&
      gender.trim().isNotEmpty &&
      occupation.trim().isNotEmpty;
}

/// Manages the multi-step onboarding screening state. Question content comes
/// from the backend catalog ([loadCatalog]) — nothing is hardcoded here.
class ScreeningController extends ChangeNotifier {
  final PersonalInfoData personal = PersonalInfoData();
  final Map<LifestyleField, double> lifestyle = {};
  final List<int> phq = [];
  final List<int> gad = [];
  final List<int> pss = [];
  final List<int> who = [];

  ScreeningCatalog? _catalog;

  static const int personalIndex = 0;
  static const int lifestyleIndex = 1;
  static const int phqIndex = 2;
  static const int gadIndex = 3;
  static const int pssIndex = 4;
  static const int whoIndex = 5;
  static const int reviewIndex = 6;
  static const int totalSteps = 7;

  int stepIndex = 0;
  int questionIndex = 0;

  /// Whether the backend catalog has been loaded for this run.
  bool get catalogLoaded => _catalog != null;

  ScreeningCatalog get catalog => _catalog!;

  List<QuestionnaireItem> get phqItems => _catalog?.phqItems ?? const [];
  List<QuestionnaireItem> get gadItems => _catalog?.gadItems ?? const [];
  List<QuestionnaireItem> get pssItems => _catalog?.pssItems ?? const [];
  List<QuestionnaireItem> get whoItems => _catalog?.whoItems ?? const [];
  List<LifestyleQuestion> get lifestyleQuestions =>
      _catalog?.lifestyleQuestions ?? const [];

  /// Loads the catalog and sizes the answer lists to its questionnaires.
  void loadCatalog(ScreeningCatalog catalog) {
    _catalog = catalog;
    _resizeAnswers();
    stepIndex = 0;
    questionIndex = 0;
    notifyListeners();
  }

  void _resizeAnswers() {
    _fillTo(phq, phqItems.length);
    _fillTo(gad, gadItems.length);
    _fillTo(pss, pssItems.length);
    _fillTo(who, whoItems.length);
  }

  static void _fillTo(List<int> list, int length) {
    list.clear();
    list.addAll(List.filled(length, -1));
  }

  ScreeningArea get area => switch (stepIndex) {
        lifestyleIndex => ScreeningArea.lifestyle,
        phqIndex => ScreeningArea.phq,
        gadIndex => ScreeningArea.gad,
        pssIndex => ScreeningArea.pss,
        whoIndex => ScreeningArea.who,
        reviewIndex => ScreeningArea.review,
        _ => ScreeningArea.personal,
      };

  bool get isQuestionArea =>
      area != ScreeningArea.personal && area != ScreeningArea.review;

  int get totalQuestions =>
      1 +
      lifestyleQuestions.length +
      phq.length +
      gad.length +
      pss.length +
      who.length;

  int get answeredCount {
    var count = personal.isComplete ? 1 : 0;
    count += lifestyle.length;
    count += phq.where((e) => e >= 0).length;
    count += gad.where((e) => e >= 0).length;
    count += pss.where((e) => e >= 0).length;
    count += who.where((e) => e >= 0).length;
    return count;
  }

  bool get isComplete {
    if (!personal.isComplete) return false;
    if (lifestyle.length != lifestyleQuestions.length) return false;
    return _allAnswered(phq) &&
        _allAnswered(gad) &&
        _allAnswered(pss) &&
        _allAnswered(who);
  }

  bool _allAnswered(List<int> list) => list.every((e) => e >= 0);

  int get currentStepItems => switch (area) {
        ScreeningArea.personal => 1,
        ScreeningArea.lifestyle => lifestyleQuestions.length,
        ScreeningArea.phq => phq.length,
        ScreeningArea.gad => gad.length,
        ScreeningArea.pss => pss.length,
        ScreeningArea.who => who.length,
        ScreeningArea.review => 1,
      };

  QuestionnaireItem? get currentQuestion => switch (area) {
        ScreeningArea.phq => _at(phqItems, questionIndex),
        ScreeningArea.gad => _at(gadItems, questionIndex),
        ScreeningArea.pss => _at(pssItems, questionIndex),
        ScreeningArea.who => _at(whoItems, questionIndex),
        _ => null,
      };

  static QuestionnaireItem? _at(List<QuestionnaireItem> items, int index) =>
      index >= 0 && index < items.length ? items[index] : null;

  int get currentAnswer => switch (area) {
        ScreeningArea.phq => _valueAt(phq, questionIndex),
        ScreeningArea.gad => _valueAt(gad, questionIndex),
        ScreeningArea.pss => _valueAt(pss, questionIndex),
        ScreeningArea.who => _valueAt(who, questionIndex),
        _ => -1,
      };

  static int _valueAt(List<int> list, int index) =>
      index >= 0 && index < list.length ? list[index] : -1;

  String get areaLabel {
    final catalog = _catalog;
    return switch (area) {
      ScreeningArea.personal => 'Personal Information',
      ScreeningArea.lifestyle => 'Lifestyle Assessment',
      ScreeningArea.phq => catalog?.phqTitle ?? 'PHQ-9 Assessment',
      ScreeningArea.gad => catalog?.gadTitle ?? 'GAD-7 Assessment',
      ScreeningArea.pss => catalog?.pssTitle ?? 'PSS Assessment',
      ScreeningArea.who => catalog?.whoTitle ?? 'WHO-5 Assessment',
      ScreeningArea.review => 'Review Your Answers',
    };
  }

  String get stepLabel => 'Step ${stepIndex + 1} of $totalSteps';

  bool get canContinue => switch (area) {
        ScreeningArea.personal => personal.isComplete,
        ScreeningArea.lifestyle =>
          _lifestyleAt(questionIndex) != null &&
              lifestyle.containsKey(_lifestyleAt(questionIndex)!.field),
        ScreeningArea.phq => _valueAt(phq, questionIndex) >= 0,
        ScreeningArea.gad => _valueAt(gad, questionIndex) >= 0,
        ScreeningArea.pss => _valueAt(pss, questionIndex) >= 0,
        ScreeningArea.who => _valueAt(who, questionIndex) >= 0,
        ScreeningArea.review => isComplete,
      };

  LifestyleQuestion? _lifestyleAt(int index) =>
      index >= 0 && index < lifestyleQuestions.length
          ? lifestyleQuestions[index]
          : null;

  double get progress =>
      (answeredCount / totalQuestions).clamp(0.0, 1.0).toDouble();

  void setPersonal({String? age, String? gender, String? occupation}) {
    if (age != null) personal.age = age;
    if (gender != null) personal.gender = gender;
    if (occupation != null) personal.occupation = occupation;
    notifyListeners();
  }

  void setLifestyle(LifestyleField field, double value) {
    lifestyle[field] = value;
    notifyListeners();
  }

  void setScale(List<int> list, int index, int value) {
    if (index < 0 || index >= list.length) return;
    list[index] = value;
    notifyListeners();
  }

  void setQuestionAnswer(int value) {
    switch (area) {
      case ScreeningArea.phq:
        setScale(phq, questionIndex, value);
        break;
      case ScreeningArea.gad:
        setScale(gad, questionIndex, value);
        break;
      case ScreeningArea.pss:
        setScale(pss, questionIndex, value);
        break;
      case ScreeningArea.who:
        setScale(who, questionIndex, value);
        break;
      case ScreeningArea.lifestyle:
        final question = _lifestyleAt(questionIndex);
        if (question != null) {
          setLifestyle(question.field, value.toDouble());
        }
        break;
      default:
        break;
    }
  }

  void next() {
    switch (area) {
      case ScreeningArea.personal:
        stepIndex = lifestyleIndex;
        questionIndex = 0;
        break;
      case ScreeningArea.review:
        break;
      default:
        if (questionIndex + 1 < currentStepItems) {
          questionIndex++;
        } else if (stepIndex < reviewIndex) {
          stepIndex++;
          questionIndex = 0;
        }
    }
    notifyListeners();
  }

  void back() {
    if (area == ScreeningArea.personal) return;
    if (questionIndex > 0) {
      questionIndex--;
    } else if (stepIndex > lifestyleIndex) {
      stepIndex--;
      questionIndex = _itemsOf(stepIndex) - 1;
    } else if (stepIndex == lifestyleIndex) {
      stepIndex = personalIndex;
      questionIndex = 0;
    }
    notifyListeners();
  }

  void jumpToStep(int step) {
    if (step < 0 || step > reviewIndex) return;
    stepIndex = step;
    questionIndex = 0;
    notifyListeners();
  }

  int _itemsOf(int step) => switch (step) {
        lifestyleIndex => lifestyleQuestions.length,
        phqIndex => phq.length,
        gadIndex => gad.length,
        pssIndex => pss.length,
        whoIndex => who.length,
        _ => 1,
      };
}
