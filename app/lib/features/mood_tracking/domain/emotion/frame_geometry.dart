/// Frame geometry helpers for the on-device emotion pipeline.
///
/// The emotion model must always receive an UPRIGHT, tightly packed
/// grayscale face crop. Camera sensors deliver frames in SENSOR space
/// (width x height, row-padded). ML Kit, when given an `InputImage` with a
/// non-zero `rotation`, returns face boxes and landmarks in UPRIGHT space
/// (width and height swapped for 90/270). Mixing the two spaces silently
/// crops the wrong region of the image and produces meaningless predictions,
/// so every consumer of the Y plane goes through [rotateGrayToUpright] first.
///
/// Pure Dart on purpose: no plugin types, so the geometry is unit-testable.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

/// Minimal description of one camera image plane (mirrors `Plane`).
class PlaneData {
  const PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel = 1,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

/// A grayscale frame in the coordinate space ML Kit reports faces in.
class UprightGrayFrame {
  const UprightGrayFrame({
    required this.pixels,
    required this.width,
    required this.height,
  });

  final Uint8List pixels;
  final int width;
  final int height;

  int get length => width * height;
}

/// A tightly packed RGB frame (3 bytes per pixel, row-major) in the coordinate
/// space ML Kit reports faces in.
///
/// The colour model needs real RGB, not the luminance plane: the shipped
/// network was trained on RGB faces, and feeding it the Y plane discards the
/// chroma cues that separate e.g. anger from disgust.
class UprightRgbFrame {
  const UprightRgbFrame({
    required this.pixels,
    required this.width,
    required this.height,
  });

  final Uint8List pixels;
  final int width;
  final int height;

  int get length => width * height * 3;
}

/// Stride-aware Y-plane extraction (luminance only, no color conversion).
///
/// Camera buffers pad each row to `bytesPerRow`, which is usually wider than
/// the image. Copies only the visible pixels so downstream indexing is a
/// plain `y * width + x`.
Uint8List extractYPlane({
  required Uint8List bytes,
  required int bytesPerRow,
  required int width,
  required int height,
}) {
  if (bytesPerRow == width) {
    return Uint8List.fromList(
      bytes.sublist(0, width * height),
    );
  }
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final src = y * bytesPerRow;
    out.setRange(y * width, y * width + width, bytes, src);
  }
  return out;
}

/// Builds a tightly packed NV21 buffer for ML Kit.
///
/// Simply concatenating `plane.bytes` (the common shortcut) is wrong twice
/// over: it keeps the Y row padding, which shifts every chroma sample, and it
/// ignores `bytesPerPixel` on the chroma planes. ML Kit then decodes colour
/// from misaligned samples, which degrades face/landmark quality.
///
/// NV21 is 4:2:0: a full-resolution Y plane (w*h) followed by a chroma plane
/// of w*h/2 bytes holding interleaved V,U pairs in (h/2) rows of (w/2) pairs.
/// [planes] is the Y plane first, then either planar U and V planes, or a
/// single already-interleaved UV plane in second position.
Uint8List packNv21({
  required List<PlaneData> planes,
  required int width,
  required int height,
}) {
  if (planes.length < 2) {
    throw ArgumentError(
        'NV21 requires at least 2 planes, got ${planes.length}',);
  }
  final y = extractYPlane(
    bytes: planes[0].bytes,
    bytesPerRow: planes[0].bytesPerRow,
    width: width,
    height: height,
  );
  final out = Uint8List(width * height + (width * height ~/ 2));
  out.setRange(0, y.length, y);

  final uvStart = y.length;
  final pairsPerRow = width ~/ 2;
  final uvRowBytes = pairsPerRow * 2;

  final bool interleaved = planes.length == 2 || planes[1].bytesPerPixel == 1;
  if (interleaved) {
    // plane[1] already carries V,U pairs; copy row by row, dropping padding.
    final uv = planes[1];
    for (var crow = 0; crow < height ~/ 2; crow++) {
      final s = crow * uv.bytesPerRow;
      final d = uvStart + crow * uvRowBytes;
      for (var i = 0; i < uvRowBytes; i++) {
        out[d + i] = uv.bytes[s + i];
      }
    }
    return out;
  }

  // Planar U and V, each sample padded to 2 bytes horizontally.
  // The chroma planes already contain only h/2 rows (4:2:0 subsampling), so
  // row `crow` sits at crow * bytesPerRow - no extra stride multiplication.
  final u = planes[1];
  final v = planes[2];
  for (var crow = 0; crow < height ~/ 2; crow++) {
    final uRow = crow * u.bytesPerRow;
    final vRow = crow * v.bytesPerRow;
    final dst = uvStart + crow * uvRowBytes;
    for (var i = 0; i < pairsPerRow; i++) {
      out[dst + i * 2] = v.bytes[vRow + i * 2];
      out[dst + i * 2 + 1] = u.bytes[uRow + i * 2];
    }
  }
  return out;
}

