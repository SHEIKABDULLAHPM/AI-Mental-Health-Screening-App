import 'package:mindease/features/onboarding/screening/data/questionnaires.dart';
import 'package:mindease/features/onboarding/screening/screening_controller.dart';

enum StressLevel { low, moderate, high }

enum SleepQuality { poor, fair, good }

enum WellnessFocus { stressManagement, sleep, moodSupport, wellbeing, balance }

class WellnessReport {
  const WellnessReport({
    required this.wellnessScore,
    required this.stressLevel,
    required this.lifestyleScore,
    required this.sleepQuality,
    required this.focus,
    required this.aiInsight,
    required this.phqTotal,
    required this.gadTotal,
    required this.pssTotal,
    required this.whoPercent,
  });

  final int wellnessScore;
  final StressLevel stressLevel;
  final int lifestyleScore;
  final SleepQuality sleepQuality;
  final WellnessFocus focus;
  final String aiInsight;
  final int phqTotal;
  final int gadTotal;
  final int pssTotal;
  final int whoPercent;

  String get focusLabel => switch (focus) {
        WellnessFocus.stressManagement => 'Stress Management',
        WellnessFocus.sleep => 'Sleep & Rest',
        WellnessFocus.moodSupport => 'Mood Support',
        WellnessFocus.wellbeing => 'Positive Wellbeing',
        WellnessFocus.balance => 'Maintain Balance',
      };

  String get stressLabel => switch (stressLevel) {
        StressLevel.low => 'Low',
        StressLevel.moderate => 'Moderate',
        StressLevel.high => 'High',
      };

  String get sleepLabel => switch (sleepQuality) {
        SleepQuality.poor => 'Poor',
        SleepQuality.fair => 'Fair',
        SleepQuality.good => 'Good',
      };
}

/// Deterministic wellbeing scoring from validated questionnaires.
class WellnessEngine {
  WellnessEngine._();

  static WellnessReport compute(ScreeningController controller) {
    final phqTotal = _sum(controller.phq);
    final gadTotal = _sum(controller.gad);
    final pssTotal = _pssScore(controller.pss);
    final whoRaw = _sum(controller.who);
    final whoPercent = (whoRaw * 4).clamp(0, 100).toInt();

    final phqScore = 100 * (27 - phqTotal) / 27;
    final gadScore = 100 * (21 - gadTotal) / 21;
    final pssScore = 100 - (pssTotal / 40 * 100);
    final wellnessScore =
        (0.3 * phqScore + 0.25 * gadScore + 0.2 * pssScore + 0.25 * whoPercent)
            .round()
            .clamp(0, 100)
            .toInt();

    final stress = _stressLevel(gadTotal, pssTotal);
    final sleep =
        _sleepQuality(controller.lifestyle[LifestyleField.sleepHours]);
    final lifestyleScore = _lifestyleScore(controller.lifestyle);
    final focus = _focus(stress, sleep, phqTotal, whoPercent);

    return WellnessReport(
      wellnessScore: wellnessScore,
      stressLevel: stress,
      lifestyleScore: lifestyleScore,
      sleepQuality: sleep,
      focus: focus,
      aiInsight:
          _insight(focus, phqTotal, gadTotal, pssTotal, whoPercent, sleep),
      phqTotal: phqTotal,
      gadTotal: gadTotal,
      pssTotal: pssTotal,
      whoPercent: whoPercent,
    );
  }

  static int _sum(List<int> values) =>
      values.where((e) => e >= 0).fold(0, (a, b) => a + b);

  static int _pssScore(List<int> pss) {
    var total = 0;
    for (var i = 0; i < pss.length; i++) {
      final v = pss[i];
      if (v < 0) continue;
      total += (i == 3 || i == 4 || i == 6 || i == 7) ? 4 - v : v;
    }
    return total;
  }

  static StressLevel _stressLevel(int gadTotal, int pssTotal) {
    final gadLvl = gadTotal <= 4
        ? 0
        : gadTotal <= 9
            ? 1
            : gadTotal <= 14
                ? 2
                : 3;
    final pssLvl = pssTotal <= 13
        ? 0
        : pssTotal <= 26
            ? 1
            : 2;
    final maxLvl = gadLvl > pssLvl ? gadLvl : pssLvl;
    if (maxLvl <= 1) return StressLevel.low;
    if (maxLvl == 2) return StressLevel.moderate;
    return StressLevel.high;
  }

