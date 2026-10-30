import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/face_alignment.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/face_quality.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_manifest.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_result.dart';

Map<String, dynamic> _manifestJson() => {
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
      'calibration': {'temperature': 1.0},
      'minimumConfidence': 0.60,
      'minimumMargin': 0.10,
      'qualityGate': <String, dynamic>{},
      'temporal': <String, dynamic>{},
      'preprocessingVersion': '2.0.0',
    };

/// Same synthetic frame as [_frame] but interleaved RGB, so the RGB aligner
/// can be exercised without a real camera. R and G vary independently so a
/// channel-swap in the aligner would be caught.
Uint8List _rgbFrame(int w, int h, {int faceL = 50, int faceT = 40,
    int faceR = 150, int faceB = 160}) {
  final px = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      if (x >= faceL && x < faceR && y >= faceT && y < faceB) {
        px[i] = 200; // R constant and high
        px[i + 1] = 30 + ((x * 7) % 100); // G varies across x
        px[i + 2] = 90; // B constant
      } else {
        px[i] = 20;
        px[i + 1] = 20;
        px[i + 2] = 20;
      }
    }
  }
  return px;
}

/// Synthetic 200x200 frame: bright square "face" on dark background,
/// with eye dots implied by landmark coordinates (geometry test uses
/// coordinates only; pixels are a smooth gradient for photometrics).
Uint8List _frame(int w, int h, {int faceL = 50, int faceT = 40,
    int faceR = 150, int faceB = 160, int blur = 0}) {
  final px = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 20;
      if (x >= faceL && x < faceR && y >= faceT && y < faceB) {
        v = 90 + ((x * 7 + y * 13) % 110); // textured: bright, contrasty, sharp
      }
      if (blur > 0) v = 120; // flat fill: zero contrast + zero sharpness
      px[y * w + x] = v;
    }
  }
  return px;
}

Face _face({
  required Rect box,
  math.Point<int>? leftEye,
  math.Point<int>? rightEye,
  double yaw = 0,
  double pitch = 0,
}) {
  final landmarks = <FaceLandmarkType, FaceLandmark?>{
    for (final t in FaceLandmarkType.values) t: null,
  };
  if (leftEye != null) {
    landmarks[FaceLandmarkType.leftEye] =
        FaceLandmark(type: FaceLandmarkType.leftEye, position: leftEye);
  }
  if (rightEye != null) {
    landmarks[FaceLandmarkType.rightEye] =
        FaceLandmark(type: FaceLandmarkType.rightEye, position: rightEye);
  }
  return Face(
    boundingBox: box,
    landmarks: landmarks,
    contours: const {},
    headEulerAngleX: pitch,
    headEulerAngleY: yaw,
    headEulerAngleZ: 0,
  );
}

