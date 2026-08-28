import 'package:mindease/features/future_letters/data/future_letter.dart';

/// UI-ONLY mock letters — delivery scheduling arrives with the backend.
final List<FutureLetter> kFutureLetters = [
  FutureLetter(
    id: 'f1',
    title: 'To my future self',
    recipient: 'Future me',
    scheduledDate: DateTime(2027, 1, 1),
    status: LetterStatus.scheduled,
    content:
        'Hey, it is me — from today. Whatever you are going through, I hope '
        'you can look back and see how far you have come. Be kind to '
        'yourself, the way you are learning to be kind today.',
  ),
  FutureLetter(
    id: 'f2',
    title: 'A note of hope',
    recipient: 'Future me',
    scheduledDate: DateTime(2026, 9, 15),
    status: LetterStatus.delivered,
    content:
        'Today felt heavy, so I am writing this for the days that feel '
        'lighter. Remember the park, the music, the small wins. They count.',
  ),
  FutureLetter(
    id: 'f3',
    title: 'One year later',
    recipient: 'Future me',
    scheduledDate: DateTime(2026, 5, 20),
    status: LetterStatus.opened,
    content:
        'You made it through a year. Read this and smile — you kept going, '
        'even when it was hard. I am proud of you.',
  ),
];
