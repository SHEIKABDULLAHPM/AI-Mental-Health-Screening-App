/// Capture-photo emotion pipeline: isolate-offloaded face preparation.
///
/// Production bottleneck this fixes (measured on-device, SM-M325F class):
///
/// The legacy path converted the ENTIRE camera frame to RGB on the Flutter UI
/// thread ([nv21ToRgb] with bilinear chroma upsampling over ~1M pixels plus a
/// full-frame rotation) and then ran ViT inference synchronously behind it.
/// Every capture blocked the UI thread for ~1 s: the preview froze, the
/// "Analyzing..." indicator never painted, and the screen looked stuck.
///
/// This pipeline keeps the UI thread free:
/// - JPEG decode runs in the platform image codec (native, async).
/// - Face crop + eye-warp alignment + photometric quality metrics run in a
///   background isolate via [compute] (pure Dart, no plugin types).
/// - Only the 224x224 tensor normalization + `Interpreter.run` remain on the
///   calling isolate, and they operate on 50K pixels instead of ~1M.
///
/// The camera screen never opens an image stream and never calls the network:
/// one `takePicture`, one ML Kit pass (native, async), one isolate
/// preparation, one local inference. Only the final user-confirmed
/// [CameraMoodResult] leaves the device through the existing single
/// analyze/record/event chain.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Output size of the aligned face crop. Must match the manifest contract
/// (the shipped ViT artifact is 224x224x3); asserted at call time against the
/// live manifest so a future model change fails loudly, never silently.
const int kPhotoAlignSize = 224;

/// Arguments crossing the isolate boundary. Plain values only — no plugin
/// types, so the worker is unit-testable and transferable via [compute].
class PhotoPrepArgs {
  const PhotoPrepArgs({
    required this.rgba,
    required this.srcWidth,
    required this.srcHeight,
    required this.faceLeft,
    required this.faceTop,
    required this.faceRight,
    required this.faceBottom,
    this.leftEyeX,
    this.leftEyeY,
    this.rightEyeX,
    this.rightEyeY,
    this.outputSize = kPhotoAlignSize,
  });

  /// Decoded photo pixels, RGBA, row-major, [srcWidth] x [srcHeight].
  final Uint8List rgba;
  final int srcWidth;
  final int srcHeight;

  /// Face box in decoded-image coordinates (already mapped 1:1 from the
  /// ML Kit box on the same upright pixels — see caller).
  final double faceLeft;
  final double faceTop;
  final double faceRight;
  final double faceBottom;

  /// Eye centers in decoded-image coordinates, or null when landmarks were
  /// unavailable. Null eyes fall back to the tight box crop.
  final double? leftEyeX;
  final double? leftEyeY;
  final double? rightEyeX;
  final double? rightEyeY;

  final int outputSize;
}

/// Result of background face preparation. Small by design: the aligned crop
/// (224x224x3 ≈ 150 KB) plus scalar quality metrics — never full-frame data.
class PhotoPrepResult {
  const PhotoPrepResult({
    required this.alignedRgb,
    required this.outputSize,
    required this.alignMethod,
    required this.eyeDistance,
    required this.brightness,
    required this.contrast,
    required this.sharpness,
  });

  /// Interleaved RGB crop, [outputSize] x [outputSize] x 3.
  final Uint8List alignedRgb;
  final int outputSize;

  /// 'landmarks' when the eye-warp applied, 'box' for the tight-box fallback.
  final String alignMethod;
  final double eyeDistance;

  /// Photometric quality metrics over the face region (same semantics as the
  /// streaming [FaceQualityGate]: mean luminance, std-dev, Laplacian
  /// variance on a 32x32 downscale).
  final double brightness;
  final double contrast;
  final double sharpness;
}

