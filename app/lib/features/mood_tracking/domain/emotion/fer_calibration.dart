import 'dart:math' as math;

import 'fer_manifest.dart';

/// Confidence calibration + uncertainty decision.
///
/// Raw softmax is NOT trusted as confidence. The deployed transform is
/// power-normalization with the fitted temperature T:
///   p_cal[i] = p[i]^(1/T) / Σ p[j]^(1/T)
/// which is exactly softmax(logits/T) computed from probabilities.
/// UNKNOWN (never a forced label) when: calibrated top-1 < minConfidence,
/// top-1/top-2 margin < minMargin.
class FerCalibration {
  const FerCalibration(this.manifest);
  final FerManifest manifest;

  List<double> applyTemperature(List<double> probs) {
    final t = manifest.temperature;
    if ((t - 1.0).abs() < 1e-9) return probs;
    final inv = 1.0 / t;
    final pw = probs.map((p) => math.pow(math.max(p, 1e-12), inv).toDouble());
    final s = pw.fold(0.0, (a, b) => a + b);
    return pw.map((v) => v / s).toList();
  }

  FerDecision decide(List<double> calibrated) {
    var top = 0;
    for (var i = 1; i < calibrated.length; i++) {
      if (calibrated[i] > calibrated[top]) top = i;
    }
    var second = 0.0;
    for (var i = 0; i < calibrated.length; i++) {
      if (i != top && calibrated[i] > second) second = calibrated[i];
    }
    final margin = calibrated[top] - second;
    final confident = calibrated[top] >= manifest.minimumConfidence &&
        margin >= manifest.minimumMargin;
    return FerDecision(
      topIndex: top,
      confidence: calibrated[top],
      margin: margin,
      certain: confident,
    );
  }
}

class FerDecision {
  const FerDecision({
    required this.topIndex,
    required this.confidence,
    required this.margin,
    required this.certain,
  });
  final int topIndex;
  final double confidence;
  final double margin;
  final bool certain;
}