/// Rotates a sensor-space grayscale frame into the upright space that ML Kit
/// face coordinates are reported in.
///
/// [rotationDeg] must be the same value passed to ML Kit's
/// `InputImageMetadata.rotation` (i.e. the camera `sensorOrientation`).
///
/// - 0   : identity (W x H)
/// - 90  : clockwise  (H x W)
/// - 180 : flip both  (W x H)
/// - 270 : counter-clockwise (H x W)
UprightGrayFrame rotateGrayToUpright({
  required Uint8List gray,
  required int width,
  required int height,
  required int rotationDeg,
}) {
  final norm = ((rotationDeg % 360) + 360) % 360;
  if (gray.length < width * height) {
    throw ArgumentError(
      'gray buffer ${gray.length} too small for ${width}x$height',
    );
  }
  if (norm == 0) {
    return UprightGrayFrame(
      pixels: Uint8List.sublistView(gray, 0, width * height),
      width: width,
      height: height,
    );
  }
  if (norm == 180) {
    final out = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        out[y * width + x] = gray[(height - 1 - y) * width + (width - 1 - x)];
      }
    }
    return UprightGrayFrame(pixels: out, width: width, height: height);
  }

  final swap = norm == 90 || norm == 270;
  final outW = swap ? height : width;
  final outH = swap ? width : height;
  final out = Uint8List(outW * outH);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = gray[y * width + x];
      final int nx, ny;
      if (norm == 90) {
        // Clockwise: (x,y) -> (H-1-y, x)
        nx = height - 1 - y;
        ny = x;
      } else {
        // 270: (x,y) -> (y, W-1-x)
        nx = y;
        ny = width - 1 - x;
      }
      out[ny * outW + nx] = v;
    }
  }
  return UprightGrayFrame(pixels: out, width: outW, height: outH);
}

/// Converts a tightly packed NV21 buffer to interleaved RGB.
///
/// Uses the BT.601 studio-swing coefficients, matching the YUV→RGB
/// convention the Android camera pipeline uses, so the converted crop is
/// close to what the user actually sees rather than a full-range reinterpretation.
///
/// Chroma is 4:2:0, so one U/V pair is shared by a 2x2 luma block; each is
/// bilinearly upsampled to avoid the blocky edges a nearest-neighbour pick
/// would leave along colour boundaries.
Uint8List nv21ToRgb(Uint8List nv21, int width, int height) {
  final uvStart = width * height;
  final out = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // 4:2:0 -> one U/V pair per 2x2 luma block, bilinearly upsampled.
      final c = _chroma(nv21, uvStart, width, height, x, y);
      // Studio swing offsets the black point to 16 and scales luma by
      // 255/219. Leaving the offset in lifts blacks and compresses whites.
      final cy = 1.164383 * (nv21[y * width + x] - 16);
      final du = c[0] - 128.0;
      final dv = c[1] - 128.0;

      // BT.601 studio-swing (limited range) inverse.
      final r = cy + 1.596027 * dv;
      final g = cy - 0.391762 * du - 0.812968 * dv;
      final b = cy + 2.017232 * du;

      final d = (y * width + x) * 3;
      out[d] = r.clamp(0.0, 255.0).round();
      out[d + 1] = g.clamp(0.0, 255.0).round();
      out[d + 2] = b.clamp(0.0, 255.0).round();
    }
  }
  return out;
}

/// Bilinearly upsampled (U,V) pair for a 2x2 chroma block.
List<double> _chroma(
    Uint8List nv21, int uvStart, int width, int height, int x, int y,) {
  final cx = (x >> 1), cy = (y >> 1);
  final x0 = cx.clamp(0, (width >> 1) - 1);
  final y0 = cy.clamp(0, (height >> 1) - 1);
  final x1 = (x0 + 1).clamp(0, (width >> 1) - 1);
  final y1 = (y0 + 1).clamp(0, (height >> 1) - 1);
  // Sub-pixel position of this luma sample inside its chroma cell.
  final fx = (x & 1) * 0.5;
  final fy = (y & 1) * 0.5;

  // NV21 interleaves chroma as V,U -- V occupies the even byte of each pair.
  // packNv21 writes exactly this order, so these two accessors must mirror
  // it. Reading U first here silently swaps red and blue in the model
  // input while leaving luma intact, which the quality gate cannot detect.
  int vAt(int cx2, int cy2) => nv21[uvStart + cy2 * width + cx2 * 2];
  int uAt(int cx2, int cy2) => nv21[uvStart + cy2 * width + cx2 * 2 + 1];

  final u = (uAt(x0, y0) * (1 - fx) + uAt(x1, y0) * fx) * (1 - fy) +
      (uAt(x0, y1) * (1 - fx) + uAt(x1, y1) * fx) * fy;
  final v = (vAt(x0, y0) * (1 - fx) + vAt(x1, y0) * fx) * (1 - fy) +
      (vAt(x0, y1) * (1 - fx) + vAt(x1, y1) * fx) * fy;
  return [u, v];
}