/// Background entrypoint for [compute]. Converts the RGBA photo to an
/// aligned RGB face crop and measures photometric quality — the pixel-heavy
/// work that must never run on the UI thread.
PhotoPrepResult prepareFaceInBackground(PhotoPrepArgs args) {
  final out = args.outputSize;
  final sw = args.srcWidth;
  final sh = args.srcHeight;

  // Clamp the face box to the decoded image; degenerate boxes fall back to
  // the full frame so the caller always gets a usable crop or a clear
  // quality failure downstream — never an exception out of the isolate.
  var x0 = args.faceLeft.clamp(0.0, sw.toDouble());
  var y0 = args.faceTop.clamp(0.0, sh.toDouble());
  var x1 = args.faceRight.clamp(0.0, sw.toDouble());
  var y1 = args.faceBottom.clamp(0.0, sh.toDouble());
  if (x1 <= x0 || y1 <= y0) {
    x0 = 0;
    y0 = 0;
    x1 = sw.toDouble();
    y1 = sh.toDouble();
  }

  // Eye-based similarity warp when both eyes are present and far enough
  // apart to be a trustworthy basis (mirrors RgbFaceAligner thresholds, but
  // operates on the RGBA source directly to avoid an intermediate full-frame
  // RGB copy).
  String method = 'box';
  double eyeDistance = 0.0;
  final double? lx = args.leftEyeX;
  final double? ly = args.leftEyeY;
  final double? rx = args.rightEyeX;
  final double? ry = args.rightEyeY;
  double? pairDist;
  if (lx != null && ly != null && rx != null && ry != null) {
    pairDist = _dist(lx, ly, rx, ry);
  }
  final bool useLandmarks = pairDist != null && pairDist > 8.0;

  final aligned = Uint8List(out * out * 3);
  if (useLandmarks && lx != null && ly != null && rx != null && ry != null) {
    method = 'landmarks';
    eyeDistance = pairDist;
    _warpSimilarityRgba(
      src: args.rgba,
      sw: sw,
      sh: sh,
      lx: lx,
      ly: ly,
      rx: rx,
      ry: ry,
      out: aligned,
      outputSize: out,
    );
  } else {
    // Tight box with a 5% margin, bilinear-resized to the model input.
    const margin = 0.05;
    final mx = (x1 - x0) * margin;
    final my = (y1 - y0) * margin;
    final bx0 = (x0 - mx).clamp(0.0, sw.toDouble());
    final by0 = (y0 - my).clamp(0.0, sh.toDouble());
    final bx1 = (x1 + mx).clamp(0.0, sw.toDouble());
    final by1 = (y1 + my).clamp(0.0, sh.toDouble());
    _boxCropRgba(
      src: args.rgba,
      sw: sw,
      sh: sh,
      x0: bx0,
      y0: by0,
      x1: bx1,
      y1: by1,
      out: aligned,
      outputSize: out,
    );
  }

  // Photometric quality over the (unmargined) face region, sampled from the
  // same decoded pixels the model will see.
  final stats = _faceGrayStats(
    rgba: args.rgba,
    sw: sw,
    sh: sh,
    x0: x0,
    y0: y0,
    x1: x1,
    y1: y1,
  );

  return PhotoPrepResult(
    alignedRgb: aligned,
    outputSize: out,
    alignMethod: method,
    eyeDistance: eyeDistance,
    brightness: stats[0],
    contrast: stats[1],
    sharpness: stats[2],
  );
}

double _dist(double x0, double y0, double x1, double y1) {
  final dx = x1 - x0;
  final dy = y1 - y0;
  return math.sqrt(dx * dx + dy * dy);
}

// Canonical eye targets in output pixels (FER-style upper-third placement),
// identical to RgbFaceAligner so both pipelines see the same framing.
double _txLeft(int out) => out * 0.32;
double _txRight(int out) => out * 0.68;
double _tyEyes(int out) => out * 0.38;

void _warpSimilarityRgba({
  required Uint8List src,
  required int sw,
  required int sh,
  required double lx,
  required double ly,
  required double rx,
  required double ry,
  required Uint8List out,
  required int outputSize,
}) {
  final sux = rx - lx;
  final suy = ry - ly;
  final srcDist = math.sqrt(sux * sux + suy * suy);
  final tux = _txRight(outputSize) - _txLeft(outputSize);
  final scale = srcDist / tux;
  final angle = math.atan2(suy, sux);
  final cosA = math.cos(angle);
  final sinA = math.sin(angle);
  for (var oy = 0; oy < outputSize; oy++) {
    for (var ox = 0; ox < outputSize; ox++) {
      final ax = ox - _txLeft(outputSize);
      final ay = oy - _tyEyes(outputSize);
      final sx = lx + (ax * cosA - ay * sinA) * scale;
      final sy = ly + (ax * sinA + ay * cosA) * scale;
      _bilinearRgba(src, sw, sh, sx, sy, out, (oy * outputSize + ox) * 3);
    }
  }
}

void _boxCropRgba({
  required Uint8List src,
  required int sw,
  required int sh,
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  required Uint8List out,
  required int outputSize,
}) {
  for (var oy = 0; oy < outputSize; oy++) {
    for (var ox = 0; ox < outputSize; ox++) {
      final sx = x0 + (ox + 0.5) / outputSize * (x1 - x0) - 0.5;
      final sy = y0 + (oy + 0.5) / outputSize * (y1 - y0) - 0.5;
      _bilinearRgba(src, sw, sh, sx, sy, out, (oy * outputSize + ox) * 3);
    }
  }
}

