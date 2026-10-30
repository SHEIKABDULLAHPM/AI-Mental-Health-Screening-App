/// Unit tests for the production fast paths (no device, no model needed).
///
/// Proves the optimized pipeline is MATHEMATICALLY equivalent to the legacy
/// path it replaces:
/// - gray ROI extraction is bit-identical to crop-of-rotated-full-frame,
/// - RGB ROI / fast conversion stays within a few LSB of the bilinear path,
/// - rect rotation mapping round-trips for all sensor orientations,
/// - evaluateBox/alignBox match evaluate/align exactly,
/// - the face tracker skips ML Kit while stable and re-detects on schedule,
/// - the profiler aggregates per-stage timings correctly.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/face_alignment.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/face_quality.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/face_tracker.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_manifest.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_profiling.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/frame_geometry.dart';

Map<String, dynamic> _manifestJson({int size = 224}) => {
      'modelId': 'vit-fer-7',
      'version': '1.0.0',
      'architecture': 'test',
      'inputWidth': size,
      'inputHeight': size,
      'channels': 3,
      'colorSpace': 'RGB',
      'normalization': 'MEAN_STD_0.5',
      'tensorLayout': 'NCHW',
      'classes': [
        'anger',
        'disgust',
        'fear',
        'happy',
        'neutral',
        'sad',
        'surprise'
      ],
      'classmapVersion': 'mo-thecreator-vit-fer-7@v1',
      'productionArtifact': 'vit_fer_fp16.tflite',
      'precision': 'fp16',
      'quantization': false,
      'checksum': 'abc',
      'calibration': {'temperature': 1.0},
      'minimumConfidence': 0.60,
      'minimumMargin': 0.10,
      'qualityGate': <String, dynamic>{},
      'temporal': {'windowSize': 8, 'minStableFrames': 4},
      'preprocessingVersion': '1.0.0',
    };

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

/// Synthetic tightly packed NV21: luma gradient + neutral chroma.
Uint8List _nv21(int w, int h) {
  final out = Uint8List(w * h + w * h ~/ 2);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out[y * w + x] = (16 + (x * 3 + y * 5) % 200);
    }
  }
  for (var i = w * h; i < out.length; i += 2) {
    out[i] = 150; // V
    out[i + 1] = 100; // U
  }
  return out;
}

/// Forward sensor->upright rect mapping (half-open mirror of
/// uprightRectToSensor).
List<double> _forwardRect(double l, double t, double r, double b, int w,
    int h, int rot,) {
  switch (((rot % 360) + 360) % 360) {
    case 90:
      // (x,y) -> (H-1-y, x): x in [sx0,sx1) -> ny; y in [sy0,sy1) -> nx.
      return [h - b, l, h - t, r];
    case 180:
      return [w - r, h - b, w - l, h - t];
    case 270:
      // (x,y) -> (y, W-1-x).
      return [t, w - r, b, w - l];
    default:
      return [l, t, r, b];
  }
}

double _meanAbsDiff(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var s = 0;
  for (var i = 0; i < a.length; i++) {
    s += (a[i] - b[i]).abs();
  }
  return s / a.length;
}

