/// On-device per-emotion RAW-logit matrix for vit-fer-7 (SM-M325F).
///
/// Diagnostic only: runs 21 labeled 224x224x3 RGB crops (3 per each of the 7
/// emotions) through the REAL production interpreter on the REAL backend and
/// prints RAW logits + softmax per crop with NO smoothing, NO thresholds, NO
/// temporal fusion — the §8/§18 "raw behavior" requirement.
///
/// Run headless on a connected Android device:
///   flutter test integration_test/fer_matrix_test.dart -d <device-id>
/// Prints FER_MATRIX lines for collection.
///
/// Requires the TEMPORARY diagnostic assets assets/fer_golden/ (21 crops +
/// truth.json, ~3.1 MB, copied from test/fer_vit_golden/). If absent, the
/// test reports `stage=skipped` and passes — the production APK never ships
/// these files.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_classifier.dart'
    show decodeOutput;
import 'package:mindease/features/mood_tracking/domain/emotion/fer_manifest.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_preprocessing.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

const _modelAsset = 'assets/models/vit_fer_fp16.tflite';
const _manifestAsset = 'assets/models/vit_fer_manifest.json';
const _truthAsset = 'assets/fer_golden/truth.json';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('raw-logit matrix', (_) async {
    late Map<String, dynamic> truth;
    try {
      truth = jsonDecode(await rootBundle.loadString(_truthAsset))
          as Map<String, dynamic>;
    } catch (_) {
      // ignore: avoid_print
      print('FER_MATRIX stage=skipped reason=diagnostic_assets_absent');
      return;
    }
    final classes = List<String>.from(truth['classes'] as List);
    final labels = List<int>.from(truth['true'] as List);

    final manifest = FerManifest.parse(jsonDecode(
        await rootBundle.loadString(_manifestAsset)) as Map<String, dynamic>,);
    final pre = FerPreprocessing(manifest);

    final swLoad = Stopwatch()..start();
    final itp = await Interpreter.fromAsset(_modelAsset,
        options: InterpreterOptions()..threads = 4,);
    // ignore: avoid_print
    print('FER_MATRIX stage=loaded backend=cpu-t4 '
        'loadMs=${swLoad.elapsedMilliseconds} '
        'inShape=${itp.getInputTensor(0).shape} '
        'outShape=${itp.getOutputTensor(0).shape}');

    final perClassTop1 = List<int>.filled(7, 0);
    final perClassN = List<int>.filled(7, 0);
    var total = 0;
    var correct = 0;
    for (var i = 0; i < labels.length; i++) {
      final name = 'crop_${i.toString().padLeft(2, '0')}.raw';
      final rgb = (await rootBundle.load('assets/fer_golden/$name'))
          .buffer
          .asUint8List();
      final tensor =
          pre.toTensorInput(rgb, quantized: false) as Float32List;
      final outBuf = Float32List(classes.length);
      final sw = Stopwatch()..start();
      itp.run(tensor.buffer.asUint8List(), outBuf.buffer);
      final inferMs = sw.elapsedMilliseconds;
      final raw = List<double>.generate(classes.length, (k) => outBuf[k]);
      final probs = decodeOutput(raw);
      var top = 0;
      for (var k = 1; k < probs.length; k++) {
        if (probs[k] > probs[top]) top = k;
      }
      final isLogits =
          raw.any((v) => v < 0) || (raw.fold(0.0, (a, b) => a + b) - 1).abs() > 1e-3;
      perClassN[labels[i]]++;
      total++;
      if (top == labels[i]) {
        correct++;
        perClassTop1[labels[i]]++;
      }
      final rawStr = raw.map((v) => v.toStringAsFixed(3)).join(',');
      final probStr = probs.map((v) => v.toStringAsFixed(4)).join(',');
      final probSum = probs.fold(0.0, (a, b) => a + b);
      // ignore: avoid_print
      print('FER_MATRIX crop=$name true=${classes[labels[i]]} '
          'isLogits=$isLogits raw=[$rawStr] softmax=[$probStr] '
          'sum=${probSum.toStringAsFixed(4)} top=${classes[top]} '
          'conf=${probs[top].toStringAsFixed(4)} inferMs=$inferMs');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final recalls = <String>[];
    for (var c = 0; c < 7; c++) {
      recalls.add('${classes[c]}=${perClassN[c] == 0 ? 0 : perClassTop1[c] / perClassN[c]}');
    }
    // ignore: avoid_print
    print('FER_MATRIX stage=summary n=$total top1=$correct '
        'acc=${total == 0 ? 0 : correct / total} recalls=[${recalls.join(' ')}]');
    // ignore: avoid_print
    print('FER_MATRIX done');
    itp.close();
  }, timeout: const Timeout(Duration(minutes: 30)));
}
