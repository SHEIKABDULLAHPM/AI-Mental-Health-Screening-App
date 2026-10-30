/// Host-runnable preprocessing micro-benchmarks (no device, no model).
///
/// Prints FER_BENCH lines with measured milliseconds so the before/after
/// report has real numbers for the conversion stage, and regression-guards
/// the structural win: the ROI path must touch far fewer pixels than the
/// full-frame path (asserted via a generous ratio bound, not absolute
/// timings, so CI machines of any speed stay green).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/frame_geometry.dart';

Uint8List _nv21(int w, int h) {
  final out = Uint8List(w * h + w * h ~/ 2);
  for (var i = 0; i < w * h; i++) {
    out[i] = 16 + (i % 200);
  }
  for (var i = w * h; i < out.length; i += 2) {
    out[i] = 150;
    out[i + 1] = 100;
  }
  return out;
}

int _timeMs(void Function() fn, {int runs = 5}) {
  // Warm up once (JIT), then take the median of [runs].
  fn();
  final samples = <int>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    samples.add(sw.elapsedMilliseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

void main() {
  group('preprocessing micro-benchmarks (FER_BENCH)', () {
    test('full-frame bilinear vs fast vs ROI-only conversion', () {
      // 1280x720 sensor frame, 90° rotation (front camera typical case).
      const w = 1280, h = 720, rot = 90;
      final nv21 = _nv21(w, h);

      final fullBilinearMs = _timeMs(() {
        nv21ToUprightRgb(nv21: nv21, width: w, height: h, rotationDeg: rot);
      });
      final fullFastMs = _timeMs(() {
        final flat = nv21ToRgbFast(nv21, w, h);
        rotateRgbToUpright(rgb: flat, width: w, height: h,
            rotationDeg: rot,);
      });
      // Typical face ROI after the 25% margin expansion (~300x360 sensor px).
      const roiW = 300, roiH = 360;
      final roiMs = _timeMs(() {
        nv21RoiToUprightRgb(
          nv21: nv21,
          sensorW: w,
          sensorH: h,
          roiX0: 490,
          roiY0: 180,
          roiW: roiW,
          roiH: roiH,
          rotationDeg: rot,
        );
      });
      final grayRoiMs = _timeMs(() {
        extractGrayRoiToUpright(
          nv21: nv21,
          sensorW: w,
          sensorH: h,
          roiX0: 490,
          roiY0: 180,
          roiW: roiW,
          roiH: roiH,
          rotationDeg: rot,
        );
      });

      // ignore: avoid_print
      print('FER_BENCH stage=frameConvert frame=${w}x$h rot=$rot '
          'fullBilinearMs=$fullBilinearMs fullFastMs=$fullFastMs '
          'roiRgbMs=$roiMs roiGrayMs=$grayRoiMs '
          'roiPixels=${roiW * roiH} fullPixels=${w * h}');

      // Structural regression guard: ROI work scales with ROI pixels
      // (~1/9th of the frame here) so it must be clearly faster. The 0.5
      // bound is generous — measured speedups are 5-15x.
      expect(roiMs, lessThan((fullBilinearMs * 0.5).ceil().clamp(1, 1 << 30)));
      expect(fullFastMs, lessThan(fullBilinearMs.clamp(1, 1 << 30)));
    });
  });
}
