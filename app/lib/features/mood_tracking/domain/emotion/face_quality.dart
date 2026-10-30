import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'fer_manifest.dart';
import 'fer_result.dart';

/// Face quality gate. Runs BEFORE inference: a face that fails here never
/// reaches the model, so poor input yields a quality status instead of a
/// false emotion.
///
/// Operates on the Y (luminance) plane of the NV21 frame — no color
/// conversion needed. All thresholds come from the manifest.
class FaceQualityGate {
  const FaceQualityGate(this.manifest);
  final FerManifest manifest;

  FaceQualityReport evaluate({
    required Face face,
    required int frameWidth,
    required int frameHeight,
    required Uint8List grayFull,
    required bool landmarksEnabled,
  }) {
    final l = face.landmarks[FaceLandmarkType.leftEye];
    final r = face.landmarks[FaceLandmarkType.rightEye];
    return evaluateBox(
      box: face.boundingBox,
      yawDeg: (face.headEulerAngleY ?? 0).abs(),
      pitchDeg: (face.headEulerAngleX ?? 0).abs(),
      leftEyePresent: l != null,
      rightEyePresent: r != null,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      grayFull: grayFull,
      landmarksEnabled: landmarksEnabled,
    );
  }

  /// Geometry-only variant of [evaluate]. Same gates, same thresholds, same
  /// math — but the inputs are plain values instead of an ML Kit [Face], so
  /// the ROI fast path can run the identical gate on a cropped buffer with a
  /// shifted box. [box] is in the coordinate space of [grayFull]
  /// ([frameWidth] x [frameHeight]).
  FaceQualityReport evaluateBox({
    required Rect box,
    required double yawDeg,
    required double pitchDeg,
    required bool leftEyePresent,
    required bool rightEyePresent,
    required int frameWidth,
    required int frameHeight,
    required Uint8List grayFull,
    required bool landmarksEnabled,
    int? sizeRefWidth,
    int? sizeRefHeight,
  }) {
    final details = <String, double>{};

    // 1. Face size relative to frame. On the ROI fast path the buffer is a
    // crop, so the ratio references the FULL frame dims ([sizeRefWidth/Height])
    // while cropping/statistics run on the ROI buffer.
    final refW = sizeRefWidth ?? frameWidth;
    final refH = sizeRefHeight ?? frameHeight;
    final areaRatio = (box.width * box.height) / (refW * refH);
    details['faceSizeRatio'] = areaRatio;
    if (areaRatio < manifest.minFaceSizeRatio) {
      return FaceQualityReport.fail(FerStatus.faceTooSmall, 0.0, details);
    }

    // 2. Head pose from ML Kit euler angles.
    final yaw = yawDeg.abs();
    final pitch = pitchDeg.abs();
    details['yawDeg'] = yaw;
    details['pitchDeg'] = pitch;
    if (yaw > manifest.maxYawDeg || pitch > manifest.maxPitchDeg) {
      final q = _poseQuality(yaw, pitch);
      return FaceQualityReport.fail(FerStatus.badPose, q, details);
    }

    // 3. Crop the face box (clamped) for photometric checks.
    final crop = _cropGray(grayFull, frameWidth, frameHeight, box);
    if (crop == null) {
      return FaceQualityReport.fail(FerStatus.faceTooSmall, 0.0, details);
    }

    final mean = _mean(crop.pixels);
    final std = _std(crop.pixels, mean);
    details['brightness'] = mean;
    details['contrast'] = std;
    if (mean < manifest.minBrightness || mean > manifest.maxBrightness) {
      return FaceQualityReport.fail(
          FerStatus.badLighting, _lightQuality(mean, std), details,);
    }
    if (std < manifest.minContrast) {
      return FaceQualityReport.fail(
          FerStatus.badLighting, _lightQuality(mean, std), details,);
    }

    // 4. Sharpness: variance of Laplacian on a 32x32 downscale (cheap).
    final sharpness = _laplacianVariance(crop.pixels, crop.w, crop.h);
    details['sharpness'] = sharpness;
    if (sharpness < manifest.minSharpness) {
      return FaceQualityReport.fail(
          FerStatus.faceTooBlurry, _blurQuality(sharpness), details,);
    }

    // 5. Occlusion proxy: landmarks requested but eyes missing.
    if (landmarksEnabled) {
      details['leftEyePresent'] = leftEyePresent ? 1.0 : 0.0;
      details['rightEyePresent'] = rightEyePresent ? 1.0 : 0.0;
      if (!leftEyePresent && !rightEyePresent) {
        return FaceQualityReport.fail(FerStatus.faceOccluded, 0.3, details);
      }
    }

    final quality = _combine(areaRatio, yaw, pitch, mean, std, sharpness);
    details['quality'] = quality;
    return FaceQualityReport.pass(quality, details);
  }

