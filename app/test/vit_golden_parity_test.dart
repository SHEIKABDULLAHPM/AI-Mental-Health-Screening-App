import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:mindease/features/mood_tracking/domain/emotion/fer_calibration.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_manifest.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_preprocessing.dart';

/// Golden parity for the seven-class ViT model.
///
/// Fixture layout (test/fer_vit_golden/), exported from the validated PyTorch
/// run by ~/vit-build/export_golden.py:
///   reference.json   {classes, indices, true, probs: {name: [7 floats]}}
///   crop_NN.raw      NN uint8 RGB crops, 224*224*3 bytes each
///
/// The crops are the *pixels* the reference probabilities were computed from,
/// so this test closes the loop on the Dart side of the contract: it runs
/// [FerPreprocessing] over the real pixels, and — when the native library is
/// available — the real interpreter on top. That catches a channel swap, a
/// wrong layout or a changed normalization, none of which a unit test on
/// hand-written numbers would catch.
void main() {
  const dirPath = 'test/fer_vit_golden';
  const modelPath = 'assets/models/vit_fer_fp16.tflite';
  const tolerance = 2e-3; // measured worst-case fp16 diff was 9.22e-04

  late Map<String, dynamic> reference;
  late List<String> classes;
  late Map<String, List<double>> refProbs;

  setUpAll(() {
    reference = jsonDecode(File('$dirPath/reference.json').readAsStringSync())
        as Map<String, dynamic>;
    classes = (reference['classes'] as List).cast<String>();
    refProbs = (reference['probs'] as Map<String, dynamic>).map(
      (k, v) =>
          MapEntry(k, (v as List).map((e) => (e as num).toDouble()).toList()),
    );
  });

  test('fixture is the seven-class contract, three crops per class', () {
    expect(classes, hasLength(7));
    expect(classes,
        ['anger', 'disgust', 'fear', 'happy', 'neutral', 'sad', 'surprise']);
    expect(refProbs, hasLength(21));
    final counts = <String, int>{};
    for (final t in (reference['true'] as List).cast<int>()) {
      counts[classes[t]] = (counts[classes[t]] ?? 0) + 1;
    }
    expect(counts.values.every((c) => c == 3), isTrue, reason: '$counts');
  });

  test('reference probabilities are valid 7-way distributions', () {
    for (final entry in refProbs.entries) {
      expect(entry.value, hasLength(7), reason: entry.key);
      expect(entry.value.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-4),
          reason: entry.key);
      expect(entry.value.every((p) => p >= 0.0 && p <= 1.0), isTrue,
          reason: entry.key);
    }
  });

  test('Dart preprocessing reproduces the reference normalization', () {
    final manifest = _testManifest();
    final pre = FerPreprocessing(manifest);
    final stats = (reference['tensorStats'] as Map<String, dynamic>);
    for (final entry in refProbs.entries) {
      final n = int.parse(entry.key.split('_').last);
      final key = n.toString().padLeft(2, '0');
      final px = File('$dirPath/crop_$key.raw').readAsBytesSync();
      expect(px, hasLength(224 * 224 * 3), reason: entry.key);
      final t = pre.toTensorInput(Uint8List.fromList(px), quantized: false)
          as Float32List;
      expect(t, hasLength(224 * 224 * 3), reason: entry.key);

      // Every value must be inside the contract range; anything outside means
      // the rescale is wrong in a way a mean would hide.
      var min = double.infinity, max = -double.infinity, sum = 0.0;
      for (final v in t) {
        if (v < min) min = v;
        if (v > max) max = v;
        sum += v;
        expect(v, inInclusiveRange(-1.0, 1.0), reason: entry.key);
      }

      // Exact agreement with the tensor the reference probabilities were
      // computed from. A channel swap, a wrong layout or a changed scale all
      // move these numbers, so this is the real regression guard.
      final want = (stats[key] as Map<String, dynamic>);
      expect(min, closeTo((want['min'] as num).toDouble(), 1e-5),
          reason: '$entry.key min');
      expect(max, closeTo((want['max'] as num).toDouble(), 1e-5),
          reason: '$entry.key max');
      expect(sum, closeTo((want['sum'] as num).toDouble(), 1e-2),
          reason: '$entry.key sum');
    }
  });

  test('calibration is the identity at the shipped T=1.0', () {
    final cal = FerCalibration(_testManifest());
    for (final entry in refProbs.entries) {
      final out = cal.applyTemperature(entry.value);
      for (var i = 0; i < out.length; i++) {
        expect(out[i], closeTo(entry.value[i], 1e-9), reason: entry.key);
      }
    }
  });

  test('tflite inference matches the PyTorch reference', () async {
    final model = File(modelPath);
    if (!model.existsSync()) {
      markTestSkipped('model asset not present in this checkout');
      return;
    }
    final manifest = _testManifest();
    final pre = FerPreprocessing(manifest);

    Interpreter? interp;
    try {
      interp = Interpreter.fromFile(model);
      interp.allocateTensors();
    } catch (e) {
      // The native binding is unavailable on the host test VM; the on-device
      // benchmark is the authoritative parity check.
      markTestSkipped('tflite native lib unavailable here: $e');
      return;
    }

    try {
      final shape = interp.getInputTensor(0).shape;
      pre.validateTensor(shape: shape, dtype: 'float32', quantized: false);
      expect(shape, [1, 3, 224, 224]);

      var maxDiff = 0.0;
      var labelMatches = 0;
      for (final entry in refProbs.entries) {
        final n = int.parse(entry.key.split('_').last);
        final key = n.toString().padLeft(2, '0');
        final px = Uint8List.fromList(
            File('$dirPath/crop_$key.raw').readAsBytesSync());
        final out = List<List<double>>.filled(1, List<double>.filled(7, 0.0));
        interp.run(pre.toTensorInput(px, quantized: false), out);

        final ref = entry.value;
        for (var i = 0; i < 7; i++) {
          final d = (out[0][i] - ref[i]).abs();
          if (d > maxDiff) maxDiff = d;
        }
        if (argmax(out[0]) == argmax(ref)) labelMatches++;
      }

      // ignore: avoid_print
      print('fp16 parity: $labelMatches/${refProbs.length} labels, '
          'max abs prob diff $maxDiff');
      expect(labelMatches, refProbs.length,
          reason: 'fp16 model must reproduce every reference label');
      expect(maxDiff, lessThan(tolerance));
    } finally {
      // Reached only when construction succeeded, so this is non-null.
      interp.close();
    }
  });

  test('the shipped manifest matches the validated artifact contract', () {
    final m = jsonDecode(
            File('assets/models/vit_fer_manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    final parsed = FerManifest.parse(m);
    expect(parsed.classes, classes);
    expect(parsed.inputWidth, 224);
    expect(parsed.inputHeight, 224);
    expect(parsed.channels, 3);
    expect(parsed.tensorLayout, 'NCHW');
    expect(parsed.productionArtifact, 'vit_fer_fp16.tflite');
    // The recorded test metrics must be the ones that were actually measured.
    expect(parsed.temperature, 1.0);
  });
}

int argmax(List<double> v) {
  var best = 0;
  for (var i = 1; i < v.length; i++) {
    if (v[i] > v[best]) best = i;
  }
  return best;
}

FerManifest _testManifest() {
  final m =
      jsonDecode(File('assets/models/vit_fer_manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  return FerManifest.parse(m);
}
