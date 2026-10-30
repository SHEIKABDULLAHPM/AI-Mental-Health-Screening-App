import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/core/api/models.dart';

String _display(String canonical) => canonical;

void main() {
  group('MindeaseProfile camera fields', () {
    MindeaseProfile profile(Map<String, dynamic> extra) =>
        MindeaseProfile.fromJson({
          'id': 'p1',
          'status': 'COMPLETED',
          ...extra,
        });

    test('parses camera signal from backend DTO', () {
      final p = profile({
        'moodMood': 'happy',
        'cameraEmotion': 'sad',
        'cameraConfidence': 0.55,
        'signalAgreement': 'differs',
      });
      expect(p.hasMood, isTrue);
      expect(p.hasCameraSignal, isTrue);
      expect(p.cameraEmotion, 'sad');
      expect(p.cameraConfidence, 0.55);
      expect(p.signalAgreement, 'differs');
    });

    test('absent camera degrades gracefully', () {
      final p = profile({'moodMood': 'calm'});
      expect(p.hasMood, isTrue);
      expect(p.hasCameraSignal, isFalse);
      expect(p.cameraEmotion, isNull);
    });

    test('unknown/noSignal camera is not a signal', () {
      final p = profile({
        'moodMood': 'low',
        'cameraEmotion': 'unknown',
        'signalAgreement': 'noSignal',
      });
      expect(p.hasCameraSignal, isFalse);
    });
  });

  group('MindeaseMoodSummary camera fields', () {
    test('parses camera signal from dashboard DTO', () {
      final s = MindeaseMoodSummary.fromJson({
        'hasHistory': true,
        'currentMood': 'okay',
        'trendDirection': 'stable',
        'historyCount': 4,
        'cameraEmotion': 'neutral',
        'signalAgreement': 'agree',
      });
      expect(s.hasCameraSignal, isTrue);
      expect(s.cameraEmotion, 'neutral');
    });

    test('missing camera keys default to no signal', () {
      final s = MindeaseMoodSummary.fromJson({'hasHistory': false});
      expect(s.hasCameraSignal, isFalse);
    });
  });

  group('cameraSignalLine', () {
    test('agree/close/differs copy never overrides self-report', () {
      expect(
        cameraSignalLine('sad', 'agree', _display),
        contains('in line with your selection'),
      );
      expect(
        cameraSignalLine('neutral', 'close', _display),
        contains('close to your selection'),
      );
      final differs = cameraSignalLine('sad', 'differs', _display);
      expect(differs, contains('different from your selection'));
      expect(differs, contains('your selection stays primary'));
    });

    test('null/unknown/noSignal yield null (nothing shown)', () {
      expect(cameraSignalLine(null, 'agree', _display), isNull);
      expect(cameraSignalLine('happy', null, _display), isNull);
      expect(cameraSignalLine('unknown', 'agree', _display), isNull);
      expect(cameraSignalLine('happy', 'noSignal', _display), isNull);
      expect(cameraSignalLine('happy', 'bogus', _display), isNull);
    });

    test('never emits numbers', () {
      final line = cameraSignalLine('sad', 'differs', _display)!;
      expect(RegExp(r'\d').hasMatch(line), isFalse);
    });
  });

  group('MindeaseProfile score availability is independent of the insight', () {
    MindeaseProfile profile(Map<String, dynamic> extra) =>
        MindeaseProfile.fromJson({
          'id': 'p1',
          'assessmentId': 'a1',
          ...extra,
        });

    test('scores are readable while the insight is still pending', () {
      final p = profile({
        'status': 'AI_ANALYSIS_PENDING',
        'wellnessScore': 58,
        'stressLevel': 'MODERATE',
        'lifestyleScore': 90,
      });

      // The whole point: an LLM outage must not withhold the score.
      expect(p.isPending, isTrue);
      expect(p.hasInsight, isFalse);
      expect(p.hasScores, isTrue);
      expect(p.wellnessScore, 58);
    });

    test('no scores yet means there is nothing to display', () {
      final p = profile({'status': 'AI_ANALYSIS_PENDING'});

      expect(p.hasScores, isFalse);
      expect(p.isPending, isTrue);
    });

    test('a completed profile carries both score and insight', () {
      final p = profile({
        'status': 'COMPLETED',
        'wellnessScore': 41,
        'aiInsight': 'Your sleep is the strongest lever this week.',
      });

      expect(p.isPending, isFalse);
      expect(p.hasScores, isTrue);
      expect(p.hasInsight, isTrue);
    });

    test('an empty insight string is treated as absent', () {
      final p = profile({'status': 'COMPLETED', 'wellnessScore': 58, 'aiInsight': ''});

      expect(p.hasInsight, isFalse);
      expect(p.hasScores, isTrue);
    });
  });
}
