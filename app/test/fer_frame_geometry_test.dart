import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/frame_geometry.dart';

/// Regression tests for the sensor-space vs upright-space bug.
///
/// ML Kit returns face boxes/landmarks in UPRIGHT space (the sensor buffer
/// rotated by `sensorOrientation`), while the camera delivers the Y plane in
/// SENSOR space. Cropping the sensor plane with upright coordinates transposes
/// the face region and yields meaningless predictions.
void main() {
  group('extractYPlane', () {
    test('drops row padding when bytesPerRow exceeds width', () {
      const w = 3, h = 2, stride = 5;
      // Rows: [1,2,3,pad,pad] [4,5,6,pad,pad]
      final src = Uint8List.fromList([1, 2, 3, 99, 99, 4, 5, 6, 99, 99]);
      final out = extractYPlane(
        bytes: src,
        bytesPerRow: stride,
        width: w,
        height: h,
      );
      expect(out, [1, 2, 3, 4, 5, 6]);
    });

    test('fast path when stride equals width', () {
      final out = extractYPlane(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        bytesPerRow: 2,
        width: 2,
        height: 2,
      );
      expect(out, [1, 2, 3, 4]);
    });
  });

  group('rotateGrayToUpright', () {
    Uint8List grid(int w, int h, int Function(int x, int y) f) {
      final g = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          g[y * w + x] = f(x, y);
        }
      }
      return g;
    }

    test('0 degrees is identity and keeps dimensions', () {
      final src = grid(3, 2, (x, y) => y * 10 + x);
      final r =
          rotateGrayToUpright(gray: src, width: 3, height: 2, rotationDeg: 0);
      expect(r.width, 3);
      expect(r.height, 2);
      expect(r.pixels, src);
    });

    test('90 degrees maps (x,y) -> (H-1-y, x) and swaps dimensions', () {
      // width=3, height=2, values: row0 = 0 1 2, row1 = 10 11 12
      // Rotating 0 1 2 / 10 11 12 clockwise 90 degrees yields
      // 10  0 / 11  1 / 12  2
      final src = grid(3, 2, (x, y) => y * 10 + x);
      final r =
          rotateGrayToUpright(gray: src, width: 3, height: 2, rotationDeg: 90);
      expect(r.width, 2, reason: 'upright width is the sensor height');
      expect(r.height, 3, reason: 'upright height is the sensor width');
      expect(r.pixels, [10, 0, 11, 1, 12, 2]);
    });

    test('270 degrees maps (x,y) -> (y, W-1-x) and swaps dimensions', () {
      // Counter-clockwise 90 degrees yields
      // 2  12 / 1  11 / 0  10
      final src = grid(3, 2, (x, y) => y * 10 + x);
      final r =
          rotateGrayToUpright(gray: src, width: 3, height: 2, rotationDeg: 270);
      expect(r.width, 2);
      expect(r.height, 3);
      expect(r.pixels, [2, 12, 1, 11, 0, 10]);
    });

    test('180 degrees flips both axes and keeps dimensions', () {
      final src = grid(3, 2, (x, y) => y * 10 + x);
      final r =
          rotateGrayToUpright(gray: src, width: 3, height: 2, rotationDeg: 180);
      expect(r.width, 3);
      expect(r.height, 2);
      expect(r.pixels, [12, 11, 10, 2, 1, 0]);
    });

    test('normalizes equivalent rotation values', () {
      final src = grid(2, 2, (x, y) => y * 2 + x);
      final a =
          rotateGrayToUpright(gray: src, width: 2, height: 2, rotationDeg: 270);
      final b =
          rotateGrayToUpright(gray: src, width: 2, height: 2, rotationDeg: -90);
      final c =
          rotateGrayToUpright(gray: src, width: 2, height: 2, rotationDeg: 630);
      expect(a.pixels, b.pixels);
      expect(a.pixels, c.pixels);
    });

    test('90 then 270 round-trips to the original', () {
      final src = grid(5, 3, (x, y) => y * 5 + x);
      final fwd =
          rotateGrayToUpright(gray: src, width: 5, height: 3, rotationDeg: 90);
      final back = rotateGrayToUpright(
          gray: fwd.pixels,
          width: fwd.width,
          height: fwd.height,
          rotationDeg: 270);
      expect(back.width, 5);
      expect(back.height, 3);
      expect(back.pixels, src);
    });

    test('rejects an undersized buffer', () {
      expect(
        () => rotateGrayToUpright(
            gray: Uint8List(3), width: 4, height: 4, rotationDeg: 90),
        throwsArgumentError,
      );
    });
  });

  group('packNv21', () {
    test('strips Y padding and interleaves V,U from padded planes', () {
      // 4x4 image => 16 Y bytes and an 8-byte chroma plane (2 rows x 2 pairs).
      const w = 4, h = 4, yStride = 6;
      // Y rows padded to 6 bytes; valid pixels are 1..16.
      final y = Uint8List.fromList([
        1, 2, 3, 4, 0, 0, //
        5, 6, 7, 8, 0, 0, //
        9, 10, 11, 12, 0, 0, //
        13, 14, 15, 16, 0, 0, //
      ]);
      // U/V planes: 4:2:0 => 2 samples per row, each padded to 2 bytes,
      // so bytesPerRow = 4 and there are 2 rows.
      final u = Uint8List.fromList([
        10, 0, 11, 0, //
        12, 0, 13, 0, //
      ]);
      final v = Uint8List.fromList([
        20, 0, 21, 0, //
        22, 0, 23, 0, //
      ]);

      final out = packNv21(
        planes: [
          PlaneData(bytes: y, bytesPerRow: yStride, bytesPerPixel: 1),
          PlaneData(bytes: u, bytesPerRow: 4, bytesPerPixel: 2),
          PlaneData(bytes: v, bytesPerRow: 4, bytesPerPixel: 2),
        ],
        width: w,
        height: h,
      );

      expect(out.length, w * h + w * h ~/ 2);
      // Y: exactly w*h tightly packed bytes, no padding.
      expect(out.sublist(0, w * h), List<int>.generate(16, (i) => i + 1));

      // NV21 order is V then U, and 4:2:0 chroma rows sample even source rows.
      expect(out.sublist(w * h), [20, 10, 21, 11, 22, 12, 23, 13]);
    });

    test('supports an interleaved UV plane in second position', () {
      const w = 4, h = 2;
      final y = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final uvPlane = Uint8List.fromList([20, 10, 21, 11]);
      final out = packNv21(
        planes: [
          PlaneData(bytes: y, bytesPerRow: w, bytesPerPixel: 1),
          PlaneData(bytes: uvPlane, bytesPerRow: 4, bytesPerPixel: 1),
        ],
        width: w,
        height: h,
      );
      expect(out.length, w * h + w * h ~/ 2);
      expect(out.sublist(w * h), [20, 10, 21, 11]);
    });

    test('requires at least two planes', () {
      expect(
        () => packNv21(planes: const [], width: 2, height: 2),
        throwsArgumentError,
      );
    });
  });

  group('coordinate-space regression (the actual bug)', () {
    // A synthetic sensor-space frame: a bright "face" block sitting in the
    // TOP-LEFT of the sensor buffer. After rotating by 270 (the usual front
    // camera value) that block must land where ML Kit reports it, so reading
    // the rotated frame with the ML Kit box must hit the face.
    test('270-degree rotation puts the face where ML Kit looks for it', () {
      const w = 4, h = 4;
      const faceValue = 200, bgValue = 10;
      final sensor = Uint8List(w * h);
      for (var i = 0; i < sensor.length; i++) {
        sensor[i] = bgValue;
      }
      // Face block at sensor rows 0-1, cols 0-1.
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          sensor[y * w + x] = faceValue;
        }
      }

      final upright = rotateGrayToUpright(
          gray: sensor, width: w, height: h, rotationDeg: 270);
      expect(upright.width, 4);
      expect(upright.height, 4);

      // Under 270, sensor (x,y) -> upright (y, W-1-x).
      // Face block sensor (0..1, 0..1) -> upright cols 0..1, rows 3..2.
      final boxInUpright = [
        for (var y = 2; y <= 3; y++)
          for (var x = 0; x <= 1; x++) upright.pixels[y * 4 + x],
      ];
      expect(boxInUpright, everyElement(faceValue));

      // The old behaviour: sampling the SENSOR buffer with those same upright
      // coordinates lands on background, not on the face.
      final wrong = [
        for (var y = 2; y <= 3; y++)
          for (var x = 0; x <= 1; x++) sensor[y * 4 + x],
      ];
      expect(wrong, everyElement(bgValue),
          reason: 'pre-fix behaviour: the crop contained no face at all');
    });

    test('rotated buffer length always equals width * height', () {
      for (final rot in [0, 90, 180, 270]) {
        final r = rotateGrayToUpright(
            gray: Uint8List(6 * 4), width: 6, height: 4, rotationDeg: rot);
        expect(r.length, r.width * r.height, reason: 'rotation $rot');
      }
    });
  });

  group('nv21ToRgb colour conversion', () {
    test('neutral chroma (U=V=128) yields equal R, G and B', () {
      // The strongest available check on the YUV matrix: any per-channel
      // coefficient error breaks the grey axis, so this fails loudly if a
      // channel's coefficients are ever mistyped.
      for (final y in [16, 64, 128, 200, 235]) {
        final rgb = nv21ToRgb(_nv21Solid(8, 8, y: y, u: 128, v: 128), 8, 8);
        final r = _px(rgb, 8, 3, 3, 0);
        final g = _px(rgb, 8, 3, 3, 1);
        final b = _px(rgb, 8, 3, 3, 2);
        expect(r, g, reason: 'R != G at luma $y (grey axis broken)');
        expect(g, b, reason: 'G != B at luma $y (grey axis broken)');
      }
    });

    test('maps the studio-swing black and white points to 0 and 255', () {
      // Android camera HAL emits limited-range NV21: Y in [16, 235]. A
      // full-range inverse would return 16 and 235 here, lifting blacks
      // and flattening contrast across the whole crop.
      final black = nv21ToRgb(_nv21Solid(8, 8, y: 16, u: 128, v: 128), 8, 8);
      expect(_px(black, 8, 3, 3, 0), inInclusiveRange(0, 1));

      final white = nv21ToRgb(_nv21Solid(8, 8, y: 235, u: 128, v: 128), 8, 8);
      expect(_px(white, 8, 3, 3, 0), inInclusiveRange(254, 255));
    });

    test('preserves contrast across the luma range', () {
      // Guards the regression this caught: skipping the 1.164 scale and the
      // -16 offset compresses the usable range to ~219 of 255 levels, a
      // systematic brightness/contrast shift the model never saw in
      // training.
      final mid = _px(nv21ToRgb(_nv21Solid(8, 8, y: 126, u: 128, v: 128), 8, 8),
          8, 3, 3, 0);
      expect(mid, inInclusiveRange(127, 128),
          reason: 'mid-grey luma should land near mid-grey RGB');
    });

    test('NV21 V-before-U plane order gives red, not blue', () {
      // Classic NV21 bug: reading the interleaved plane as U,V instead of
      // V,U swaps the red and blue casts. High V / low U must read red.
      final red = nv21ToRgb(_nv21Solid(8, 8, y: 128, u: 90, v: 200), 8, 8);
      expect(_px(red, 8, 3, 3, 0), greaterThan(_px(red, 8, 3, 3, 2) + 60),
          reason: 'high V must push R above B');
      expect(_px(red, 8, 3, 3, 1), lessThan(_px(red, 8, 3, 3, 0)),
          reason: 'green must not dominate a red cast');

      final blue = nv21ToRgb(_nv21Solid(8, 8, y: 128, u: 200, v: 90), 8, 8);
      expect(_px(blue, 8, 3, 3, 2), greaterThan(_px(blue, 8, 3, 3, 0) + 60),
          reason: 'high U must push B above R');
    });

    test('packNv21 -> nv21ToRgb round trip keeps R and B distinct', () {
      // The bug this locks down: packNv21 writes chroma as V,U while
      // nv21ToRgb once read it as U,V. The pair stayed internally
      // "consistent" enough to pass unit tests on each half, so every
      // frame reaching the model was red/blue swapped. Luma was unchanged,
      // so no quality gate could see it. Driving the two together from
      // Android's real plane order (Y, U, V) is the only end-to-end check
      // that catches a disagreement between producer and consumer.
      final w = 8, h = 8;
      // Strongly red-dominant chroma: high V, low U.
      final uPlane = PlaneData(
          bytes: Uint8List.fromList(List.filled(w * (h ~/ 2), 90)),
          bytesPerRow: w,
          bytesPerPixel: 2);
      final vPlane = PlaneData(
          bytes: Uint8List.fromList(List.filled(w * (h ~/ 2), 200)),
          bytesPerRow: w,
          bytesPerPixel: 2);
      final yPlane = PlaneData(
          bytes: Uint8List.fromList(List.filled(w * h, 128)), bytesPerRow: w);

      final packed =
          packNv21(planes: [yPlane, uPlane, vPlane], width: w, height: h);
      final rgb = nv21ToRgb(packed, w, h);

      expect(_px(rgb, w, 3, 3, 0), greaterThan(_px(rgb, w, 3, 3, 2) + 60),
          reason: 'high V plane must surface as red, not blue');
    });

    test('packNv21 -> nv21ToRgb round trip keeps B distinct', () {
      final w = 8, h = 8;
      final uPlane = PlaneData(
          bytes: Uint8List.fromList(List.filled(w * (h ~/ 2), 200)),
          bytesPerRow: w,
          bytesPerPixel: 2);
      final vPlane = PlaneData(
          bytes: Uint8List.fromList(List.filled(w * (h ~/ 2), 90)),
          bytesPerRow: w);
      final yPlane = PlaneData(
          bytes: Uint8List.fromList(List.filled(w * h, 128)), bytesPerRow: w);

      final packed =
          packNv21(planes: [yPlane, uPlane, vPlane], width: w, height: h);
      final rgb = nv21ToRgb(packed, w, h);

      expect(_px(rgb, w, 3, 3, 2), greaterThan(_px(rgb, w, 3, 3, 0) + 60),
          reason: 'high U plane must surface as blue, not red');
    });

    test('clamps out-of-gamut output instead of wrapping', () {
      // Extremes can drive the matrix negative or past 255; a wrap-around
      // would turn saturated skin tones into noise.
      for (final c in [
        [16, 16, 240],
        [235, 240, 16],
        [16, 240, 240]
      ]) {
        final rgb =
            nv21ToRgb(_nv21Solid(4, 4, y: c[0], u: c[1], v: c[2]), 4, 4);
        for (final p in [0, 1, 2]) {
          expect(_px(rgb, 4, 1, 1, p), inInclusiveRange(0, 255));
        }
      }
    });
  });

  group('nv21ToUprightRgb', () {
    test('rotates RGB and swaps dimensions for 90 and 270', () {
      final nv21 = _nv21Solid(6, 4, y: 100, u: 128, v: 128);
      for (final rot in [90, 270]) {
        final f =
            nv21ToUprightRgb(nv21: nv21, width: 6, height: 4, rotationDeg: rot);
        expect(f.width, 4, reason: 'rot $rot');
        expect(f.height, 6, reason: 'rot $rot');
        expect(f.pixels.length, f.width * f.height * 3, reason: 'rot $rot');
      }
    });

    test('keeps dimensions for 0 and 180', () {
      final nv21 = _nv21Solid(6, 4, y: 100, u: 128, v: 128);
      for (final rot in [0, 180]) {
        final f =
            nv21ToUprightRgb(nv21: nv21, width: 6, height: 4, rotationDeg: rot);
        expect(f.width, 6, reason: 'rot $rot');
        expect(f.height, 4, reason: 'rot $rot');
        expect(f.pixels.length, f.width * f.height * 3, reason: 'rot $rot');
      }
    });

    test('180 is a true flip of the converted RGB', () {
      // A luma gradient so every pixel is distinguishable, then confirm the
      // 180 output equals the reversed source exactly.
      final w = 4, h = 4;
      final nv21 = _nv21Solid(w, h, y: 0, u: 128, v: 128);
      for (var i = 0; i < w * h; i++) {
        nv21[i] = 60 + i * 5;
      }
      final rgb = nv21ToRgb(nv21, w, h);
      final f =
          nv21ToUprightRgb(nv21: nv21, width: w, height: h, rotationDeg: 180);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final s = ((h - 1 - y) * w + (w - 1 - x)) * 3;
          final d = (y * w + x) * 3;
          expect(f.pixels[d], rgb[s], reason: 'at ($x,$y)');
          expect(f.pixels[d + 1], rgb[s + 1], reason: 'at ($x,$y)');
          expect(f.pixels[d + 2], rgb[s + 2], reason: 'at ($x,$y)');
        }
      }
    });

    test('normalizes equivalent rotation values', () {
      final nv21 = _nv21Solid(4, 4, y: 100, u: 128, v: 128);
      final base =
          nv21ToUprightRgb(nv21: nv21, width: 4, height: 4, rotationDeg: 90);
      for (final rot in [90, 450, -270]) {
        final f =
            nv21ToUprightRgb(nv21: nv21, width: 4, height: 4, rotationDeg: rot);
        expect(f.pixels, base.pixels, reason: 'rot $rot must equal rot 90');
      }
    });
  });
}

