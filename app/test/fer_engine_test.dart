import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/camera_emotion_mapping.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_calibration.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_manifest.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_preprocessing.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_result.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_temporal.dart';
import 'package:mindease/features/mood_tracking/presentation/screens/camera_mood_screen.dart';

Map<String, dynamic> _validManifestJson() => {
      'modelId': 'vit-fer-7',
      'version': '1.0.0',
      'architecture': 'test',
      'inputWidth': 224,
      'inputHeight': 224,
      'channels': 3,
      'colorSpace': 'RGB',
      'normalization': 'MEAN_STD_0.5',
      'tensorLayout': 'NCHW',
      'classes': List<String>.from(kFerClasses),
      'classmapVersion': 'mo-thecreator-vit-fer-7@v1',
      'productionArtifact': 'vit_fer_fp16.tflite',
      'precision': 'fp16',
      'quantization': false,
      'checksum': 'abc',
      'calibration': {'temperature': 1.5},
      'minimumConfidence': 0.60,
      'minimumMargin': 0.10,
      'qualityGate': <String, dynamic>{},
      'temporal': {'windowSize': 8, 'minStableFrames': 4},
      'preprocessingVersion': '1.0.0',
    };

void main() {
  group('FerManifest', () {
    test('parses a valid manifest', () {
      final m = FerManifest.parse(_validManifestJson());
      expect(m.inputSize, 224);
      expect(m.classes.length, 7);
      expect(m.temperature, 1.5);
      expect(m.temporalWindow, 8);
    });

    test('rejects wrong class count', () {
      final j = _validManifestJson()..['classes'] = ['a', 'b'];
      expect(() => FerManifest.parse(j), throwsA(isA<FerManifestError>()));
    });

    test('rejects non-canonical class order', () {
      final j = _validManifestJson()
        ..['classes'] = List<String>.from(kFerClasses.reversed);
      expect(() => FerManifest.parse(j), throwsA(isA<FerManifestError>()));
    });

    test('rejects legacy 48px input (the old bug can never reload)', () {
      final j = _validManifestJson()
        ..['inputWidth'] = 48
        ..['inputHeight'] = 48;
      expect(() => FerManifest.parse(j), throwsA(isA<FerManifestError>()));
    });

    test('rejects the retired 64x64x1 grayscale contract', () {
      final j = _validManifestJson()
        ..['inputWidth'] = 64
        ..['inputHeight'] = 64
        ..['channels'] = 1;
      expect(() => FerManifest.parse(j), throwsA(isA<FerManifestError>()));
    });

    test('rejects non-RGB contract', () {
      final j = _validManifestJson()..['colorSpace'] = 'GRAY';
      expect(() => FerManifest.parse(j), throwsA(isA<FerManifestError>()));
    });

    test('rejects NHWC layout (NCHW is the model contract)', () {
      final j = _validManifestJson()..['tensorLayout'] = 'NHWC';
      expect(() => FerManifest.parse(j), throwsA(isA<FerManifestError>()));
    });

    test('rejects the retired contempt class', () {
      final j = _validManifestJson()
        ..['classes'] = [
          'anger',
          'contempt',
          'disgust',
          'fear',
          'happy',
          'neutral',
          'sad'
        ];
      expect(() => FerManifest.parse(j), throwsA(isA<FerManifestError>()));
    });
  });

  group('FerPreprocessing contract', () {
    late FerManifest m;
    setUp(() => m = FerManifest.parse(_validManifestJson()));

    test('RGB crop is written as NCHW float32 normalized to [-1,1]', () {
      final pre = FerPreprocessing(m);
      const hw = 224 * 224;
      final px = Uint8List(hw * 3);
      // Pixel 0 = pure red, pixel 1 = 50% red (grey-ish), pixel 2 = black.
      px[0] = 255;
      px[3] = 128;
      final out = pre.toTensorInput(px, quantized: false) as Float32List;
      expect(out.length, hw * 3);
      // NCHW: the R plane comes first, so out[i] indexes the R plane.
      expect(out[0], closeTo(1.0, 1e-6));
      expect(out[1], closeTo(128 * (2 / 255) - 1, 1e-6));
      expect(out[2], closeTo(-1.0, 1e-6));
      // The G and B planes must not alias the R plane.
      expect(out[hw], closeTo(-1.0, 1e-6));
      expect(out[2 * hw], closeTo(-1.0, 1e-6));
    });

    test('quantized input is rejected, not silently reinterpreted', () {
      final pre = FerPreprocessing(m);
      expect(() => pre.toTensorInput(Uint8List(224 * 224 * 3), quantized: true),
          throwsA(isA<FerContractError>()));
    });

    test('wrong crop size throws (no silent reshape)', () {
      final pre = FerPreprocessing(m);
      expect(() => pre.toTensorInput(Uint8List(48 * 48 * 3), quantized: false),
          throwsA(isA<FerContractError>()));
    });

    test('grayscale-sized crop throws', () {
      final pre = FerPreprocessing(m);
      expect(() => pre.toTensorInput(Uint8List(64 * 64), quantized: false),
          throwsA(isA<FerContractError>()));
    });

    test('interpreter 48px tensor is rejected', () {
      final pre = FerPreprocessing(m);
      expect(
          () => pre.validateTensor(
              shape: [1, 48, 48, 3], dtype: 'float32', quantized: false),
          throwsA(isA<FerContractError>()));
    });

    test('NHWC-shaped tensor is rejected (NCHW only)', () {
      final pre = FerPreprocessing(m);
      expect(
          () => pre.validateTensor(
              shape: [1, 224, 224, 3], dtype: 'float32', quantized: false),
          throwsA(isA<FerContractError>()));
    });

    test('correct tensor validates', () {
      final pre = FerPreprocessing(m);
      pre.validateTensor(
          shape: [1, 3, 224, 224], dtype: 'float32', quantized: false);
    });
  });

  group('FerCalibration', () {
    late FerManifest m;
    setUp(() => m = FerManifest.parse(_validManifestJson())); // T=1.5

    test('temperature flattens overconfident distributions', () {
      final cal = FerCalibration(m);
      final sharp = [0.97, 0.005, 0.0, 0.0, 0.01, 0.005, 0.01];
      final out = cal.applyTemperature(sharp);
      expect(out[0], lessThan(0.97));
      expect(out.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
    });

    test('T=1 is identity', () {
      final m1 = FerManifest.parse(
          _validManifestJson()..['calibration'] = {'temperature': 1.0});
      final p = [0.1, 0.2, 0.05, 0.4, 0.05, 0.1, 0.05];
      expect(FerCalibration(m1).applyTemperature(p), p);
    });

    test('confident + wide margin -> certain', () {
      final d =
          FerCalibration(m).decide([0.02, 0.01, 0.01, 0.85, 0.03, 0.03, 0.03]);
      expect(d.certain, isTrue);
      expect(d.topIndex, 3); // happy
    });

    test('low confidence -> uncertain, never forced', () {
      final d = FerCalibration(m).decide([0.2, 0.15, 0.1, 0.1, 0.2, 0.05, 0.1]);
      expect(d.certain, isFalse);
    });

    test('narrow margin -> uncertain', () {
      final d =
          FerCalibration(m).decide([0.05, 0.05, 0.05, 0.40, 0.05, 0.30, 0.05]);
      expect(d.certain, isFalse);
      expect(d.margin, closeTo(0.10, 1e-9));
    });
  });

  group('FerTemporalFusion', () {
    late FerManifest m;
    setUp(() => m = FerManifest.parse(_validManifestJson()));

    List<double> oneHot(int i) =>
        List<double>.generate(7, (j) => j == i ? 0.9 : 0.1 / 6);

    test('needs minStableFrames before stable', () {
      final f = FerTemporalFusion(m);
      FerTemporalState? s;
      for (var k = 0; k < 3; k++) {
        s = f.addFrame(oneHot(3), 0.9);
      }
      expect(s!.stable, isFalse);
      s = f.addFrame(oneHot(3), 0.9);
      expect(s.stable, isTrue);
      expect(s.vote, 3);
    });

    test('disagreement blocks stability (no flicker surfacing)', () {
      final f = FerTemporalFusion(m);
      for (var k = 0; k < 3; k++) {
        f.addFrame(oneHot(3), 0.9);
      }
      // Two dissenting frames: agreement drops to 3/5 = 0.6 < 0.75.
      f.addFrame(oneHot(4), 0.9);
      final s = f.addFrame(oneHot(4), 0.9);
      expect(s.stable, isFalse);
    });

    test('flicker counts label changes', () {
      final f = FerTemporalFusion(m);
      for (var k = 0; k < 5; k++) {
        f.addFrame(oneHot(3), 0.9);
      }
      final before = f.labelChanges;
      f.addFrame(oneHot(0), 0.9);
      f.addFrame(oneHot(0), 0.9);
      expect(f.labelChanges, greaterThan(before));
    });

    test('51/49 alternation keeps support (no flicker trap)', () {
      // Root-cause regression test: two expressions alternating frame to
      // frame must not starve the agreement gate while the EMA is converged.
      // Support counts top-2 membership, so both frames support the EMA
      // winner every time.
      final f = FerTemporalFusion(m);
      List<double> soft(int top, int second) {
        final p = List<double>.filled(7, 0.02);
        p[top] = 0.51;
        p[second] = 0.43;
        return p;
      }
      FerTemporalState? s;
      for (var k = 0; k < 8; k++) {
        s = f.addFrame(k.isEven ? soft(3, 4) : soft(4, 3), 0.9);
      }
      expect(s!.frames, 8);
      expect(s.stable, isTrue);
    });

    test('genuine dissent still withholds support', () {
      // One-hot frames for another class can never contain the vote in
      // their top-2, so real disagreement still blocks stability.
      final f = FerTemporalFusion(m);
      for (var k = 0; k < 6; k++) {
        f.addFrame(oneHot(3), 0.9);
      }
      final s = f.addFrame(oneHot(5), 0.9);
      // 6/7 support stays above the bar here (a single dissent is
      // tolerated); sustained dissent drops it below.
      expect(s.stable, isTrue);
      f.addFrame(oneHot(5), 0.9);
      final s3 = f.addFrame(oneHot(5), 0.9);
      expect(s3.stable, isFalse);
    });
  });

  group('canonical class metadata', () {
    test('every canonical class has a display name', () {
      // Regression: an 8-class display map shipped alongside a model that
      // emits 7 different ids, so 'happy'/'sad' fell through to the raw id
      // and the UI showed a bare "happy" instead of "Happiness".
      for (final c in kFerClasses) {
        expect(kFerDisplayNames.containsKey(c), isTrue, reason: c);
        expect(ferDisplayName(c), isNot(c),
            reason: '$c has no distinct display name');
      }
    });

    test('display-name map has no stale classes', () {
      expect(kFerDisplayNames.keys.toSet(), kFerClasses.toSet());
      for (final stale in ['happiness', 'sadness', 'contempt']) {
        expect(kFerDisplayNames.containsKey(stale), isFalse, reason: stale);
      }
    });

    test('unknown falls back to the raw id rather than throwing', () {
      expect(ferDisplayName('not-a-class'), 'not-a-class');
    });

    test('class order matches the model id2label order', () {
      expect(kFerClasses,
          ['anger', 'disgust', 'fear', 'happy', 'neutral', 'sad', 'surprise']);
    });
  });

  group('camera emotion mapping', () {
    test('all 7 canonical classes map to tags', () {
      for (final c in kFerClasses) {
        expect(mapCanonicalToTag(c), isNotNull, reason: c);
      }
    });

    test('unknown maps to null (no pre-fill)', () {
      expect(mapCanonicalToTag('unknown'), isNull);
    });

    test('mapping version is pinned', () {
      expect(kCameraEmotionMappingVersion, 'camera-emotion-map-v2');
    });
  });

  group('CameraMoodResult event payload', () {
    test('toEventMap matches the emotion-event contract exactly', () {
      const r = CameraMoodResult(
        emotion: 'happy',
        confidence: 0.84,
        faceQuality: 0.93,
        framesAnalyzed: 8,
        emotionScores: {'happy': 0.87},
        calibratedConfidence: 0.84,
        modelId: 'vit-fer-7',
        modelVersion: '1.0.0',
        preprocessingVersion: '1.0.0',
        status: 'PREDICTED',
      );
      final map = r.toEventMap(
        capturedAt: '2026-09-28T00:00:00Z',
        idempotencyKey: 'k-1',
      );
      // Exact backend CreateEmotionEventRequest field set — no more, no less.
      expect(
        map.keys.toSet(),
        {
          'emotion',
          'scores',
          'calibratedConfidence',
          'faceQuality',
          'modelId',
          'modelVersion',
          'preprocessingVersion',
          'status',
          'source',
          'capturedAt',
          'idempotencyKey',
        },
      );
      expect(map['source'], 'CAMERA');
      expect(map['scores'], {'happy': 0.87});
    });

    test('toMap keeps legacy analyze keys plus versioned keys', () {
      const r = CameraMoodResult(
        emotion: 'happy',
        confidence: 0.84,
        faceQuality: 0.93,
        framesAnalyzed: 8,
      );
      final map = r.toMap();
      expect(map['dominantEmotion'], 'happy');
      expect(map['faceCount'], 1);
      expect(map['modelId'], 'vit-fer-7');
      expect(map['preprocessingVersion'], 'unknown');
    });

    test('photo capture produces a single-frame result contract', () {
      // The photo flow confirms exactly one analyzed frame: framesAnalyzed
      // is 1, faceCount stays 1, and the PREDICTED status wire value is
      // what the backend fusion weights as a single observation.
      const r = FerResult(
        emotion: 'neutral',
        scores: {'neutral': 0.72},
        calibratedConfidence: 0.72,
        rawTopProbability: 0.70,
        margin: 0.25,
        faceQuality: 0.8,
        status: FerStatus.predicted,
        modelId: 'vit-fer-7',
        modelVersion: '1.0.0',
        preprocessingVersion: '2.0.0',
        valence: 0.0,
        arousal: 0.0,
        framesAnalyzed: 1,
      );
      final mood = CameraMoodResult.fromFer(r, 1);
      expect(mood.emotion, 'neutral');
      expect(mood.framesAnalyzed, 1);
      expect(mood.status, 'PREDICTED');
      final map = mood.toMap();
      expect(map['dominantEmotion'], 'neutral');
      expect(map['faceDetected'], isTrue);
      expect(map['faceCount'], 1);
      expect(map['framesAnalyzed'], 1);
      expect(map['status'], 'PREDICTED');
    });
  });

  group('FerResult payload', () {
    test('toMap preserves legacy keys and adds versioned keys', () {
      final m = FerManifest.parse(_validManifestJson());
      final r = FerResult(
        emotion: 'happy',
        scores: {for (final c in m.classes) c: 0.1},
        calibratedConfidence: 0.8,
        rawTopProbability: 0.9,
        margin: 0.5,
        faceQuality: 0.9,
        status: FerStatus.predicted,
        modelId: m.modelId,
        modelVersion: m.version,
        preprocessingVersion: m.preprocessingVersion,
        valence: 0.5,
        arousal: 0.2,
        framesAnalyzed: 6,
      );
      final map = r.toMap();
      for (final k in [
        'dominantEmotion',
        'emotionScores',
        'faceDetected',
        'faceCount',
        'faceQuality',
        'valence',
        'arousal',
        'framesAnalyzed'
      ]) {
        expect(map.containsKey(k), isTrue, reason: k);
      }
      expect(map['modelVersion'], '1.0.0');
      expect(map['status'], 'PREDICTED');
    });
  });
}