  static SleepQuality _sleepQuality(double? hours) {
    if (hours == null) return SleepQuality.fair;
    if (hours >= 7 && hours <= 9) return SleepQuality.good;
    if (hours >= 5) return SleepQuality.fair;
    return SleepQuality.poor;
  }

  static int _lifestyleScore(Map<LifestyleField, double> lifestyle) {
    var points = 0.0;
    var count = 0;

    final sleep = lifestyle[LifestyleField.sleepHours];
    if (sleep != null) {
      count++;
      points += sleep >= 7 && sleep <= 9
          ? 100
          : sleep >= 6 || sleep == 10
              ? 70
              : sleep >= 5 || sleep == 11
                  ? 45
                  : 20;
    }
    final exercise = lifestyle[LifestyleField.exercise];
    if (exercise != null) {
      count++;
      points += [20, 50, 80, 100][exercise.round()];
    }
    final water = lifestyle[LifestyleField.water];
    if (water != null) {
      count++;
      points += [25, 50, 75, 100][water.round()];
    }
    final screen = lifestyle[LifestyleField.screenTime];
    if (screen != null) {
      count++;
      points += screen < 3
          ? 100
          : screen <= 6
              ? 80
              : screen <= 9
                  ? 55
                  : 30;
    }
    final work = lifestyle[LifestyleField.workingHours];
    if (work != null) {
      count++;
      points += work <= 8
          ? 90
          : work <= 10
              ? 70
              : work <= 12
                  ? 50
                  : 30;
    }

    return count == 0 ? 0 : (points / count).round().clamp(0, 100).toInt();
  }

  static WellnessFocus _focus(
    StressLevel stress,
    SleepQuality sleep,
    int phqTotal,
    int whoPercent,
  ) {
    if (stress == StressLevel.high) return WellnessFocus.stressManagement;
    if (sleep == SleepQuality.poor) return WellnessFocus.sleep;
    if (phqTotal >= 10) return WellnessFocus.moodSupport;
    if (whoPercent < 50) return WellnessFocus.wellbeing;
    return WellnessFocus.balance;
  }

  static String _insight(
    WellnessFocus focus,
    int phq,
    int gad,
    int pss,
    int who,
    SleepQuality sleep,
  ) {
    final parts = <String>[];
    parts.add('Your responses suggest ${_summaryLine(phq, gad, pss, who)}.');
    switch (focus) {
      case WellnessFocus.stressManagement:
        parts.add(
            'Your primary focus for the coming week is stress management.',);
        parts.add(
          'Try the 4-7-8 breathing technique and short mindful walks whenever '
          'you feel overwhelmed.',
        );
        break;
      case WellnessFocus.sleep:
        parts.add(
            'Improving your sleep is the highest-impact step you can take right now.',);
        parts.add(
            'Aim for 7-9 hours of rest and keep a consistent bedtime schedule.',);
        break;
      case WellnessFocus.moodSupport:
        parts.add('Your primary focus is mood support.');
        parts.add(
          'Small daily wins, gentle movement, and talking to someone you trust '
          'can help lift your mood.',
        );
        break;
      case WellnessFocus.wellbeing:
        parts.add('Your primary focus is boosting your everyday wellbeing.');
        parts.add(
          'Nurture activities that bring you joy and stay connected with '
          'people who matter to you.',
        );
        break;
      case WellnessFocus.balance:
        parts.add('Your responses look well-balanced right now.');
        parts.add(
          'Keep up your current routines — consistency is your strongest tool '
          'for staying well.',
        );
        break;
    }
    parts.add(
      'This insight is guidance, not a diagnosis. A mental health professional '
      'can provide a complete evaluation.',
    );
    return parts.join(' ');
  }

  static String _summaryLine(int phq, int gad, int pss, int who) {
    final flags = <String>[];
    if (phq >= 10) {
      flags.add('some signs of low mood');
    } else if (phq >= 5) {
      flags.add('a mild dip in mood');
    }
    if (gad >= 10) {
      flags.add('noticeable anxiety');
    } else if (gad >= 5) {
      flags.add('some anxious feelings');
    }
    if (pss >= 27) {
      flags.add('elevated stress levels');
    } else if (pss >= 14) {
      flags.add('moderate stress');
    }
    if (who < 50) {
      flags.add('lower everyday energy');
    }
    if (flags.isEmpty) return 'a generally balanced state of wellbeing';
    if (flags.length == 1) return flags.first;
    return '${flags.take(flags.length - 1).join(', ')} and ${flags.last}';
  }
}
