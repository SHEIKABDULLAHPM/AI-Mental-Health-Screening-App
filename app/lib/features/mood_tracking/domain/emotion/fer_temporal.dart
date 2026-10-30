import 'fer_manifest.dart';

/// Temporal fusion: quality-weighted EMA over a sliding window + voted
/// stability gate. Suppresses frame-to-frame flicker without going stale:
/// the EMA adapts within ~1/alpha frames while the vote requires sustained
/// agreement before a PREDICTED state is emitted.
class FerTemporalFusion {
  FerTemporalFusion(this.manifest);
  final FerManifest manifest;

  final List<_Frame> _window = [];
  List<double>? _ema;
  int labelChanges = 0;
  int _lastVote = -1;

  void reset() {
    _window.clear();
    _ema = null;
    labelChanges = 0;
    _lastVote = -1;
  }

  /// Add one frame's calibrated probabilities; returns the fusion state.
  FerTemporalState addFrame(List<double> probs, double quality) {
    _window.add(_Frame(probs, quality));
    while (_window.length > manifest.temporalWindow) {
      _window.removeAt(0);
    }
    final a = manifest.emaAlpha;
    if (_ema == null) {
      _ema = List<double>.from(probs);
    } else {
      // Quality gates the update rate: poor frames barely move the EMA.
      final step = a * (0.25 + 0.75 * quality.clamp(0.0, 1.0));
      for (var i = 0; i < _ema!.length; i++) {
        _ema![i] = (1 - step) * _ema![i] + step * probs[i];
      }
    }

    var vote = 0;
    for (var i = 1; i < _ema!.length; i++) {
      if (_ema![i] > _ema![vote]) vote = i;
    }
    if (_lastVote >= 0 && vote != _lastVote) labelChanges++;
    _lastVote = vote;

    var agree = 0;
    for (final f in _window) {
      // Support, not unanimity: the fused winner must be among the frame's
      // top-2. A 51/49 alternation between two expressions keeps support at
      // 1.0 (the EMA already converged — no flicker is surfaced), while a
      // genuinely dissenting frame (e.g. one-hot for another class, whose
      // top-2 cannot contain the vote) withholds support exactly as before.
      // Chance level for top-2 support is 2/7, so the 0.75 bar stays strict.
      // Ties resolve to the lowest index, matching the argmax loops above.
      var first = 0, second = -1;
      for (var i = 1; i < f.probs.length; i++) {
        if (f.probs[i] > f.probs[first]) {
          second = first;
          first = i;
        } else if (second < 0 || f.probs[i] > f.probs[second]) {
          second = i;
        }
      }
      if (first == vote || second == vote) agree++;
    }
    final agreement = _window.isEmpty ? 0.0 : agree / _window.length;
    final stable = _window.length >= manifest.minStableFrames &&
        agreement >= manifest.minAgreement;

    return FerTemporalState(
      ema: List<double>.from(_ema!),
      vote: vote,
      agreement: agreement,
      frames: _window.length,
      stable: stable,
      flicker: labelChanges,
    );
  }
}

class _Frame {
  _Frame(this.probs, this.quality);
  final List<double> probs;
  final double quality;
}

class FerTemporalState {
  const FerTemporalState({
    required this.ema,
    required this.vote,
    required this.agreement,
    required this.frames,
    required this.stable,
    required this.flicker,
  });
  final List<double> ema;
  final int vote;
  final double agreement;
  final int frames;
  final bool stable;
  final int flicker;
}
