import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/features/journal/data/journal_entry.dart';

void main() {
  group('JournalEntry model', () {
    test('constructs with required fields', () {
      final entry = JournalEntry(
        id: 'j-1',
        title: 'Test',
        content: 'Content',
        date: DateTime(2025, 8, 20),
        type: JournalEntryType.text,
      );
      expect(entry.id, 'j-1');
      expect(entry.title, 'Test');
      expect(entry.content, 'Content');
      expect(entry.type, JournalEntryType.text);
      expect(entry.emotion, isNull);
      expect(entry.hasImage, isFalse);
      expect(entry.hasAudio, isFalse);
    });

    test('constructs with optional media fields', () {
      final entry = JournalEntry(
        id: '1',
        title: 't',
        content: 'c',
        date: DateTime.now(),
        type: JournalEntryType.image,
        imageKey: 'journal/u1/images/abc.jpg',
        imageUrl: 'https://minio/img.jpg',
        audioKey: 'journal/u1/audio/abc.m4a',
        audioUrl: 'https://minio/audio.m4a',
        audioDurationSeconds: 90,
      );
      expect(entry.hasImage, isTrue);
      expect(entry.hasAudio, isTrue);
      expect(entry.audioDurationLabel, '1:30');
    });

    test('dateLabel formats correctly', () {
      final entry = JournalEntry(
        id: '1', title: 't', content: 'c',
        date: DateTime(2025, 3, 15, 14, 30),
        type: JournalEntryType.text,
      );
      expect(entry.dateLabel, '15 Mar 2025');
    });

    test('timeLabel formats 2:30 PM', () {
      final entry = JournalEntry(
        id: '1', title: 't', content: 'c',
        date: DateTime(2025, 1, 1, 14, 30),
        type: JournalEntryType.text,
      );
      expect(entry.timeLabel, '2:30 PM');
    });

    test('timeLabel formats midnight as 12:05 AM', () {
      final entry = JournalEntry(
        id: '1', title: 't', content: 'c',
        date: DateTime(2025, 1, 1, 0, 5),
        type: JournalEntryType.text,
      );
      expect(entry.timeLabel, '12:05 AM');
    });

    test('audioDurationLabel formats correctly', () {
      final entry = JournalEntry(
        id: '1', title: 't', content: 'c',
        date: DateTime.now(), type: JournalEntryType.voice,
        audioDurationSeconds: 125,
      );
      expect(entry.audioDurationLabel, '2:05');
    });

    test('audioDurationLabel empty when null', () {
      final entry = JournalEntry(
        id: '1', title: 't', content: 'c',
        date: DateTime.now(), type: JournalEntryType.text,
      );
      expect(entry.audioDurationLabel, '');
    });

    test('hasImage true when imageKey present', () {
      final entry = JournalEntry(
        id: '1', title: 't', content: 'c',
        date: DateTime.now(), type: JournalEntryType.image,
        imageKey: 'journal/user1/images/abc.jpg',
      );
      expect(entry.hasImage, isTrue);
    });

    test('hasImage false when imageKey null', () {
      final entry = JournalEntry(
        id: '1', title: 't', content: 'c',
        date: DateTime.now(), type: JournalEntryType.text,
      );
      expect(entry.hasImage, isFalse);
    });

    test('hasAudio true when audioKey present', () {
      final entry = JournalEntry(
        id: '1', title: 't', content: 'c',
        date: DateTime.now(), type: JournalEntryType.voice,
        audioKey: 'journal/user1/audio/abc.m4a',
      );
      expect(entry.hasAudio, isTrue);
    });

    test('hasAudio false when audioKey null', () {
      final entry = JournalEntry(
        id: '1', title: 't', content: 'c',
        date: DateTime.now(), type: JournalEntryType.text,
      );
      expect(entry.hasAudio, isFalse);
    });
  });

  group('JournalEntryType', () {
    test('label returns correct string', () {
      expect(JournalEntryType.text.label, 'Text');
      expect(JournalEntryType.voice.label, 'Voice');
      expect(JournalEntryType.image.label, 'Image');
    });

    test('isText returns correct bool', () {
      expect(JournalEntryType.text.isText, isTrue);
      expect(JournalEntryType.voice.isText, isFalse);
      expect(JournalEntryType.image.isText, isFalse);
    });
  });

  group('AiAnalysisData', () {
    test('isReady for COMPLETED', () {
      final ai = AiAnalysisData(status: 'COMPLETED', emotion: 'joy');
      expect(ai.isReady, isTrue);
    });

    test('isStale for STALE', () {
      final ai = AiAnalysisData(status: 'STALE');
      expect(ai.isStale, isTrue);
    });

    test('isProcessing for PROCESSING', () {
      final ai = AiAnalysisData(status: 'PROCESSING');
      expect(ai.isProcessing, isTrue);
    });

    test('hasFailed for FAILED', () {
      final ai = AiAnalysisData(status: 'FAILED');
      expect(ai.hasFailed, isTrue);
    });

    test('hasFailed for TIMEOUT', () {
      final ai = AiAnalysisData(status: 'TIMEOUT');
      expect(ai.hasFailed, isTrue);
    });

    test('hasFailed for UNAVAILABLE', () {
      final ai = AiAnalysisData(status: 'UNAVAILABLE');
      expect(ai.hasFailed, isTrue);
    });

    test('not ready when NOT_REQUESTED', () {
      final ai = AiAnalysisData(status: 'NOT_REQUESTED');
      expect(ai.isReady, isFalse);
      expect(ai.isStale, isFalse);
      expect(ai.isProcessing, isFalse);
      expect(ai.hasFailed, isFalse);
    });

    test('preserves optional fields', () {
      final ai = AiAnalysisData(
        status: 'COMPLETED',
        emotion: 'sadness',
        emotionConfidence: 0.85,
        sentiment: 'negative',
        sentimentConfidence: 0.72,
        emotionalThemes: 'melancholy, loss',
        summary: 'This entry reflects sadness.',
        reflectionPrompt: 'What brought this feeling?',
      );
      expect(ai.emotion, 'sadness');
      expect(ai.emotionConfidence, 0.85);
      expect(ai.sentiment, 'negative');
      expect(ai.sentimentConfidence, 0.72);
      expect(ai.emotionalThemes, 'melancholy, loss');
      expect(ai.summary, 'This entry reflects sadness.');
      expect(ai.reflectionPrompt, 'What brought this feeling?');
    });

    test('summary is null by default', () {
      final ai = AiAnalysisData(status: 'COMPLETED');
      expect(ai.summary, isNull);
    });
  });
}
