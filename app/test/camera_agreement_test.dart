import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/features/mood_tracking/domain/emotion/camera_emotion_mapping.dart';

void main() {
  group('mapCanonicalToMood mirrors server fusion table', () {
    test('covers all seven canonical classes', () {
      expect(mapCanonicalToMood('happy'), 'happy');
      expect(mapCanonicalToMood('neutral'), 'calm');
      expect(mapCanonicalToMood('sad'), 'low');
      expect(mapCanonicalToMood('anger'), 'stressed');
      expect(mapCanonicalToMood('fear'), 'stressed');
      expect(mapCanonicalToMood('surprise'), 'okay');
      expect(mapCanonicalToMood('disgust'), 'low');
    });

    test('unknown and unmapped yield null (no signal)', () {
      expect(mapCanonicalToMood('unknown'), isNull);
      expect(mapCanonicalToMood('contempt'), isNull);
      expect(mapCanonicalToMood(''), isNull);
    });
  });

  group('cameraAgreement: self-report stays primary', () {
    test('user Happy + camera Happy -> agree', () {
      expect(
        cameraAgreement(
          userMoodId: 'happy',
          cameraEmotion: 'happy',
          cameraConfidence: 0.85,
        ),
        CameraAgreement.agree,
      );
    });

    test('user Happy + camera Sad (medium confidence) -> differs, never overrides', () {
      expect(
        cameraAgreement(
          userMoodId: 'happy',
          cameraEmotion: 'sad',
          cameraConfidence: 0.55,
        ),
        CameraAgreement.differs,
      );
    });

    test('user Calm + camera Neutral -> agree (neutral maps to calm)', () {
      expect(
        cameraAgreement(
          userMoodId: 'calm',
          cameraEmotion: 'neutral',
          cameraConfidence: 0.9,
        ),
        CameraAgreement.agree,
      );
    });

    test('adjacent moods -> close (okay vs calm differ by 0.3)', () {
      expect(
        cameraAgreement(
          userMoodId: 'okay',
          cameraEmotion: 'neutral',
          cameraConfidence: 0.8,
        ),
        CameraAgreement.close,
      );
    });

    test('low-confidence camera -> noSignal (user mood is the signal)', () {
      expect(
        cameraAgreement(
          userMoodId: 'happy',
          cameraEmotion: 'sad',
          cameraConfidence: 0.2,
        ),
        CameraAgreement.noSignal,
      );
    });

    test('unknown camera emotion -> noSignal', () {
      expect(
        cameraAgreement(
          userMoodId: 'low',
          cameraEmotion: 'unknown',
          cameraConfidence: 0.9,
        ),
        CameraAgreement.noSignal,
      );
    });

    test('user Stressed + camera Anger -> agree', () {
      expect(
        cameraAgreement(
          userMoodId: 'stressed',
          cameraEmotion: 'anger',
          cameraConfidence: 0.75,
        ),
        CameraAgreement.agree,
      );
    });

    test('user Low + camera Disgust -> agree (disgust maps to low)', () {
      expect(
        cameraAgreement(
          userMoodId: 'low',
          cameraEmotion: 'disgust',
          cameraConfidence: 0.7,
        ),
        CameraAgreement.agree,
      );
    });
  });
}