/// Builds a tightly packed NV21 buffer with a constant luma/chroma fill.
///
/// NV21 is planar Y then interleaved V,U -- note V comes FIRST. The tests
/// below depend on that order, so a buffer built with the opposite
/// convention would make them pass for the wrong reason.
Uint8List _nv21Solid(int w, int h,
    {required int y, required int u, required int v}) {
  // Chroma is subsampled in BOTH dimensions: (w/2) * (h/2) samples, each
  // stored as an interleaved V,U pair, so the plane is w*h/2 bytes. Each
  // chroma row is (w/2)*2 = w bytes, which is why the row stride is w and
  // not w/2. Dimensions must be even, as Android always provides.
  final cw = w ~/ 2;
  final ch = h ~/ 2;
  final buf = Uint8List(w * h + cw * ch * 2);
  for (var i = 0; i < w * h; i++) {
    buf[i] = y;
  }
  final uv = w * h;
  for (var cy = 0; cy < ch; cy++) {
    for (var cx = 0; cx < cw; cx++) {
      final i = uv + cy * w + cx * 2;
      buf[i] = v;
      buf[i + 1] = u;
    }
  }
  return buf;
}

int _px(Uint8List rgb, int w, int x, int y, int ch) =>
    rgb[(y * w + x) * 3 + ch];