void main() {
  late FerManifest manifest;
  setUp(() => manifest = FerManifest.parse(_manifestJson()));

  group('FaceAligner geometry', () {
    test('landmark warp puts eyes on canonical targets', () {
      // Eyes at (80,80) and (120,88): tilted by ~11deg, dist ~40.8px.
      final gray = _frame(200, 200);
      final face = _face(
        box: const Rect.fromLTWH(50, 40, 100, 120),
        leftEye: const math.Point<int>(80, 80),
        rightEye: const math.Point<int>(120, 88),
      );
      final out = const FaceAligner().align(
        grayFull: gray, frameWidth: 200, frameHeight: 200, face: face);
      expect(out.method, 'landmarks');
      expect(out.pixels64.length, 64 * 64);
      expect(out.eyeDistance, closeTo(40.8, 0.5));

      // The warped output, re-interpreted: sample brightness around the
      // canonical eye targets — both must sit inside the bright face area.
      // (Geometry check: the warp must not throw eyes out of frame.)
      var bright = 0;
      for (final t in [(20, 24), (21, 24), (43, 24), (44, 24)]) {
        if (out.pixels64[t.$2 * 64 + t.$1] > 60) bright++;
      }
      expect(bright, greaterThanOrEqualTo(3));
    });

    test('missing landmarks fall back to box crop (reported)', () {
      final gray = _frame(200, 200);
      final face = _face(box: const Rect.fromLTWH(50, 40, 100, 120));
      final out = const FaceAligner().align(
        grayFull: gray, frameWidth: 200, frameHeight: 200, face: face);
      expect(out.method, 'box');
      expect(out.pixels64.length, 64 * 64);
      // Box crop centered on the bright square: mean must be bright.
      final mean =
          out.pixels64.fold(0, (a, b) => a + b) / out.pixels64.length;
      expect(mean, greaterThan(80));
    });

    test('degenerate eye distance falls back to box', () {
      final gray = _frame(200, 200);
      final face = _face(
        box: const Rect.fromLTWH(50, 40, 100, 120),
        leftEye: const math.Point<int>(100, 100),
        rightEye: const math.Point<int>(101, 100),
      );
      final out = const FaceAligner().align(
        grayFull: gray, frameWidth: 200, frameHeight: 200, face: face);
      expect(out.method, 'box');
    });
  });

  group('RgbFaceAligner geometry (the path the ViT pipeline uses)', () {
    test('landmark warp produces a 224x224x3 RGB crop', () {
      final rgb = _rgbFrame(200, 200);
      final face = _face(
        box: const Rect.fromLTWH(50, 40, 100, 120),
        leftEye: const math.Point<int>(80, 80),
        rightEye: const math.Point<int>(120, 88),
      );
      final out = const RgbFaceAligner().align(
          rgbFull: rgb, frameWidth: 200, frameHeight: 200, face: face);
      expect(out.method, 'landmarks');
      expect(out.pixels.length, 224 * 224 * 3);
      expect(out.eyeDistance, closeTo(40.8, 0.5));
    });

    test('channels are not swapped: R stays high, B stays mid', () {
      final rgb = _rgbFrame(200, 200);
      final face = _face(
        box: const Rect.fromLTWH(50, 40, 100, 120),
        leftEye: const math.Point<int>(80, 80),
        rightEye: const math.Point<int>(120, 80),
      );
      final out = const RgbFaceAligner().align(
          rgbFull: rgb, frameWidth: 200, frameHeight: 200, face: face);
      // Sample inside the face region of the warped output. The synthetic
      // face is R=200, B=90, so an R/B transposition shows up immediately.
      for (final t in [(100, 100), (110, 90), (90, 110)]) {
        final i = (t.$2 * 224 + t.$1) * 3;
        expect(out.pixels[i], 200, reason: 'R at $t');
        expect(out.pixels[i + 2], 90, reason: 'B at $t');
      }
    });

    test('missing landmarks fall back to box crop (reported)', () {
      final rgb = _rgbFrame(200, 200);
      final face = _face(box: const Rect.fromLTWH(50, 40, 100, 120));
      final out = const RgbFaceAligner().align(
          rgbFull: rgb, frameWidth: 200, frameHeight: 200, face: face);
      expect(out.method, 'box');
      expect(out.pixels.length, 224 * 224 * 3);
      // Box crop lands on the bright face, so R must dominate the background.
      var rSum = 0.0, gSum = 0.0;
      for (var i = 0; i < out.pixels.length; i += 3) {
        rSum += out.pixels[i];
        gSum += out.pixels[i + 1];
      }
      expect(rSum / (out.pixels.length / 3), greaterThan(150));
      expect(gSum, lessThan(rSum));
    });

    test('degenerate eye distance falls back to box', () {
      final rgb = _rgbFrame(200, 200);
      final face = _face(
        box: const Rect.fromLTWH(50, 40, 100, 120),
        leftEye: const math.Point<int>(100, 100),
        rightEye: const math.Point<int>(101, 100),
      );
      final out = const RgbFaceAligner().align(
          rgbFull: rgb, frameWidth: 200, frameHeight: 200, face: face);
      expect(out.method, 'box');
    });

    test('bilinear sampling never reads outside the source frame', () {
      // A face whose box and eyes sit on the frame edge forces the sampler to
      // clamp; an unclamped read would throw or wrap.
      final rgb = _rgbFrame(120, 120,
          faceL: 0, faceT: 0, faceR: 60, faceB: 60);
      final face = _face(
        box: const Rect.fromLTWH(0, 0, 60, 60),
        leftEye: const math.Point<int>(15, 20),
        rightEye: const math.Point<int>(45, 20),
      );
      final out = const RgbFaceAligner().align(
          rgbFull: rgb, frameWidth: 120, frameHeight: 120, face: face);
      expect(out.method, 'landmarks');
      expect(out.pixels.length, 224 * 224 * 3);
    });
  });

  group('FaceQualityGate', () {
    test('good face passes with high quality', () {
      final gray = _frame(200, 200);
      final face = _face(
        box: const Rect.fromLTWH(50, 40, 100, 120),
        leftEye: const math.Point<int>(80, 80),
        rightEye: const math.Point<int>(120, 80),
      );
      final r = FaceQualityGate(manifest).evaluate(
        face: face, frameWidth: 200, frameHeight: 200,
        grayFull: gray, landmarksEnabled: true);
      expect(r.passed, isTrue);
      expect(r.status, FerStatus.ready);
      expect(r.quality, greaterThan(0.5));
    });

    test('tiny face is rejected', () {
      final gray = _frame(400, 400,
          faceL: 190, faceT: 190, faceR: 210, faceB: 210);
      final face = _face(box: const Rect.fromLTWH(190, 190, 20, 20));
      final r = FaceQualityGate(manifest).evaluate(
        face: face, frameWidth: 400, frameHeight: 400,
        grayFull: gray, landmarksEnabled: false);
      expect(r.passed, isFalse);
      expect(r.status, FerStatus.faceTooSmall);
    });

    test('extreme yaw is rejected', () {
      final gray = _frame(200, 200);
      final face = _face(
        box: const Rect.fromLTWH(50, 40, 100, 120), yaw: 45);
      final r = FaceQualityGate(manifest).evaluate(
        face: face, frameWidth: 200, frameHeight: 200,
        grayFull: gray, landmarksEnabled: false);
      expect(r.passed, isFalse);
      expect(r.status, FerStatus.badPose);
    });

    test('dark frame is rejected as bad lighting', () {
      final gray = Uint8List(200 * 200); // all zeros
      final face = _face(box: const Rect.fromLTWH(50, 40, 100, 120));
      final r = FaceQualityGate(manifest).evaluate(
        face: face, frameWidth: 200, frameHeight: 200,
        grayFull: gray, landmarksEnabled: false);
      expect(r.passed, isFalse);
      expect(r.status, FerStatus.badLighting);
    });

    test('flat fill is rejected as blurry', () {
      final gray = _frame(200, 200, blur: 1);
      final face = _face(box: const Rect.fromLTWH(50, 40, 100, 120));
      final r = FaceQualityGate(manifest).evaluate(
        face: face, frameWidth: 200, frameHeight: 200,
        grayFull: gray, landmarksEnabled: false);
      expect(r.passed, isFalse);
      // flat fill has zero contrast AND zero sharpness; either gate fires
      expect(r.status,
          anyOf([FerStatus.faceTooBlurry, FerStatus.badLighting]));
    });

    test('missing eyes with landmarks on means occluded', () {
      final gray = _frame(200, 200);
      final face = _face(box: const Rect.fromLTWH(50, 40, 100, 120));
      final r = FaceQualityGate(manifest).evaluate(
        face: face, frameWidth: 200, frameHeight: 200,
        grayFull: gray, landmarksEnabled: true);
      expect(r.passed, isFalse);
      expect(r.status, FerStatus.faceOccluded);
    });
  });
}