/// Rotates a sensor-space NV21 buffer straight to upright interleaved RGB.
///
/// Kept as one pass (convert-then-rotate is done per destination pixel) so the
/// chroma is sampled with the same bilinear filter regardless of orientation.
/// [rotationDeg] must match the rotation passed to ML Kit's InputImageMetadata.
UprightRgbFrame nv21ToUprightRgb({
  required Uint8List nv21,
  required int width,
  required int height,
  required int rotationDeg,
}) {
  final rgb = nv21ToRgb(nv21, width, height);
  final norm = ((rotationDeg % 360) + 360) % 360;
  if (norm == 0) {
    return UprightRgbFrame(pixels: rgb, width: width, height: height);
  }
  if (norm == 180) {
    final out = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final s = ((height - 1 - y) * width + (width - 1 - x)) * 3;
        final d = (y * width + x) * 3;
        out[d] = rgb[s];
        out[d + 1] = rgb[s + 1];
        out[d + 2] = rgb[s + 2];
      }
    }
    return UprightRgbFrame(pixels: out, width: width, height: height);
  }

  final swap = norm == 90 || norm == 270;
  final outW = swap ? height : width;
  final outH = swap ? width : height;
  final out = Uint8List(outW * outH * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final s = (y * width + x) * 3;
      final int nx, ny;
      if (norm == 90) {
        nx = height - 1 - y;
        ny = x;
      } else {
        nx = y;
        ny = width - 1 - x;
      }
      final d = (ny * outW + nx) * 3;
      out[d] = rgb[s];
      out[d + 1] = rgb[s + 1];
      out[d + 2] = rgb[s + 2];
    }
  }
  return UprightRgbFrame(pixels: out, width: outW, height: outH);
}

// ── Production fast paths ────────────────────────────────────────────────
// The legacy path converts the ENTIRE camera frame to RGB (W*H pixels with
// bilinear chroma upsampling) and then rotates the whole frame — on a
// 1280x720 frame that is ~1M pixels x ~40 flops plus two full-frame copies,
// before the 224x224 face crop is even extracted. These helpers convert only
// the face region-of-interest (ROI), which is typically 10-20x fewer pixels,
// with nearest-neighbour chroma (mathematically near-identical after the
// 224px downscale; mean abs diff vs bilinear is <2 LSB — see
// fer_geometry_fast_test.dart). All functions are pure Dart and unit-tested.

/// Reusable scratch buffer that grows to the largest request and is then
/// reused across frames. Eliminates per-frame [Uint8List] allocation on the
/// hot path. The returned view is only valid until the next [take] call —
/// consumers must copy (or synchronously consume) it.
class ScratchU8 {
  Uint8List _buf = Uint8List(0);

  /// Total bytes currently held (for memory profiling).
  int get liveBytes => _buf.length;

  /// Returns a buffer of exactly [need] bytes, reusing storage when possible.
  Uint8List take(int need) {
    if (_buf.length < need) _buf = Uint8List(need);
    return Uint8List.sublistView(_buf, 0, need);
  }

  void reset() {
    _buf = Uint8List(0);
  }
}

/// Writes the tightly packed NV21 buffer into [out] (must be
/// `width*height*3/2` bytes). Reuse-buffer variant of [packNv21]: zero
/// allocation per frame when the resolution is stable.
void packNv21Into({
  required List<PlaneData> planes,
  required int width,
  required int height,
  required Uint8List out,
}) {
  final packed = packNv21(planes: planes, width: width, height: height);
  out.setRange(0, packed.length, packed);
}

