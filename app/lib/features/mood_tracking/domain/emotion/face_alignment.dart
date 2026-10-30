import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Eye-based similarity alignment.
///
/// Maps the detected eye centers onto canonical targets so the classifier
/// always sees a consistently aligned 64x64 crop (rotation + scale +
/// translation normalized). Falls back to a tight bounding-box crop when
/// landmarks are unavailable; the method is reported so callers can apply
/// a quality penalty instead of silently degrading.
class FaceAligner {
  const FaceAligner({this.outputSize = 64});

  final int outputSize;

  /// Canonical eye targets in output pixels (FER-style upper-third placement).
  double get _txLeft => outputSize * 0.32;
  double get _txRight => outputSize * 0.68;
  double get _tyEyes => outputSize * 0.38;

  AlignedFace align({
    required Uint8List grayFull,
    required int frameWidth,
    required int frameHeight,
    required Face face,
  }) {
    final left = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final right = face.landmarks[FaceLandmarkType.rightEye]?.position;
    if (left != null && right != null) {
      final dx = right.x - left.x, dy = right.y - left.y;
      final eyeDist = math.sqrt(dx * dx + dy * dy);
      if (eyeDist > 4) {
        final out = _warpSimilarity(
          grayFull,
          frameWidth,
          frameHeight,
          left.x.toDouble(),
          left.y.toDouble(),
          right.x.toDouble(),
          right.y.toDouble(),
        );
        return AlignedFace(out, 'landmarks', eyeDist);
      }
    }
    final out = _boxCrop(grayFull, frameWidth, frameHeight, face.boundingBox);
    return AlignedFace(out, 'box', 0.0);
  }

  /// Inverse-map each output pixel through the similarity transform and
  /// bilinear-sample the source. Similarity solved from the two eye pairs.
  Uint8List _warpSimilarity(Uint8List src, int sw, int sh, double lx, double ly,
      double rx, double ry,) {
    // Source basis: u = right-left (eye axis), v = perp. Target basis fixed.
    final sux = rx - lx, suy = ry - ly;
    final srcDist = math.sqrt(sux * sux + suy * suy);
    final tux = _txRight - _txLeft; // horizontal, ty equal
    final scale = srcDist / tux;
    // Rotation of source eye axis vs horizontal.
    final angle = math.atan2(suy, sux);
    final cosA = math.cos(angle), sinA = math.sin(angle);
    // Source point for output (ox,oy): start at left eye, step along
    // rotated/scaled axes.
    final out = Uint8List(outputSize * outputSize);
    for (var oy = 0; oy < outputSize; oy++) {
      for (var ox = 0; ox < outputSize; ox++) {
        final ax = ox - _txLeft; // target-space offset from left-eye target
        final ay = oy - _tyEyes;
        // Rotate by +angle and scale (target->source).
        final sx = lx + (ax * cosA - ay * sinA) * scale;
        final sy = ly + (ax * sinA + ay * cosA) * scale;
        out[oy * outputSize + ox] = _bilinear(src, sw, sh, sx, sy);
      }
    }
    return out;
  }

  Uint8List _boxCrop(Uint8List src, int sw, int sh, Rect box) {
    // Tight box with a 5% margin; bilinear resize to output.
    final mx = box.width * 0.05, my = box.height * 0.05;
    final x0 = (box.left - mx).clamp(0.0, sw.toDouble());
    final y0 = (box.top - my).clamp(0.0, sh.toDouble());
    final x1 = (box.right + mx).clamp(0.0, sw.toDouble());
    final y1 = (box.bottom + my).clamp(0.0, sh.toDouble());
    final out = Uint8List(outputSize * outputSize);
    for (var oy = 0; oy < outputSize; oy++) {
      for (var ox = 0; ox < outputSize; ox++) {
        final sx = x0 + (ox + 0.5) / outputSize * (x1 - x0) - 0.5;
        final sy = y0 + (oy + 0.5) / outputSize * (y1 - y0) - 0.5;
        out[oy * outputSize + ox] = _bilinear(src, sw, sh, sx, sy);
      }
    }
    return out;
  }

  static int _bilinear(Uint8List src, int sw, int sh, double x, double y) {
    final x0 = x.floor().clamp(0, sw - 1);
    final y0 = y.floor().clamp(0, sh - 1);
    final x1 = (x0 + 1).clamp(0, sw - 1);
    final y1 = (y0 + 1).clamp(0, sh - 1);
    final fx = (x - x0).clamp(0.0, 1.0);
    final fy = (y - y0).clamp(0.0, 1.0);
    final a = src[y0 * sw + x0].toDouble();
    final b = src[y0 * sw + x1].toDouble();
    final c = src[y1 * sw + x0].toDouble();
    final d = src[y1 * sw + x1].toDouble();
    return ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
        .round()
        .clamp(0, 255);
  }
}

class AlignedFace {
  const AlignedFace(this.pixels64, this.method, this.eyeDistance);
  final Uint8List pixels64;
  final String method; // 'landmarks' | 'box'
  final double eyeDistance;
}

/// RGB similarity alignment for the 224x224 ViT pipeline.
///
/// Mirrors [FaceAligner] (eye-driven similarity warp, tight-box fallback) but
/// keeps all three channels, because the shipped model was trained on RGB
/// faces and the chroma carries real class information.
///
/// Output is tightly packed interleaved RGB, ready for the NCHW float
/// conversion in [FerPreprocessing].
class RgbFaceAligner {
  const RgbFaceAligner({this.outputSize = 224});

  final int outputSize;