/// Bilinear RGB sample from an RGBA source, alpha skipped.
void _bilinearRgba(
  Uint8List src,
  int sw,
  int sh,
  double x,
  double y,
  Uint8List dst,
  int dstBase,
) {
  final x0 = x.floor().clamp(0, sw - 1);
  final y0 = y.floor().clamp(0, sh - 1);
  final x1 = (x0 + 1).clamp(0, sw - 1);
  final y1 = (y0 + 1).clamp(0, sh - 1);
  final fx = (x - x0).clamp(0.0, 1.0);
  final fy = (y - y0).clamp(0.0, 1.0);
  final w00 = (1 - fx) * (1 - fy);
  final w01 = fx * (1 - fy);
  final w10 = (1 - fx) * fy;
  final w11 = fx * fy;
  final i00 = (y0 * sw + x0) * 4;
  final i01 = (y0 * sw + x1) * 4;
  final i10 = (y1 * sw + x0) * 4;
  final i11 = (y1 * sw + x1) * 4;
  for (var c = 0; c < 3; c++) {
    final v = src[i00 + c] * w00 +
        src[i01 + c] * w01 +
        src[i10 + c] * w10 +
        src[i11 + c] * w11;
    dst[dstBase + c] = v.round().clamp(0, 255);
  }
}

/// Mean luminance, std-dev, and Laplacian-variance sharpness over the face
/// region. The sharpness pass runs on a 32x32 downscale, mirroring the
/// streaming quality gate so photo and stream paths judge blur identically.
List<double> _faceGrayStats({
  required Uint8List rgba,
  required int sw,
  required int sh,
  required double x0,
  required double y0,
  required double x1,
  required double y1,
}) {
  final ix0 = x0.floor().clamp(0, sw - 1);
  final iy0 = y0.floor().clamp(0, sh - 1);
  final ix1 = x1.ceil().clamp(1, sw);
  final iy1 = y1.ceil().clamp(1, sh);
  final w = (ix1 - ix0).clamp(1, sw);
  final h = (iy1 - iy0).clamp(1, sh);

  // Cap the sampled pixels: stats on a stride-sampled grid are
  // indistinguishable from full sampling for mean/std purposes.
  final stride = math.max(1, math.min(w, h) ~/ 64);
  var sum = 0.0;
  var sumSq = 0.0;
  var n = 0;
  for (var y = iy0; y < iy1; y += stride) {
    for (var x = ix0; x < ix1; x += stride) {
      final i = (y * sw + x) * 4;
      final gray =
          0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
      sum += gray;
      sumSq += gray * gray;
      n++;
    }
  }
  if (n == 0) return [0.0, 0.0, 0.0];
  final mean = sum / n;
  final variance = math.max(0.0, sumSq / n - mean * mean);
  final std = math.sqrt(variance);

  // 32x32 downscale for the Laplacian variance.
  const dw = 32;
  const dh = 32;
  final small = Float32List(dw * dh);
  for (var y = 0; y < dh; y++) {
    for (var x = 0; x < dw; x++) {
      final sx = ix0 + (x + 0.5) / dw * w;
      final sy = iy0 + (y + 0.5) / dh * h;
      small[y * dw + x] = _sampleGray(rgba, sw, sh, sx, sy);
    }
  }
  var lapSum = 0.0;
  var lapSumSq = 0.0;
  var lapN = 0;
  for (var y = 1; y < dh - 1; y++) {
    for (var x = 1; x < dw - 1; x++) {
      final lap = small[(y - 1) * dw + x] +
          small[(y + 1) * dw + x] +
          small[y * dw + x - 1] +
          small[y * dw + x + 1] -
          4 * small[y * dw + x];
      lapSum += lap;
      lapSumSq += lap * lap;
      lapN++;
    }
  }
  final lapMean = lapSum / lapN;
  final sharpness =
      math.max(0.0, lapSumSq / lapN - lapMean * lapMean);

  return [mean, std, sharpness];
}

double _sampleGray(Uint8List rgba, int sw, int sh, double x, double y) {
  final x0 = x.floor().clamp(0, sw - 1);
  final y0 = y.floor().clamp(0, sh - 1);
  final i = (y0 * sw + x0) * 4;
  return 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
}

/// Runs [prepareFaceInBackground] off the UI thread.
///
/// Separated for testability: callers pass decoded RGBA + face geometry and
/// get back a model-ready crop without ever touching the UI isolate's event
/// loop with pixel work.
Future<PhotoPrepResult> prepareFaceOffThread(PhotoPrepArgs args) =>
    compute(prepareFaceInBackground, args);
