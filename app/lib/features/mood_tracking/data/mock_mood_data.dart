import 'package:mindease/features/mood_tracking/data/mood_entry.dart';

/// UI-ONLY preview data for Mood Tracking.
///
/// Replace with repository/API calls in a later phase — the screens only
/// depend on [mockMoodEntries] and never on where it comes from.
final List<MoodEntry> mockMoodEntries = [
  MoodEntry(
    id: 'm1',
    date: _daysAgo(0, hour: 9),
    moodId: 'calm',
    emotion: 'Content',
    note: 'Started the day with a short walk.',
  ),
  MoodEntry(
    id: 'm2',
    date: _daysAgo(1, hour: 20),
    moodId: 'happy',
    emotion: 'Grateful',
    note: 'Dinner with the family was lovely.',
  ),
  MoodEntry(
    id: 'm3',
    date: _daysAgo(2, hour: 13),
    moodId: 'okay',
    emotion: 'Tired',
    note: null,
  ),
  MoodEntry(
    id: 'm4',
    date: _daysAgo(3, hour: 22),
    moodId: 'low',
    emotion: 'Overwhelmed',
    note: 'Struggled to switch off before bed.',
  ),
  MoodEntry(
    id: 'm5',
    date: _daysAgo(4, hour: 18),
    moodId: 'calm',
    emotion: 'Relaxed',
    note: 'Evening meditation helped.',
  ),
  MoodEntry(
    id: 'm6',
    date: _daysAgo(5, hour: 12),
    moodId: 'stressed',
    emotion: 'Anxious',
    note: 'Busy day at work.',
  ),
  MoodEntry(
    id: 'm7',
    date: _daysAgo(6, hour: 8),
    moodId: 'happy',
    emotion: 'Hopeful',
    note: null,
  ),
  MoodEntry(
    id: 'm8',
    date: _daysAgo(8, hour: 21),
    moodId: 'okay',
    emotion: 'Content',
    note: null,
  ),
  MoodEntry(
    id: 'm9',
    date: _daysAgo(10, hour: 10),
    moodId: 'very_happy',
    emotion: 'Grateful',
    note: 'A really good morning.',
  ),
  MoodEntry(
    id: 'm10',
    date: _daysAgo(12, hour: 15),
    moodId: 'low',
    emotion: 'Sad',
    note: null,
  ),
  MoodEntry(
    id: 'm11',
    date: _daysAgo(14, hour: 19),
    moodId: 'calm',
    emotion: 'Relaxed',
    note: 'Read a chapter before bed.',
  ),
  MoodEntry(
    id: 'm12',
    date: _daysAgo(16, hour: 11),
    moodId: 'happy',
    emotion: 'Content',
    note: null,
  ),
  MoodEntry(
    id: 'm13',
    date: _daysAgo(19, hour: 23),
    moodId: 'okay',
    emotion: 'Tired',
    note: 'Slept late.',
  ),
  MoodEntry(
    id: 'm14',
    date: _daysAgo(21, hour: 8),
    moodId: 'very_happy',
    emotion: 'Hopeful',
    note: null,
  ),
];

/// Date helper so mock preview data is always relative to "today".
DateTime _daysAgo(int days, {required int hour}) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - days, hour, 17);
}