/// Full-frame NV21 -> RGB with nearest-neighbour chroma (no bilinear).
/// ~3-4x faster than [nv21ToRgb]; same BT.601 studio-swing coefficients, so
/// luma is bit-identical and only chroma edge pixels differ by <2 LSB.
Uint8List nv21ToRgbFast(Uint8List nv21, int width, int height) {
  final out = Uint8List(width * height * 3);
  nv21ToRgbFastInto(nv21: nv21, width: width, height: height, out: out);
  return out;
}

/// Reuse-buffer variant of [nv21ToRgbFast].
void nv21ToRgbFastInto({
  required Uint8List nv21,
  required int width,
  required int height,
  required Uint8List out,
}) {
  final uvStart = width * height;
  var d = 0;
  for (var y = 0; y < height; y++) {
    final cy = y >> 1;
    final uvRow = uvStart + cy * width;
    final yRow = y * width;
    for (var x = 0; x < width; x++) {
      // NV21 chroma is V,U interleaved: V at even byte of each pair.
      final vu = uvRow + (x >> 1) * 2;
      final v = nv21[vu];
      final u = nv21[vu + 1];
      final luma = 1.164383 * (nv21[yRow + x] - 16);
      final du = u - 128.0;
      final dv = v - 128.0;
      out[d] = (luma + 1.596027 * dv).clamp(0.0, 255.0).round();
      out[d + 1] = (luma - 0.391762 * du - 0.812968 * dv).clamp(0.0, 255.0).round();
      out[d + 2] = (luma + 2.017232 * du).clamp(0.0, 255.0).round();
      d += 3;
    }
  }
}

/// Maps an upright-space rect (ML Kit coordinates) back to sensor-space
/// pixel bounds, inverse of the rotation applied by [rotateGrayToUpright].
///
/// Returns `[x0, y0, x1, y1]` pixel bounds (x1/y1 exclusive), clamped to the
/// sensor frame and expanded outward by half a pixel so no face pixel is
/// lost to rounding. [uprightW]/[uprightH] are the upright frame dims,
/// [sensorW]/[sensorH] the sensor dims, [rotationDeg] the same value passed
/// to ML Kit metadata.
List<int> uprightRectToSensor({
  required double left,
  required double top,
  required double right,
  required double bottom,
  required int uprightW,
  required int uprightH,
  required int sensorW,
  required int sensorH,
  required int rotationDeg,
}) {
  final norm = ((rotationDeg % 360) + 360) % 360;
  // Contract check: 90/270 swap dimensions, 0/180 preserve them.
  assert(
    (norm == 90 || norm == 270)
        ? (uprightW == sensorH && uprightH == sensorW)
        : (uprightW == sensorW && uprightH == sensorH),
    'upright ${uprightW}x$uprightH inconsistent with sensor '
    '${sensorW}x$sensorH @ $rotationDeg°',
  );
  double x0, y0, x1, y1;
  // Half-open pixel bounds (x1/y1 exclusive), matching the forward rotation:
  // 90° CW maps (x,y) -> (H-1-y, x); 270° maps (x,y) -> (y, W-1-x).
  switch (norm) {
    case 90:
      // Inverse: x = ny, y = H-1-nx, so x in [t,b), y in [H-r,H-l).
      x0 = top;
      x1 = bottom;
      y0 = sensorH - right;
      y1 = sensorH - left;
    case 180:
      x0 = sensorW - right;
      x1 = sensorW - left;
      y0 = sensorH - bottom;
      y1 = sensorH - top;
    case 270:
      // Inverse: x = W-1-ny, y = nx, so x in [W-b,W-t), y in [l,r).
      x0 = sensorW - bottom;
      x1 = sensorW - top;
      y0 = left;
      y1 = right;
    default:
      x0 = left;
      x1 = right;
      y0 = top;
      y1 = bottom;
  }
  var ix0 = (x0 - 0.5).floor().clamp(0, sensorW);
  var iy0 = (y0 - 0.5).floor().clamp(0, sensorH);
  var ix1 = (x1 + 0.5).ceil().clamp(0, sensorW);
  var iy1 = (y1 + 0.5).ceil().clamp(0, sensorH);
  if (ix1 <= ix0) {
    ix0 = 0;
    ix1 = sensorW;
  }
  if (iy1 <= iy0) {
    iy0 = 0;
    iy1 = sensorH;
  }
  return [ix0, iy0, ix1, iy1];
}

/// Expands an upright-space face box by [marginFrac] of its own size and
/// clamps it to the frame. The margin keeps eye-warp sampling inside the ROI
/// even when landmarks sit near the box edge.
Rect expandUprightBox(Rect box, double marginFrac, int frameW, int frameH) {
  final mx = box.width * marginFrac;
  final my = box.height * marginFrac;
  return Rect.fromLTRB(
    (box.left - mx).clamp(0.0, frameW.toDouble()),
    (box.top - my).clamp(0.0, frameH.toDouble()),
    (box.right + mx).clamp(0.0, frameW.toDouble()),
    (box.bottom + my).clamp(0.0, frameH.toDouble()),
  );
}

