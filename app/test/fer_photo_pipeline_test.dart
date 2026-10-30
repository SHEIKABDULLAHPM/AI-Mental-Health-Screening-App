import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/features/mood_tracking/domain/emotion/fer_photo_pipeline.dart';

/// Synthetic 64x48 RGBA image: textured face-like box on a dark background.
/// The checkerboard texture gives the face region real contrast and edge
/// energy so quality metrics are non-degenerate.
Uint8List _syntheticRgba(int w, int h) {
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inFace = x >= 16 && x < 48 && y >= 8 && y < 40;
      final int v;
      if (!inFace) {
        v = 20;
      } else {
        v = ((x + y) % 2 == 0) ? 200 : 120;
      }
      final i = (y * w + x) * 4;
      px[i] = v;
      px[i + 1] = v;
      px[i + 2] = v;
      px[i + 3] = 255;
    }
  }
  return px;
}

void main() {
  group('prepareFaceInBackground (isolate entrypoint)', () {
    test('box fallback returns a 224x224x3 crop with sane quality', () {
      final result = prepareFaceInBackground(
        PhotoPrepArgs(
          rgba: _syntheticRgba(64, 48),
          srcWidth: 64,
          srcHeight: 48,
          faceLeft: 16,
          faceTop: 8,
          faceRight: 48,
          faceBottom: 40,
          outputSize: 224,
        ),
      );

      expect(result.alignedRgb.length, 224 * 224 * 3);
      expect(result.alignMethod, 'box');
      expect(result.outputSize, 224);
      // Bright face region: mean well above the dark background.
      expect(result.brightness, greaterThan(100));
      expect(result.contrast, greaterThan(0));
      expect(result.sharpness, greaterThanOrEqualTo(0));
    });

    test('landmark warp engages with wide-apart eyes', () {
      final result = prepareFaceInBackground(
        PhotoPrepArgs(
          rgba: _syntheticRgba(64, 48),
          srcWidth: 64,
          srcHeight: 48,
          faceLeft: 16,
          faceTop: 8,
          faceRight: 48,
          faceBottom: 40,
          leftEyeX: 24,
          leftEyeY: 20,
          rightEyeX: 40,
          rightEyeY: 20,
          outputSize: 224,
        ),
      );

      expect(result.alignMethod, 'landmarks');
      expect(result.eyeDistance, closeTo(16.0, 0.001));
      expect(result.alignedRgb.length, 224 * 224 * 3);
    });

    test('close-together eyes fall back to the box crop', () {
      final result = prepareFaceInBackground(
        PhotoPrepArgs(
          rgba: _syntheticRgba(64, 48),
          srcWidth: 64,
          srcHeight: 48,
          faceLeft: 16,
          faceTop: 8,
          faceRight: 48,
          faceBottom: 40,
          leftEyeX: 30,
          leftEyeY: 20,
          rightEyeX: 33,
          rightEyeY: 20,
          outputSize: 224,
        ),
      );

      expect(result.alignMethod, 'box');
    });

    test('degenerate box never throws (clamps to frame)', () {
      final result = prepareFaceInBackground(
        PhotoPrepArgs(
          rgba: _syntheticRgba(64, 48),
          srcWidth: 64,
          srcHeight: 48,
          faceLeft: 999,
          faceTop: 999,
          faceRight: -5,
          faceBottom: -5,
          outputSize: 224,
        ),
      );

      expect(result.alignedRgb.length, 224 * 224 * 3);
    });
  });
}
