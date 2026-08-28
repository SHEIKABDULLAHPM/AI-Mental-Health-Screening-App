/// UI-facing models for the screening flow.
///
/// The questionnaire *content* is no longer hardcoded here: it is loaded from
/// the backend catalog (GET /screenings/questions) and mapped into these
/// models by [ScreeningCatalog.fromApi].
library;

import 'package:mindease/core/api/models.dart';

class ScaleOption {
  const ScaleOption(this.value, this.label);

  final int value;
  final String label;
}

class QuestionnaireItem {
  const QuestionnaireItem({
    required this.question,
    required this.instruction,
    required this.options,
  });

  final String question;
  final String instruction;
  final List<ScaleOption> options;
}

enum LifestyleField { sleepHours, exercise, water, screenTime, workingHours }

enum LifestyleInputType { slider, choice }

class LifestyleChoice {
  const LifestyleChoice(this.value, this.label);

  final int value;
  final String label;
}

class LifestyleQuestion {
  const LifestyleQuestion({
    required this.field,
    required this.label,
    required this.title,
    required this.hint,
    required this.type,
    this.choices = const [],
    this.min = 0,
    this.max = 12,
    this.step = 0.5,
    this.unit = '',
  });

  final LifestyleField field;
  final String label;
  final String title;
  final String hint;
  final LifestyleInputType type;
  final List<LifestyleChoice> choices;
  final double min;
  final double max;
  final double step;
  final String unit;
}

/// Server-backed question set for one screening run, mapped from the
/// questionnaire catalog. Provides the ordered clinical questionnaires, the
/// lifestyle questions and the personal-info picker options.
class ScreeningCatalog {
  const ScreeningCatalog({
    required this.version,
    required this.phqItems,
    required this.gadItems,
    required this.pssItems,
    required this.whoItems,
    required this.lifestyleQuestions,
    required this.genderOptions,
    required this.occupationOptions,
    required this.phqTitle,
    required this.gadTitle,
    required this.pssTitle,
    required this.whoTitle,
  });

  final String version;
  final List<QuestionnaireItem> phqItems;
  final List<QuestionnaireItem> gadItems;
  final List<QuestionnaireItem> pssItems;
  final List<QuestionnaireItem> whoItems;
  final List<LifestyleQuestion> lifestyleQuestions;
  final List<String> genderOptions;
  final List<String> occupationOptions;
  final String phqTitle;
  final String gadTitle;
  final String pssTitle;
  final String whoTitle;

  /// Maps the backend catalog into the UI models. Missing questionnaires map
  /// to empty lists so the flow can still degrade gracefully.
  factory ScreeningCatalog.fromApi(MindeaseCatalog api) {
    return ScreeningCatalog(
      version: api.version,
      phqItems: _items(api.byCode('phq9')),
      gadItems: _items(api.byCode('gad7')),
      pssItems: _items(api.byCode('pss10')),
      whoItems: _items(api.byCode('who5')),
      lifestyleQuestions: [
        for (final q in api.lifestyle) _lifestyle(q),
      ],
      genderOptions: api.genderOptions,
      occupationOptions: api.occupationOptions,
      phqTitle: api.byCode('phq9')?.title ?? 'PHQ-9 Assessment',
      gadTitle: api.byCode('gad7')?.title ?? 'GAD-7 Assessment',
      pssTitle: api.byCode('pss10')?.title ?? 'PSS Assessment',
      whoTitle: api.byCode('who5')?.title ?? 'WHO-5 Assessment',
    );
  }

  static List<QuestionnaireItem> _items(MindeaseQuestionnaire? q) {
    if (q == null) return const [];
    final options = [
      for (final o in q.options) ScaleOption(o.value, o.label),
    ];
    return [
      for (final text in q.items)
        QuestionnaireItem(
          question: text,
          instruction: q.instruction,
          options: options,
        ),
    ];
  }

  static LifestyleQuestion _lifestyle(MindeaseLifestyleQuestion q) {
    final field = switch (q.field) {
      'sleepHours' => LifestyleField.sleepHours,
      'exercise' => LifestyleField.exercise,
      'water' => LifestyleField.water,
      'screenTime' => LifestyleField.screenTime,
      'workingHours' => LifestyleField.workingHours,
      _ => LifestyleField.sleepHours,
    };
    final type = q.type == 'choice'
        ? LifestyleInputType.choice
        : LifestyleInputType.slider;
    return LifestyleQuestion(
      field: field,
      label: q.label,
      title: q.title,
      hint: q.hint,
      type: type,
      min: q.min,
      max: q.max,
      step: q.step,
      unit: q.unit,
      choices: [
        for (final c in q.choices) LifestyleChoice(c.value, c.label),
      ],
    );
  }
}