  // -- metrics ---------------------------------------------------------------

  static _GrayCrop? _cropGray(Uint8List gray, int fw, int fh, Rect box) {
    var x0 = box.left.floor().clamp(0, fw - 1);
    var y0 = box.top.floor().clamp(0, fh - 1);
    var x1 = box.right.ceil().clamp(1, fw);
    var y1 = box.bottom.ceil().clamp(1, fh);
    final w = x1 - x0, h = y1 - y0;
    if (w < 8 || h < 8) return null;
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      out.setRange(y * w, y * w + w, gray, (y0 + y) * fw + x0);
    }
    return _GrayCrop(out, w, h);
  }

  static double _mean(Uint8List p) {
    var s = 0;
    for (var i = 0; i < p.length; i++) {
      s += p[i];
    }
    return s / p.length;
  }

  static double _std(Uint8List p, double mean) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final d = p[i] - mean;
      s += d * d;
    }
    return math.sqrt(s / p.length);
  }

  /// Variance of Laplacian, computed on a 32x32 area-sampled downscale.
  static double _laplacianVariance(Uint8List p, int w, int h) {
    const dw = 32, dh = 32;
    final small = Float64List(dw * dh);
    for (var y = 0; y < dh; y++) {
      for (var x = 0; x < dw; x++) {
        final sx = (x * w / dw).floor().clamp(0, w - 1);
        final sy = (y * h / dh).floor().clamp(0, h - 1);
        small[y * dw + x] = p[sy * w + sx].toDouble();
      }
    }
    var sum = 0.0, sumSq = 0.0;
    var n = 0;
    for (var y = 1; y < dh - 1; y++) {
      for (var x = 1; x < dw - 1; x++) {
        final c = small[y * dw + x];
        final lap = small[(y - 1) * dw + x] +
            small[(y + 1) * dw + x] +
            small[y * dw + x - 1] +
            small[y * dw + x + 1] -
            4 * c;
        sum += lap;
        sumSq += lap * lap;
        n++;
      }
    }
    final mean = sum / n;
    return (sumSq / n) - mean * mean;
  }

  double _poseQuality(double yaw, double pitch) =>
      ((1 - yaw / 90).clamp(0.0, 1.0) * 0.6 +
              (1 - pitch / 90).clamp(0.0, 1.0) * 0.4)
          .clamp(0.0, 1.0);

  double _lightQuality(double mean, double std) =>
      ((1 - ((mean - 127.5).abs() / 127.5)) * 0.5 +
              (std / 64).clamp(0.0, 1.0) * 0.5)
          .clamp(0.0, 1.0);

  double _blurQuality(double sharpness) =>
      (sharpness / (manifest.minSharpness * 4)).clamp(0.0, 1.0);

  double _combine(double areaRatio, double yaw, double pitch, double mean,
      double std, double sharpness,) {
    final sizeQ = (areaRatio / 0.25).clamp(0.0, 1.0);
    final poseQ = _poseQuality(yaw, pitch);
    final lightQ = _lightQuality(mean, std);
    final blurQ = _blurQuality(sharpness);
    return (sizeQ * 0.25 + poseQ * 0.25 + lightQ * 0.25 + blurQ * 0.25)
        .clamp(0.0, 1.0);
  }
}

class FaceQualityReport {
  const FaceQualityReport._(
      this.passed, this.status, this.quality, this.details,);

  factory FaceQualityReport.pass(double quality, Map<String, double> details) =>
      FaceQualityReport._(true, FerStatus.ready, quality, details);
  factory FaceQualityReport.fail(
          FerStatus status, double quality, Map<String, double> details,) =>
      FaceQualityReport._(false, status, quality, details);

  final bool passed;
  final FerStatus status;
  final double quality;
  final Map<String, double> details;
}

class _GrayCrop {
  _GrayCrop(this.pixels, this.w, this.h);
  final Uint8List pixels;
  final int w, h;
}
