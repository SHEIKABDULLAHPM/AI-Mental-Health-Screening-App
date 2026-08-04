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
  final String title;
  final String hint;
  final LifestyleInputType type;
  final List<LifestyleChoice> choices;
  final double min;
  final double max;
  final double step;
  final String unit;
}

const phqOptions = [
  ScaleOption(0, 'Not at all'),
  ScaleOption(1, 'Several days'),
  ScaleOption(2, 'More than half the days'),
  ScaleOption(3, 'Nearly every day'),
];

const gadOptions = [
  ScaleOption(0, 'Not at all'),
  ScaleOption(1, 'Several days'),
  ScaleOption(2, 'More than half the days'),
  ScaleOption(3, 'Nearly every day'),
];

const pssOptions = [
  ScaleOption(0, 'Never'),
  ScaleOption(1, 'Almost never'),
  ScaleOption(2, 'Sometimes'),
  ScaleOption(3, 'Fairly often'),
  ScaleOption(4, 'Very often'),
];

const whoOptions = [
  ScaleOption(0, 'At no time'),
  ScaleOption(1, 'Some of the time'),
  ScaleOption(2, 'Less than half of the time'),
  ScaleOption(3, 'More than half of the time'),
  ScaleOption(4, 'Most of the time'),
  ScaleOption(5, 'All of the time'),
];

const phq9Items = <QuestionnaireItem>[
  QuestionnaireItem(
    question: 'Little interest or pleasure in doing things',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: phqOptions,
  ),
  QuestionnaireItem(
    question: 'Feeling down, depressed, or hopeless',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: phqOptions,
  ),
  QuestionnaireItem(
    question: 'Trouble falling or staying asleep, or sleeping too much',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: phqOptions,
  ),
  QuestionnaireItem(
    question: 'Feeling tired or having little energy',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: phqOptions,
  ),
  QuestionnaireItem(
    question: 'Poor appetite or overeating',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: phqOptions,
  ),
  QuestionnaireItem(
    question:
        'Feeling bad about yourself - or that you are a failure or have let yourself or your family down',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: phqOptions,
  ),
  QuestionnaireItem(
    question:
        'Trouble concentrating on things, such as reading the newspaper or watching television',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: phqOptions,
  ),
  QuestionnaireItem(
    question:
        'Moving or speaking so slowly that other people could have noticed. Or the opposite - being so fidgety or restless that you have been moving around a lot more than usual',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: phqOptions,
  ),
  QuestionnaireItem(
    question:
        'Thoughts that you would be better off dead, or of hurting yourself in some way',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: phqOptions,
  ),
];

const gad7Items = <QuestionnaireItem>[
  QuestionnaireItem(
    question: 'Feeling nervous, anxious, or on edge',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: gadOptions,
  ),
  QuestionnaireItem(
    question: 'Not being able to stop or control worrying',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: gadOptions,
  ),
  QuestionnaireItem(
    question: 'Worrying too much about different things',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: gadOptions,
  ),
  QuestionnaireItem(
    question: 'Trouble relaxing',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: gadOptions,
  ),
  QuestionnaireItem(
    question: 'Being so restless that it is hard to sit still',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: gadOptions,
  ),
  QuestionnaireItem(
    question: 'Becoming easily annoyed or irritable',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: gadOptions,
  ),
  QuestionnaireItem(
    question: 'Feeling afraid, as if something awful might happen',
    instruction:
        'Over the last 2 weeks, how often have you been bothered by the following problems?',
    options: gadOptions,
  ),
];

const pssItems = <QuestionnaireItem>[
  QuestionnaireItem(
    question: 'Been upset because of something that happened unexpectedly?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
  QuestionnaireItem(
    question:
        'Felt that you were unable to control the important things in your life?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
  QuestionnaireItem(
    question: 'Felt nervous and stressed?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
  QuestionnaireItem(
    question:
        'Felt confident about your ability to handle your personal problems?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
  QuestionnaireItem(
    question: 'Felt that things were going your way?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
  QuestionnaireItem(
    question:
        'Found that you could not cope with all the things that you had to do?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
  QuestionnaireItem(
    question: 'Been able to control irritations in your life?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
  QuestionnaireItem(
    question: 'Felt that you were on top of things?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
  QuestionnaireItem(
    question:
        'Been angered because of things that were outside of your control?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
  QuestionnaireItem(
    question:
        'Felt difficulties were piling up so high that you could not overcome them?',
    instruction:
        'In the last month, how often have you felt or thought the following?',
    options: pssOptions,
  ),
];

const who5Items = <QuestionnaireItem>[
  QuestionnaireItem(
    question: 'I have felt cheerful and in good spirits',
    instruction:
        'Over the last 2 weeks, how much of the time have you felt the following?',
    options: whoOptions,
  ),
  QuestionnaireItem(
    question: 'I have felt calm and relaxed',
    instruction:
        'Over the last 2 weeks, how much of the time have you felt the following?',
    options: whoOptions,
  ),
  QuestionnaireItem(
    question: 'I have felt active and vigorous',
    instruction:
        'Over the last 2 weeks, how much of the time have you felt the following?',
    options: whoOptions,
  ),
  QuestionnaireItem(
    question: 'I woke up feeling fresh and rested',
    instruction:
        'Over the last 2 weeks, how much of the time have you felt the following?',
    options: whoOptions,
  ),
  QuestionnaireItem(
    question: 'My daily life has been filled with things that interest me',
    instruction:
        'Over the last 2 weeks, how much of the time have you felt the following?',
    options: whoOptions,
  ),
];

const exerciseChoices = [
  LifestyleChoice(0, 'Never'),
  LifestyleChoice(1, '1-2 times a week'),
  LifestyleChoice(2, '3-4 times a week'),
  LifestyleChoice(3, '5 or more times a week'),
];

const waterChoices = [
  LifestyleChoice(0, 'Less than 2 glasses'),
  LifestyleChoice(1, '2-4 glasses'),
  LifestyleChoice(2, '5-7 glasses'),
  LifestyleChoice(3, '8 or more glasses'),
];

const lifestyleQuestions = <LifestyleQuestion>[
  LifestyleQuestion(
    field: LifestyleField.sleepHours,
    title: 'How many hours of sleep do you get on an average night?',
    hint: 'Slide to select the number of hours',
    type: LifestyleInputType.slider,
    min: 0,
    max: 12,
    step: 0.5,
    unit: 'hours',
  ),
  LifestyleQuestion(
    field: LifestyleField.exercise,
    title: 'How often do you exercise in a typical week?',
    hint: 'Choose the option that fits best',
    type: LifestyleInputType.choice,
    choices: exerciseChoices,
  ),
  LifestyleQuestion(
    field: LifestyleField.water,
    title: 'How many glasses of water do you drink each day?',
    hint: 'Choose the option that fits best',
    type: LifestyleInputType.choice,
    choices: waterChoices,
  ),
  LifestyleQuestion(
    field: LifestyleField.screenTime,
    title: 'How many hours a day do you spend on screens?',
    hint: 'Slide to select the number of hours',
    type: LifestyleInputType.slider,
    min: 0,
    max: 16,
    step: 0.5,
    unit: 'hours',
  ),
  LifestyleQuestion(
    field: LifestyleField.workingHours,
    title: 'How many hours a day do you work or study?',
    hint: 'Slide to select the number of hours',
    type: LifestyleInputType.slider,
    min: 0,
    max: 14,
    step: 0.5,
    unit: 'hours',
  ),
];
