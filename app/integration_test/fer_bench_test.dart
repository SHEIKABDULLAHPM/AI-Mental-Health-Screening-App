/// On-device backend benchmark for the ViT FER model (SM-M325F and friends).
///
/// Run headless on a connected Android device (no human interaction needed):
///   flutter test integration_test/fer_bench_test.dart -d <device-id>
///
/// One test case per backend so no single case exceeds runner timeouts.
/// Measures load time + timed inference over a fixed synthetic NCHW input.
/// Prints FER_BENCH lines for collection. No UI/camera/feature code touched.
///
/// The 'preprocessing' and 'model-size' cases need no interpreter and run
/// first: they quantify the frame-conversion stage (full bilinear vs fast
/// vs ROI-only) and the artifact size for the before/after report.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/frame_geometry.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

const _modelAsset = 'assets/models/vit_fer_fp16.tflite';
const _inputLen = 1 * 3 * 224 * 224;
const _warmupRuns = 1;
const _timedRuns = 5;

/// Deterministic pseudo-random input in [-1,1] (fixed seed, no assets needed).
Float32List _syntheticInput() {
  final rng = math.Random(42);
  final data = Float32List(_inputLen);
  for (var i = 0; i < data.length; i++) {
    data[i] = rng.nextDouble() * 2.0 - 1.0;
  }
  return data;
}

Future<void> _bench(
    String name, InterpreterOptions Function() optsFn, Float32List input,) async {
  final swLoad = Stopwatch()..start();
  Interpreter? interp;
  try {
    interp = await Interpreter.fromAsset(_modelAsset, options: optsFn());
  } catch (e) {
    // ignore: avoid_print
    print('FER_BENCH backend=$name status=FAILED error=$e');
    return;
  }
  final loadMs = swLoad.elapsedMilliseconds;
  final inShape = interp.getInputTensor(0).shape;
  final outShape = interp.getOutputTensor(0).shape;

  final outBuf = Float32List(7);
  try {
    for (var i = 0; i < _warmupRuns; i++) {
      interp.run(input.buffer.asUint8List(), outBuf.buffer);
    }
    final samples = <int>[];
    for (var i = 0; i < _timedRuns; i++) {
      final sw = Stopwatch()..start();
      interp.run(input.buffer.asUint8List(), outBuf.buffer);
      samples.add(sw.elapsedMilliseconds);
    }
    samples.sort();
    final sum = samples.fold(0, (a, b) => a + b);
    // ignore: avoid_print
    print('FER_BENCH backend=$name status=OK loadMs=$loadMs '
        'inferAvgMs=${sum ~/ samples.length} inferMedianMs=${samples[samples.length ~/ 2]} '
        'inferMinMs=${samples.first} inferMaxMs=${samples.last} '
        'inShape=$inShape outShape=$outShape');
  } catch (e) {
    // ignore: avoid_print
    print('FER_BENCH backend=$name status=RUN_FAILED error=$e');
  } finally {
    interp.close();
  }
  // Small pause so thermal throttling does not skew the next backend.
  await Future<void>.delayed(const Duration(seconds: 3));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('fer preprocessing (no model needed)', () {
    testWidgets('frame-convert', (_) async {
      // 1280x720 sensor frame @ 90° (front-camera typical case).
      const w = 1280, h = 720, rot = 90;
      final nv21 = Uint8List(w * h + w * h ~/ 2);
      for (var i = 0; i < nv21.length; i++) {
        nv21[i] = i % 251;
      }
      int timeMs(void Function() fn) {
        fn();
        final samples = <int>[];
        for (var i = 0; i < 5; i++) {
          final sw = Stopwatch()..start();
          fn();
          samples.add(sw.elapsedMilliseconds);
        }
        samples.sort();
        return samples[samples.length ~/ 2];
      }

      final fullMs = timeMs(() {
        nv21ToUprightRgb(nv21: nv21, width: w, height: h, rotationDeg: rot);
      });
      final fastMs = timeMs(() {
        final flat = nv21ToRgbFast(nv21, w, h);
        rotateRgbToUpright(
            rgb: flat, width: w, height: h, rotationDeg: rot,);
      });
      final roiMs = timeMs(() {
        nv21RoiToUprightRgb(
          nv21: nv21,
          sensorW: w,
          sensorH: h,
          roiX0: 490,
          roiY0: 180,
          roiW: 300,
          roiH: 360,
          rotationDeg: rot,
        );
      });
      // ignore: avoid_print
      print('FER_BENCH stage=frameConvert frame=${w}x$h rot=$rot '
          'fullBilinearMs=$fullMs fullFastMs=$fastMs roiRgbMs=$roiMs');
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('model-size', (_) async {
      final blob = await rootBundle.load(_modelAsset);
      final mb = blob.lengthInBytes / (1024 * 1024);
      // ignore: avoid_print
      print('FER_BENCH stage=modelSize bytes=${blob.lengthInBytes} '
          'mb=${mb.toStringAsFixed(1)} asset=$_modelAsset');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('fer backends', () {
    late Float32List input;
    setUpAll(() => input = _syntheticInput());

    testWidgets('cpu-t2', (_) async {
      await _bench('cpu-t2', () => InterpreterOptions()..threads = 2, input);
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('cpu-t4', (_) async {
      await _bench('cpu-t4', () => InterpreterOptions()..threads = 4, input);
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('cpu-t8', (_) async {
      await _bench('cpu-t8', () => InterpreterOptions()..threads = 8, input);
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('nnapi-t4', (_) async {
      await _bench(
        'nnapi-t4',
        () => InterpreterOptions()
          ..threads = 4
          ..useNnApiForAndroid = true,
        input,
      );
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('gpu', (_) async {
      await _bench('gpu', () {
        final opts = InterpreterOptions()..threads = 2;
        opts.addDelegate(GpuDelegateV2());
        return opts;
      }, input);
      // ignore: avoid_print
      print('FER_BENCH done');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