  /// Canonical eye targets, matching the FER-style upper-third placement used
  /// by the grayscale aligner so both pipelines see the same framing.
  double get _txLeft => outputSize * 0.32;
  double get _txRight => outputSize * 0.68;
  double get _tyEyes => outputSize * 0.38;

  AlignedRgbFace align({
    required Uint8List rgbFull,
    required int frameWidth,
    required int frameHeight,
    required Face face,
  }) {
    final left = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final right = face.landmarks[FaceLandmarkType.rightEye]?.position;
    return alignBox(
      rgbFull: rgbFull,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      box: face.boundingBox,
      leftEyeX: left?.x.toDouble(),
      leftEyeY: left?.y.toDouble(),
      rightEyeX: right?.x.toDouble(),
      rightEyeY: right?.y.toDouble(),
    );
  }

  /// Geometry-only variant of [align]. Same warp, same fallback, same
  /// canonical eye targets — but coordinates are plain values in the space
  /// of [rgbFull], so an ROI-cropped buffer works with ROI-relative
  /// coordinates. Null eye coordinates (or too-close eyes) fall back to the
  /// tight box crop and report method 'box', exactly like [align].
  AlignedRgbFace alignBox({
    required Uint8List rgbFull,
    required int frameWidth,
    required int frameHeight,
    required Rect box,
    double? leftEyeX,
    double? leftEyeY,
    double? rightEyeX,
    double? rightEyeY,
  }) {
    if (leftEyeX != null &&
        leftEyeY != null &&
        rightEyeX != null &&
        rightEyeY != null) {
      final dx = rightEyeX - leftEyeX, dy = rightEyeY - leftEyeY;
      final eyeDist = math.sqrt(dx * dx + dy * dy);
      // Below this the landmarks are not a trustworthy similarity basis.
      if (eyeDist > 8) {
        return AlignedRgbFace(
          _warpSimilarity(rgbFull, frameWidth, frameHeight, leftEyeX,
              leftEyeY, rightEyeX, rightEyeY,),
          'landmarks',
          eyeDist,
        );
      }
    }
    return AlignedRgbFace(
      _boxCrop(rgbFull, frameWidth, frameHeight, box),
      'box',
      0.0,
    );
  }

  Uint8List _warpSimilarity(Uint8List src, int sw, int sh, double lx, double ly,
      double rx, double ry,) {
    final sux = rx - lx, suy = ry - ly;
    final srcDist = math.sqrt(sux * sux + suy * suy);
    final tux = _txRight - _txLeft;
    final scale = srcDist / tux;
    final angle = math.atan2(suy, sux);
    final cosA = math.cos(angle), sinA = math.sin(angle);
    final out = Uint8List(outputSize * outputSize * 3);
    for (var oy = 0; oy < outputSize; oy++) {
      for (var ox = 0; ox < outputSize; ox++) {
        final ax = ox - _txLeft;
        final ay = oy - _tyEyes;
        final sx = lx + (ax * cosA - ay * sinA) * scale;
        final sy = ly + (ax * sinA + ay * cosA) * scale;
        _bilinearRgb(src, sw, sh, sx, sy, out, (oy * outputSize + ox) * 3);
      }
    }
    return out;
  }

  Uint8List _boxCrop(Uint8List src, int sw, int sh, Rect box) {
    final mx = box.width * 0.05, my = box.height * 0.05;
    final x0 = (box.left - mx).clamp(0.0, sw.toDouble());
    final y0 = (box.top - my).clamp(0.0, sh.toDouble());
    final x1 = (box.right + mx).clamp(0.0, sw.toDouble());
    final y1 = (box.bottom + my).clamp(0.0, sh.toDouble());
    final out = Uint8List(outputSize * outputSize * 3);
    for (var oy = 0; oy < outputSize; oy++) {
      for (var ox = 0; ox < outputSize; ox++) {
        final sx = x0 + (ox + 0.5) / outputSize * (x1 - x0) - 0.5;
        final sy = y0 + (oy + 0.5) / outputSize * (y1 - y0) - 0.5;
        _bilinearRgb(src, sw, sh, sx, sy, out, (oy * outputSize + ox) * 3);
      }
    }
    return out;
  }

  /// Bilinear RGB sample written straight into [dst] at [dstBase].
  static void _bilinearRgb(Uint8List src, int sw, int sh, double x, double y,
      Uint8List dst, int dstBase,) {
    final x0 = x.floor().clamp(0, sw - 1);
    final y0 = y.floor().clamp(0, sh - 1);
    final x1 = (x0 + 1).clamp(0, sw - 1);
    final y1 = (y0 + 1).clamp(0, sh - 1);
    final fx = (x - x0).clamp(0.0, 1.0);
    final fy = (y - y0).clamp(0.0, 1.0);
    final w00 = (1 - fx) * (1 - fy), w01 = fx * (1 - fy);
    final w10 = (1 - fx) * fy, w11 = fx * fy;
    final i00 = (y0 * sw + x0) * 3, i01 = (y0 * sw + x1) * 3;
    final i10 = (y1 * sw + x0) * 3, i11 = (y1 * sw + x1) * 3;
    for (var c = 0; c < 3; c++) {
      final v = src[i00 + c] * w00 +
          src[i01 + c] * w01 +
          src[i10 + c] * w10 +
          src[i11 + c] * w11;
      dst[dstBase + c] = v.round().clamp(0, 255);
    }
  }
}

class AlignedRgbFace {
  const AlignedRgbFace(this.pixels, this.method, this.eyeDistance);
  final Uint8List pixels; // outputSize * outputSize * 3, interleaved RGB
  final String method; // 'landmarks' | 'box'
  final double eyeDistance;
}
