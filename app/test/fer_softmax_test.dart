import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/features/mood_tracking/domain/emotion/fer_classifier.dart';

// Regression test for the neutral-bias root cause: the shipped ViT artifact
// emits raw LOGITS, and every downstream stage assumes probabilities.
// Uses verbatim interpreter rows captured on-device (SM-M325F logcat).
void main() {
  // FER_RAW f=3: resting frame, neutral logit dominant.
  const deviceLogitsNeutral = [
    -0.936, // anger
    -1.931, // disgust
    -0.597, // fear
    -0.569, // happy
    3.317, // neutral
    0.573, // sad
    -1.520, // surprise
  ];

  // FER_RAW surprise-pose frame: surprise logit on top.
  const deviceLogitsSurprise = [
    -2.507, // anger
    -1.672, // disgust
    1.731, // fear
    -2.722, // happy
    2.435, // neutral
    -0.975, // sad
    3.100, // surprise
  ];

  group('softmaxLogits', () {
    test('decodes the captured neutral frame to neutral ~88%', () {
      final probs = softmaxLogits(deviceLogitsNeutral);
      expect(probs, hasLength(7));
      expect(probs.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
      expect(probs.every((p) => p >= 0.0 && p <= 1.0), isTrue);
      // neutral must win, and confidence must be a real probability (< 1.0),
      // not the raw logit 3.317 that used to sail past the 0.6 gate.
      expect(probs[4], closeTo(0.883, 1e-3));
      expect(probs[4], lessThan(1.0));
      expect(probs[5], closeTo(0.057, 1e-3)); // sad runner-up
    });

    test('decodes the captured surprise frame to surprise ~55%', () {
      final probs = softmaxLogits(deviceLogitsSurprise);
      expect(probs.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
      expect(probs[6], closeTo(0.555, 1e-3));
      expect(probs[4], closeTo(0.286, 1e-3)); // neutral second
      expect(probs[2], closeTo(0.141, 1e-3)); // fear third
    });

    test('is numerically stable for large logits', () {
      final probs = softmaxLogits([1000.0, 999.0, 0.0, -5.0, 2.0, 1.0, -1.0]);
      expect(probs.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
      expect(probs.every((p) => p.isFinite), isTrue);
      expect(probs[0], greaterThan(0.7));
    });

    test('uniform logits give a uniform distribution', () {
      final probs = softmaxLogits([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]);
      for (final p in probs) {
        expect(p, closeTo(1 / 7, 1e-9));
      }
    });
  });

  group('decodeOutput', () {
    test('applies softmax to logits', () {
      final probs = decodeOutput(deviceLogitsNeutral);
      expect(probs[4], closeTo(0.883, 1e-3));
    });

    test('passes an already-valid distribution through untouched', () {
      const dist = [0.05, 0.05, 0.1, 0.6, 0.1, 0.05, 0.05];
      final out = decodeOutput(dist);
      for (var i = 0; i < out.length; i++) {
        expect(out[i], closeTo(dist[i], 1e-12));
      }
    });

    test('does not mutate the input row', () {
      final row = List<double>.from(deviceLogitsSurprise);
      decodeOutput(row);
      expect(row[6], 3.1);
    });
  });
}
