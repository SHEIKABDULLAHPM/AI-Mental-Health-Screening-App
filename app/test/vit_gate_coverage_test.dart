import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mindease/features/mood_tracking/domain/emotion/fer_calibration.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_manifest.dart';
import 'package:mindease/features/mood_tracking/domain/emotion/fer_temporal.dart';

/// Gate-coverage regression for the "only Happy/Neutral ever surface" bug.
///
/// That failure was not a model problem: the shipped gates were never
/// measured against the model's own confidence distribution, so the
/// confidence gate silently rejected most of the minority classes and they
/// could essentially never reach PREDICTED.
///
/// This replays the real 175-image validation probabilities through the real
/// calibration and temporal fusion, and asserts that every class can surface
/// and that the gates still reject genuinely ambiguous input. It also pins the
/// thresholds, so "make the number go up" cannot be a way to pass.
void main() {
  const dirPath = 'test/fer_vit_golden';

  late FerManifest manifest;
  late List<String> classes;
  late List<List<double>> probs;
  late List<int> truth;

  setUpAll(() {
    manifest = FerManifest.parse(jsonDecode(
            File('assets/models/vit_fer_manifest.json').readAsStringSync())
        as Map<String, dynamic>);
    final ref = jsonDecode(File('$dirPath/reference.json').readAsStringSync())
        as Map<String, dynamic>;
    classes = (ref['classes'] as List).cast<String>();
    final v = ref['validation'] as Map<String, dynamic>;
    probs = (v['probs'] as List)
        .map((r) => (r as List).map((e) => (e as num).toDouble()).toList())
        .toList();
    truth = (v['true'] as List).map((e) => (e as num).toInt()).toList();
  });

  /// Hold one frame's distribution steady across a full temporal window, the
  /// way a user does when they keep the same expression for a moment.
  FerTemporalState settle(List<double> p, {double quality = 0.9}) {
    final f = FerTemporalFusion(manifest);
    late FerTemporalState s;
    for (var k = 0; k < manifest.temporalWindow; k++) {
      s = f.addFrame(p, quality);
    }
    return s;
  }

  group('thresholds are not lowered to manufacture output', () {
    test('minimumConfidence is 0.60', () {
      expect(manifest.minimumConfidence, 0.60);
    });

    test('minimumMargin is 0.10', () {
      expect(manifest.minimumMargin, 0.10);
    });

    test('temperature is the honest fitted value, not a legacy carry-over', () {
      // 0.8278 was fitted for the retired model and measured WORSE here.
      expect(manifest.temperature, 1.0);
      expect(manifest.temperature, isNot(0.8278571963310242));
    });
  });

  group('gate coverage: every class can actually surface', () {
    test('the validation set is the full measured set', () {
      expect(classes, hasLength(7));
      expect(probs, hasLength(175));
      expect(truth, hasLength(175));
    });

    test('holding a true class steady yields PREDICTED for that class', () {
      // For each class, take frames the model actually got right and hold the
      // best one steady. Each class must reach PREDICTED on its own data.
      final cal = FerCalibration(manifest);
      final reach = <String, bool>{for (final c in classes) c: false};

      for (var i = 0; i < probs.length; i++) {
        final p = probs[i];
        if (_argmax(p) != truth[i]) continue; // only genuine predictions
        final d = cal.decide(cal.applyTemperature(p));
        if (!d.certain) continue; // model itself was not sure enough
        final s = settle(p);
        final state = cal.decide(s.ema);
        if (state.certain && s.stable) {
          reach[classes[truth[i]]] = true;
        }
      }

      // ignore: avoid_print
      print('per-class PREDICTED reachability: $reach');
      for (final c in classes) {
        expect(reach[c], isTrue,
            reason: '$c can never reach PREDICTED — gate coverage regression');
      }
    });

    test('overall emission rate stays conservative (not gate-removed)', () {
      final cal = FerCalibration(manifest);
      var emitted = 0;
      for (final p in probs) {
        final d = cal.decide(cal.applyTemperature(p));
        if (d.certain) emitted++;
      }
      final rate = emitted / probs.length;
      // ignore: avoid_print
      print('single-frame emission rate: ${(rate * 100).toStringAsFixed(1)}%');
      // A gate that lets almost everything through is as much a bug as one
      // that lets nothing through.
      expect(rate, greaterThan(0.50),
          reason: 'gate rejects too much for a validated model');
      expect(rate, lessThan(0.98), reason: 'gate is effectively disabled');
    });

    test('gating on confidence does not reduce accuracy', () {
      final cal = FerCalibration(manifest);

      var rawCorrect = 0;
      var gatedCorrect = 0;
      var gatedTotal = 0;
      for (var i = 0; i < probs.length; i++) {
        final hit = _argmax(probs[i]) == truth[i];
        if (hit) rawCorrect++;
        if (cal.decide(cal.applyTemperature(probs[i])).certain) {
          gatedTotal++;
          if (hit) gatedCorrect++;
        }
      }
      // ignore: avoid_print
      print('raw argmax accuracy: $rawCorrect/${probs.length}, '
          'gated accuracy: $gatedCorrect/$gatedTotal');

      // A confidence gate exists to raise precision. If it emits a set that
      // is *less* accurate than the ungated stream, the gate is doing harm.
      expect(gatedTotal, greaterThan(0));
      expect(gatedCorrect / gatedTotal,
          greaterThanOrEqualTo(rawCorrect / probs.length));
    });

    test('genuinely ambiguous input stays UNCERTAIN', () {
      final cal = FerCalibration(manifest);
      // Near-uniform: no class is meaningfully ahead of any other.
      final flat = List<double>.filled(7, 1 / 7);
      final d = cal.decide(cal.applyTemperature(flat));
      expect(d.certain, isFalse);
      final s = settle(flat);
      expect(s.stable && cal.decide(s.ema).certain, isFalse);
    });

    test('a confident minority class is NOT suppressed', () {
      // The original failure mode: a decisive 'surprise' distribution being
      // rejected while weaker happy/neutral frames passed.
      final cal = FerCalibration(manifest);
      final surpriseIdx = classes.indexOf('surprise');
      final decisive = List<double>.filled(7, 0.02);
      decisive[surpriseIdx] = 1 - 0.02 * 6;
      final d = cal.decide(cal.applyTemperature(decisive));
      expect(d.topIndex, surpriseIdx);
      expect(d.certain, isTrue,
          reason: 'a decisive minority class must pass the gate');
    });
  });
}

int _argmax(List<double> v) {
  var best = 0;
  for (var i = 1; i < v.length; i++) {
    if (v[i] > v[best]) best = i;
  }
  return best;
}
