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

  ScreeningArea get area {
    switch (stepIndex) {
      case lifestyleIndex:
        return ScreeningArea.lifestyle;
      case phqIndex:
        return ScreeningArea.phq;
      case gadIndex:
        return ScreeningArea.gad;
      case pssIndex:
        return ScreeningArea.pss;
      case whoIndex:
        return ScreeningArea.who;
      case reviewIndex:
        return ScreeningArea.review;
      default:
        return ScreeningArea.personal;
    }
  }

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

  int get currentStepItems {
    switch (area) {
      case ScreeningArea.personal:
        return 1;
      case ScreeningArea.lifestyle:
        return lifestyleQuestions.length;
      case ScreeningArea.phq:
        return phq.length;
      case ScreeningArea.gad:
        return gad.length;
      case ScreeningArea.pss:
        return pss.length;
      case ScreeningArea.who:
        return who.length;
      case ScreeningArea.review:
        return 1;
    }
  }

  QuestionnaireItem? get currentQuestion {
    switch (area) {
      case ScreeningArea.phq:
        return phq9Items[questionIndex];
      case ScreeningArea.gad:
        return gad7Items[questionIndex];
      case ScreeningArea.pss:
        return pssItems[questionIndex];
      case ScreeningArea.who:
        return who5Items[questionIndex];
      default:
        return null;
    }
  }

  int get currentAnswer {
    switch (area) {
      case ScreeningArea.phq:
        return phq[questionIndex];
      case ScreeningArea.gad:
        return gad[questionIndex];
      case ScreeningArea.pss:
        return pss[questionIndex];
      case ScreeningArea.who:
        return who[questionIndex];
      default:
        return -1;
    }
  }

  String get areaLabel {
    switch (area) {
      case ScreeningArea.personal:
        return 'Personal Information';
      case ScreeningArea.lifestyle:
        return 'Lifestyle Assessment';
      case ScreeningArea.phq:
        return 'PHQ-9 Assessment';
      case ScreeningArea.gad:
        return 'GAD-7 Assessment';
      case ScreeningArea.pss:
        return 'PSS Assessment';
      case ScreeningArea.who:
        return 'WHO-5 Assessment';
      case ScreeningArea.review:
        return 'Review Your Answers';
    }
  }

  String get stepLabel => 'Step ${stepIndex + 1} of $totalSteps';

  bool get canContinue {
    switch (area) {
      case ScreeningArea.personal:
        return personal.isComplete;
      case ScreeningArea.lifestyle:
        return lifestyle.containsKey(lifestyleQuestions[questionIndex].field);
      case ScreeningArea.phq:
        return phq[questionIndex] >= 0;
      case ScreeningArea.gad:
        return gad[questionIndex] >= 0;
      case ScreeningArea.pss:
        return pss[questionIndex] >= 0;
      case ScreeningArea.who:
        return who[questionIndex] >= 0;
      case ScreeningArea.review:
        return isComplete;
    }
  }

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

  int _itemsOf(int step) {
    switch (step) {
      case personalIndex:
        return 1;
      case lifestyleIndex:
        return lifestyleQuestions.length;
      case phqIndex:
        return phq.length;
      case gadIndex:
        return gad.length;
      case pssIndex:
        return pss.length;
      case whoIndex:
        return who.length;
      case reviewIndex:
        return 1;
      default:
        return 1;
    }
  }

  double get progress {
    final raw = answeredCount / totalQuestions;
    return raw.clamp(0.0, 1.0).toDouble();
  }
}
