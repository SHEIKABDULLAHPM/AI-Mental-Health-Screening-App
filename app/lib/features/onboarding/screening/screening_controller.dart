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

/// Manages the multi-step onboarding screening state.
class ScreeningController extends ChangeNotifier {
  final PersonalInfoData personal = PersonalInfoData();
  final Map<LifestyleField, double> lifestyle = {};
  final List<int> phq = List.filled(9, -1);
  final List<int> gad = List.filled(7, -1);
  final List<int> pss = List.filled(10, -1);
  final List<int> who = List.filled(5, -1);

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
        ScreeningArea.phq => phq9Items[questionIndex],
        ScreeningArea.gad => gad7Items[questionIndex],
        ScreeningArea.pss => pssItems[questionIndex],
        ScreeningArea.who => who5Items[questionIndex],
        _ => null,
      };

  int get currentAnswer => switch (area) {
        ScreeningArea.phq => phq[questionIndex],
        ScreeningArea.gad => gad[questionIndex],
        ScreeningArea.pss => pss[questionIndex],
        ScreeningArea.who => who[questionIndex],
        _ => -1,
      };

  String get areaLabel => switch (area) {
        ScreeningArea.personal => 'Personal Information',
        ScreeningArea.lifestyle => 'Lifestyle Assessment',
        ScreeningArea.phq => 'PHQ-9 Assessment',
        ScreeningArea.gad => 'GAD-7 Assessment',
        ScreeningArea.pss => 'PSS Assessment',
        ScreeningArea.who => 'WHO-5 Assessment',
        ScreeningArea.review => 'Review Your Answers',
      };

  String get stepLabel => 'Step ${stepIndex + 1} of $totalSteps';

  bool get canContinue => switch (area) {
        ScreeningArea.personal => personal.isComplete,
        ScreeningArea.lifestyle =>
          lifestyle.containsKey(lifestyleQuestions[questionIndex].field),
        ScreeningArea.phq => phq[questionIndex] >= 0,
        ScreeningArea.gad => gad[questionIndex] >= 0,
        ScreeningArea.pss => pss[questionIndex] >= 0,
        ScreeningArea.who => who[questionIndex] >= 0,
        ScreeningArea.review => isComplete,
      };

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
        final question = lifestyleQuestions[questionIndex];
        setLifestyle(question.field, value.toDouble());
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