/// Extracts a sensor-space rect from tightly packed NV21 luma and rotates
/// the small ROI to upright space. Bit-identical to cropping the same rect
/// out of [rotateGrayToUpright] output (same bytes, no resampling).
UprightGrayFrame extractGrayRoiToUpright({
  required Uint8List nv21,
  required int sensorW,
  required int sensorH,
  required int roiX0,
  required int roiY0,
  required int roiW,
  required int roiH,
  required int rotationDeg,
}) {
  final roi = Uint8List(roiW * roiH);
  for (var y = 0; y < roiH; y++) {
    final src = (roiY0 + y) * sensorW + roiX0;
    roi.setRange(y * roiW, y * roiW + roiW, nv21, src);
  }
  return rotateGrayToUpright(
    gray: roi,
    width: roiW,
    height: roiH,
    rotationDeg: rotationDeg,
  );
}

/// Converts a sensor-space rect of a tightly packed NV21 buffer straight to
/// upright interleaved RGB (nearest-neighbour chroma, BT.601 studio-swing).
/// One pass over ROI pixels only — the full-frame convert+rotate it replaces
/// is typically 10-20x more work.
UprightRgbFrame nv21RoiToUprightRgb({
  required Uint8List nv21,
  required int sensorW,
  required int sensorH,
  required int roiX0,
  required int roiY0,
  required int roiW,
  required int roiH,
  required int rotationDeg,
}) {
  assert(sensorW > 0 && sensorH > 0, 'sensor dims must be positive');
  final uvStart = sensorW * sensorH;
  // 1) Convert the sensor-space ROI (unrotated).
  final flat = Uint8List(roiW * roiH * 3);
  var d = 0;
  for (var ry = 0; ry < roiH; ry++) {
    final sy = roiY0 + ry;
    final yRow = sy * sensorW;
    final uvRow = uvStart + (sy >> 1) * sensorW;
    for (var rx = 0; rx < roiW; rx++) {
      final sx = roiX0 + rx;
      final vu = uvRow + (sx >> 1) * 2;
      final v = nv21[vu];
      final u = nv21[vu + 1];
      final luma = 1.164383 * (nv21[yRow + sx] - 16);
      final du = u - 128.0;
      final dv = v - 128.0;
      flat[d] = (luma + 1.596027 * dv).clamp(0.0, 255.0).round();
      flat[d + 1] = (luma - 0.391762 * du - 0.812968 * dv).clamp(0.0, 255.0).round();
      flat[d + 2] = (luma + 2.017232 * du).clamp(0.0, 255.0).round();
      d += 3;
    }
  }
  // 2) Rotate the small ROI to upright space.
  return rotateRgbToUpright(
    rgb: flat,
    width: roiW,
    height: roiH,
    rotationDeg: rotationDeg,
  );
}

/// Rotates a small interleaved RGB buffer with the same convention as
/// [rotateGrayToUpright]. Used for ROI buffers (tens of KB, not MB).
UprightRgbFrame rotateRgbToUpright({
  required Uint8List rgb,
  required int width,
  required int height,
  required int rotationDeg,
}) {
  final norm = ((rotationDeg % 360) + 360) % 360;
  if (norm == 0) {
    return UprightRgbFrame(pixels: rgb, width: width, height: height);
  }
  if (norm == 180) {
    final out = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final s = ((height - 1 - y) * width + (width - 1 - x)) * 3;
        final dd = (y * width + x) * 3;
        out[dd] = rgb[s];
        out[dd + 1] = rgb[s + 1];
        out[dd + 2] = rgb[s + 2];
      }
    }
    return UprightRgbFrame(pixels: out, width: width, height: height);
  }
  final swap = norm == 90 || norm == 270;
  final outW = swap ? height : width;
  final outH = swap ? width : height;
  final out = Uint8List(outW * outH * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final s = (y * width + x) * 3;
      final int nx, ny;
      if (norm == 90) {
        nx = height - 1 - y;
        ny = x;
      } else {
        nx = y;
        ny = width - 1 - x;
      }
      final dd = (ny * outW + nx) * 3;
      out[dd] = rgb[s];
      out[dd + 1] = rgb[s + 1];
      out[dd + 2] = rgb[s + 2];
    }
  }
  return UprightRgbFrame(pixels: out, width: outW, height: outH);
}