void main() {
  group('uprightRectToSensor', () {
    for (final rot in [0, 90, 180, 270]) {
      test('round-trips sensor rect @ $rot°', () {
        const w = 320, h = 240;
        const l = 60.0, t = 50.0, r = 180.0, b = 170.0;
        final f = _forwardRect(l, t, r, b, w, h, rot);
        final uw = (rot == 90 || rot == 270) ? h : w;
        final uh = (rot == 90 || rot == 270) ? w : h;
        final back = uprightRectToSensor(
          left: f[0],
          top: f[1],
          right: f[2],
          bottom: f[3],
          uprightW: uw,
          uprightH: uh,
          sensorW: w,
          sensorH: h,
          rotationDeg: rot,
        );
        // Outward 0.5px expansion: recovered bounds contain the original.
        expect(back[0] <= l + 1, isTrue, reason: 'x0 $back vs $l');
        expect(back[1] <= t + 1, isTrue, reason: 'y0 $back vs $t');
        expect(back[2] >= r - 1, isTrue, reason: 'x1 $back vs $r');
        expect(back[3] >= b - 1, isTrue, reason: 'y1 $back vs $b');
        expect(back[2] - back[0] - (r - l), lessThan(4));
        expect(back[3] - back[1] - (b - t), lessThan(4));
      });
    }

    test('clamps out-of-frame boxes instead of throwing', () {
      final back = uprightRectToSensor(
        left: -50,
        top: -50,
        right: 10000,
        bottom: 10000,
        uprightW: 320,
        uprightH: 240,
        sensorW: 320,
        sensorH: 240,
        rotationDeg: 0,
      );
      expect(back, [0, 0, 320, 240]);
    });
  });

  group('gray ROI', () {
    for (final rot in [0, 90, 180, 270]) {
      test('bit-identical to crop of full upright frame @ $rot°', () {
        const w = 160, h = 120;
        final nv21 = _nv21(w, h);
        final gray = Uint8List.sublistView(nv21, 0, w * h);
        final full = rotateGrayToUpright(
            gray: Uint8List.fromList(gray), width: w, height: h,
            rotationDeg: rot,);
        // Sensor ROI -> forward upright location.
        const sx0 = 30, sy0 = 20, sw = 80, sh = 60;
        final f = _forwardRect(sx0.toDouble(), sy0.toDouble(),
            (sx0 + sw).toDouble(), (sy0 + sh).toDouble(), w, h, rot,);
        final roi = extractGrayRoiToUpright(
          nv21: nv21,
          sensorW: w,
          sensorH: h,
          roiX0: sx0,
          roiY0: sy0,
          roiW: sw,
          roiH: sh,
          rotationDeg: rot,
        );
        expect(roi.width, full.width == w ? sw : sh);
        expect(roi.height, full.height == h ? sh : sw);
        // Crop the same upright rect out of the full frame.
        final ux0 = f[0].round().clamp(0, full.width - 1);
        final uy0 = f[1].round().clamp(0, full.height - 1);
        for (var y = 0; y < roi.height; y++) {
          for (var x = 0; x < roi.width; x++) {
            expect(roi.pixels[y * roi.width + x],
                full.pixels[(uy0 + y) * full.width + (ux0 + x)],);
          }
        }
      });
    }
  });

  group('RGB conversion fast paths', () {
    test('nv21ToRgbFast ≈ nv21ToRgb (mean abs diff < 2 LSB)', () {
      const w = 96, h = 64;
      final nv21 = _nv21(w, h);
      final slow = nv21ToRgb(nv21, w, h);
      final fast = nv21ToRgbFast(nv21, w, h);
      expect(_meanAbsDiff(slow, fast), lessThan(2.0));
    });

    test('convert-then-rotate == nv21ToUprightRgb (same math, one pass)',
        () {
      const w = 96, h = 64;
      final nv21 = _nv21(w, h);
      for (final rot in [0, 90, 180, 270]) {
        final ref =
            nv21ToUprightRgb(nv21: nv21, width: w, height: h,
                rotationDeg: rot,);
        final flat = nv21ToRgb(nv21, w, h);
        final got =
            rotateRgbToUpright(rgb: flat, width: w, height: h,
                rotationDeg: rot,);
        expect(got.width, ref.width);
        expect(got.height, ref.height);
        expect(got.pixels, ref.pixels);
      }
    });

    test('ROI RGB ≈ full-frame RGB crop (mean abs diff < 5 LSB)', () {
      const w = 160, h = 120;
      final nv21 = _nv21(w, h);
      const rot = 90;
      final full = nv21ToUprightRgb(
          nv21: nv21, width: w, height: h, rotationDeg: rot,);
      const sx0 = 30, sy0 = 20, sw = 80, sh = 60;
      final roi = nv21RoiToUprightRgb(
        nv21: nv21,
        sensorW: w,
        sensorH: h,
        roiX0: sx0,
        roiY0: sy0,
        roiW: sw,
        roiH: sh,
        rotationDeg: rot,
      );
      // Upright location of the sensor ROI under 90° CW: nx = H-1-y.
      const ux0 = h - (sy0 + sh), uy0 = sx0;
      expect(roi.width, sh);
      expect(roi.height, sw);
      final ref = Uint8List(roi.width * roi.height * 3);
      for (var y = 0; y < roi.height; y++) {
        for (var x = 0; x < roi.width; x++) {
          final s = ((uy0 + y) * full.width + (ux0 + x)) * 3;
          final d = (y * roi.width + x) * 3;
          ref[d] = full.pixels[s];
          ref[d + 1] = full.pixels[s + 1];
          ref[d + 2] = full.pixels[s + 2];
        }
      }
      // NN vs bilinear chroma differ only at chroma edges; luma identical.
      expect(_meanAbsDiff(ref, roi.pixels), lessThan(5.0));
    });

    test('packNv21Into matches packNv21', () {
      const w = 64, h = 48;
      final y = Uint8List(w * h);
      for (var i = 0; i < y.length; i++) {
        y[i] = i % 251;
      }
      final uv = Uint8List(w * h ~/ 2);
      for (var i = 0; i < uv.length; i++) {
        uv[i] = (i * 7) % 256;
      }
      final planes = [
        PlaneData(bytes: y, bytesPerRow: w),
        PlaneData(bytes: uv, bytesPerRow: w),
      ];
      final ref = packNv21(planes: planes, width: w, height: h);
      final out = Uint8List(ref.length);
      packNv21Into(planes: planes, width: w, height: h, out: out);
      expect(out, ref);
    });
  });

  group('gate/align geometry-only parity', () {
    test('evaluateBox matches evaluate on the same face', () {
      final m = FerManifest.parse(_manifestJson());
      final gate = FaceQualityGate(m);
      const w = 200, h = 200;
      final gray = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          gray[y * w + x] =
              (x >= 50 && x < 150 && y >= 40 && y < 160)
                  ? 90 + ((x * 7 + y * 13) % 110)
                  : 20;
        }
      }
      final face = _face(
        box: const Rect.fromLTWH(50, 40, 100, 120),
        leftEye: const math.Point<int>(80, 80),
        rightEye: const math.Point<int>(120, 88),
        yaw: 5,
        pitch: -3,
      );
      final a = gate.evaluate(
          face: face, frameWidth: w, frameHeight: h, grayFull: gray,
          landmarksEnabled: true,);
      final b = gate.evaluateBox(
        box: face.boundingBox,
        yawDeg: face.headEulerAngleY ?? 0,
        pitchDeg: face.headEulerAngleX ?? 0,
        leftEyePresent: true,
        rightEyePresent: true,
        frameWidth: w,
        frameHeight: h,
        grayFull: gray,
        landmarksEnabled: true,
      );
      expect(b.passed, a.passed);
      expect(b.status, a.status);
      expect(b.quality, closeTo(a.quality, 1e-9));
    });

    test('alignBox matches align on the same face', () {
      const w = 200, h = 200;
      final rgb = Uint8List(w * h * 3);
      for (var i = 0; i < rgb.length; i++) {
        rgb[i] = (i * 13) % 251;
      }
      final face = _face(
        box: const Rect.fromLTWH(50, 40, 100, 120),
        leftEye: const math.Point<int>(80, 80),
        rightEye: const math.Point<int>(120, 88),
      );
      const aligner = RgbFaceAligner(outputSize: 64);
      final a = aligner.align(
          rgbFull: rgb, frameWidth: w, frameHeight: h, face: face,);
      final b = aligner.alignBox(
        rgbFull: rgb,
        frameWidth: w,
        frameHeight: h,
        box: face.boundingBox,
        leftEyeX: 80,
        leftEyeY: 80,
        rightEyeX: 120,
        rightEyeY: 88,
      );
      expect(b.method, a.method);
      expect(b.pixels, a.pixels);
    });
  });

  group('FaceTracker policy', () {
    Face trackerFace() => _face(
          box: const Rect.fromLTWH(50, 40, 100, 120),
          leftEye: const math.Point<int>(80, 80),
          rightEye: const math.Point<int>(120, 88),
        );

    test('first frame always detects', () {
      final t = FaceTracker();
      expect(t.shouldDetect(now: DateTime(2026, 1, 1)),
          FaceTrackDecision.detect,);
    });

    test('stable face reuses cache until the timeout', () {
      final t = FaceTracker(
          config: const FaceTrackerConfig(
              redetectInterval: Duration(milliseconds: 1200),),);
      final t0 = DateTime(2026, 1, 1);
      t.noteDetection([trackerFace()], now: t0);
      expect(t.shouldDetect(now: t0.add(const Duration(milliseconds: 500))),
          FaceTrackDecision.track,);
      expect(t.cachedFaces, isNotNull);
      expect(t.shouldDetect(now: t0.add(const Duration(milliseconds: 1300))),
          FaceTrackDecision.detect,);
    });

    test('repeated gate rejections force re-detection', () {
      final t = FaceTracker();
      final t0 = DateTime(2026, 1, 1);
      t.noteDetection([trackerFace()], now: t0);
      expect(t.shouldDetect(now: t0.add(const Duration(milliseconds: 10))),
          FaceTrackDecision.track,);
      t.noteGateRejection();
      t.noteGateRejection();
      expect(t.shouldDetect(now: t0.add(const Duration(milliseconds: 10))),
          FaceTrackDecision.detect,);
    });

    test('empty detection drops the track', () {
      final t = FaceTracker();
      final t0 = DateTime(2026, 1, 1);
      t.noteDetection([trackerFace()], now: t0);
      t.noteDetection([], now: t0.add(const Duration(milliseconds: 1300)));
      expect(t.hasTrack, isFalse);
      expect(t.shouldDetect(now: t0.add(const Duration(milliseconds: 1400))),
          FaceTrackDecision.detect,);
    });

    test('invalidate + reset drop the track', () {
      final t = FaceTracker();
      final t0 = DateTime(2026, 1, 1);
      t.noteDetection([trackerFace()], now: t0);
      t.invalidate();
      expect(t.hasTrack, isFalse);
      t.noteDetection([trackerFace()], now: t0);
      t.reset();
      expect(t.hasTrack, isFalse);
    });
  });

  group('FerPipelineProfiler', () {
    test('aggregates stages, drops, fps and bottleneck', () {
      final p = FerPipelineProfiler();
      p.backend = 'cpu';
      p.modelId = 'vit-fer-7';
      p.record(FerStage.inference, 100);
      p.record(FerStage.inference, 200);
      p.record(FerStage.faceDetect, 10);
      p.countFrame();
      p.countFrame();
      p.dropFrame();
      final r = p.snapshot();
      expect(r.stageAvgMs['inference'], 150.0);
      expect(r.stageAvgMs['faceDetect'], 10.0);
      expect(r.framesAnalyzed, 2);
      expect(r.droppedFrames, 1);
      expect(r.effectiveFps, greaterThanOrEqualTo(0));
      expect(p.bottleneck, FerStage.inference);
      expect(r.toLogLine(), contains('FER_PROFILE'));
      expect(r.toLogLine(), contains('backend=cpu'));
    });

    test('begin/end measures wall time', () {
      final p = FerPipelineProfiler();
      p.begin(FerStage.preprocess);
      p.end(FerStage.preprocess);
      expect(p.snapshot().stageAvgMs['preprocess'],
          greaterThanOrEqualTo(0));
    });
  });

  group('manifest mobile sizes', () {
    test('112x112x3 lightweight contract accepted', () {
      final m = FerManifest.parse(_manifestJson(size: 112));
      expect(m.inputSize, 112);
    });

    test('legacy 48px still rejected', () {
      expect(() => FerManifest.parse(_manifestJson(size: 48)),
          throwsA(isA<FerManifestError>()));
    });

    test('non-square still rejected', () {
      final j = _manifestJson(size: 112)..['inputHeight'] = 96;
      expect(
          () => FerManifest.parse(j), throwsA(isA<FerManifestError>()));
    });
  });

  group('ScratchU8', () {
    test('reuses storage across frames', () {
      final s = ScratchU8();
      final a = s.take(100);
      expect(a.length, 100);
      final b = s.take(50);
      expect(b.length, 50);
      expect(s.liveBytes, 100);
      s.take(1000);
      expect(s.liveBytes, 1000);
      s.reset();
      expect(s.liveBytes, 0);
    });
  });
}
