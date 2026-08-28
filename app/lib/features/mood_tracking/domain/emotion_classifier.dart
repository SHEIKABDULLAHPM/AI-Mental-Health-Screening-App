import 'dart:math';
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// On-device emotion classifier using a TFLite model (FER2013-trained,
/// 48x48 grayscale input → 7 emotion classes).
///
/// Falls back to MLKit smile/eye heuristics if model unavailable.
/// Returns EmotionResult with emotion="unknown" when confidence is low.
class EmotionClassifier {
  Interpreter? _interpreter;
  bool _modelLoaded = false;
  bool _isQuantized = false;

  static const int inputSize = 48;
  static const int numClasses = 7;

  /// Confidence threshold — below this, emotion is "unknown".
  static const double confidenceThreshold = 0.35;

  static const List<String> labels = [
    'Angry',
    'Disgust',
    'Fear',
    'Happy',
    'Sad',
    'Surprise',
    'Neutral',
  ];

  static const Map<String, String> _labelMap = {
    'Angry': 'angry',
    'Disgust': 'disgust',
    'Fear': 'fear',
    'Happy': 'happy',
    'Sad': 'sad',
    'Surprise': 'surprised',
    'Neutral': 'neutral',
  };

  bool get isReady => _modelLoaded;

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/emotion_model.tflite',
        options: options,
      );
      _modelLoaded = true;

      final inputTensor = _interpreter!.getInputTensor(0);
      _isQuantized = inputTensor.type == TensorType.int8 ||
          inputTensor.type == TensorType.uint8;
    } catch (e) {
      _modelLoaded = false;
      _interpreter = null;
    }
  }

  /// Classify emotion from a face detected in an RGB image buffer.
  EmotionResult classify({
    required Uint8List rgbBytes,
    required int frameWidth,
    required int frameHeight,
    required Face face,
  }) {
    if (!_modelLoaded || _interpreter == null) {
      return _heuristicFallback(face);
    }

    try {
      final box = face.boundingBox;

      // Add 20% padding around the face for better feature capture
      final padX = (box.width * 0.2).toInt();
      final padY = (box.height * 0.2).toInt();
      final x = max(0, box.left.toInt() - padX);
      final y = max(0, box.top.toInt() - padY);
      final w = min(box.width.toInt() + padX * 2, frameWidth - x);
      final h = min(box.height.toInt() + padY * 2, frameHeight - y);
      if (w <= 0 || h <= 0) return _heuristicFallback(face);

      // Crop face from RGB buffer
      final faceRgb = _cropRgb(rgbBytes, frameWidth, x, y, w, h);

      // Resize to 48x48 and convert to grayscale
      final input = _preprocess(faceRgb, w, h);

      // Run inference with appropriate output buffer
      List<double> rawScores;
      if (_isQuantized) {
        final output = List.filled(1 * numClasses, 0).reshape([1, numClasses]);
        _interpreter!.run(input, output);
        final intScores =
            (output[0] as List<int>).map((v) => v.toDouble()).toList();
        rawScores = _softmax(intScores);
      } else {
        final output =
            List.filled(1 * numClasses, 0.0).reshape([1, numClasses]);
        _interpreter!.run(input, output);
        rawScores = (output[0] as List<double>);
      }

      // Parse results
      final scores = <String, double>{};
      for (var i = 0; i < numClasses; i++) {
        scores[_labelMap[labels[i]]!] = rawScores[i];
      }

      // Dominant emotion
      String dominant = 'neutral';
      double best = -1;
      scores.forEach((emotion, score) {
        if (score > best) {
          best = score;
          dominant = emotion;
        }
      });

      // Confidence = gap between top-1 and top-2 (stronger signal)
      final sorted = scores.values.toList()..sort((a, b) => b.compareTo(a));
      final gapConfidence = sorted.length >= 2
          ? (sorted[0] - sorted[1]).clamp(0.0, 1.0)
          : sorted.first.clamp(0.0, 1.0);

      // Combined confidence: top-1 score × gap signal
      // If top score is high but gap is tiny, confidence is moderate
      final combinedConfidence = (sorted[0] * 0.6 + gapConfidence * 0.4)
          .clamp(0.0, 1.0);

      final faceQuality = _faceQuality(face, frameWidth, frameHeight);

      // Apply confidence threshold
      final emotion = combinedConfidence >= confidenceThreshold
          ? dominant
          : 'unknown';

      return EmotionResult(
        emotion: emotion,
        confidence: combinedConfidence,
        faceQuality: faceQuality,
        scores: scores,
        valence: _computeValence(scores),
        arousal: _computeArousal(scores),
      );
    } catch (_) {
      return _heuristicFallback(face);
    }
  }

  /// NV21 camera frame → RGB bytes.
  static Uint8List nv21ToRgb(Uint8List nv21, int width, int height) {
    final rgb = Uint8List(width * height * 3);
    final ySize = width * height;
    var pixelIndex = 0;

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final yi = row * width + col;
        if (yi >= nv21.length) break;

        var y = nv21[yi];
        if (y < 0) y = 0;
        if (y > 255) y = 255;

        // UV plane in NV21: VU pairs, stride = width (each row of UV
        // covers 2 rows of Y). UV byte index = ySize + (row/2)*width + (col & ~1)
        final uvRow = row ~/ 2;
        final uvCol = col & ~1; // align to even column
        final uvIndex = ySize + uvRow * width + uvCol;

        if (uvIndex + 1 >= nv21.length) {
          rgb[pixelIndex++] = y;
          rgb[pixelIndex++] = y;
          rgb[pixelIndex++] = y;
          continue;
        }

        // NV21: byte[uvIndex] = V, byte[uvIndex+1] = U
        final v = nv21[uvIndex];
        final u = nv21[uvIndex + 1];

        // BT.601 YUV → RGB
        var r = (y + 1.402 * (v - 128)).round();
        var g = (y - 0.344136 * (u - 128) - 0.714136 * (v - 128)).round();
        var b = (y + 1.772 * (u - 128)).round();
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        rgb[pixelIndex++] = r;
        rgb[pixelIndex++] = g;
        rgb[pixelIndex++] = b;
      }
    }
    return rgb;
  }

  /// Crop face region from RGB buffer.
  Uint8List _cropRgb(
    Uint8List rgb,
    int frameWidth,
    int x,
    int y,
    int w,
    int h,
  ) {
    final faceRgb = Uint8List(w * h * 3);
    for (var row = 0; row < h; row++) {
      final srcOffset = ((y + row) * frameWidth + x) * 3;
      final dstOffset = row * w * 3;
      final copyLen = w * 3;
      if (srcOffset + copyLen <= rgb.length &&
          dstOffset + copyLen <= faceRgb.length) {
        faceRgb.setRange(dstOffset, dstOffset + copyLen, rgb, srcOffset);
      }
    }
    return faceRgb;
  }

  /// Preprocess cropped face RGB → 48x48 grayscale tensor [1,48,48,1].
  List<dynamic> _preprocess(Uint8List faceRgb, int srcW, int srcH) {
    if (_isQuantized) {
      final input = Uint8List(1 * inputSize * inputSize);
      for (var y = 0; y < inputSize; y++) {
        for (var x = 0; x < inputSize; x++) {
          final srcX = (x * srcW / inputSize).toInt().clamp(0, srcW - 1);
          final srcY = (y * srcH / inputSize).toInt().clamp(0, srcH - 1);
          final idx = (srcY * srcW + srcX) * 3;
          if (idx + 2 < faceRgb.length) {
            final gray = (0.299 * faceRgb[idx] +
                    0.587 * faceRgb[idx + 1] +
                    0.114 * faceRgb[idx + 2])
                .round();
            input[y * inputSize + x] = gray.clamp(0, 255);
          }
        }
      }
      return input.reshape([1, inputSize, inputSize, 1]);
    } else {
      final input = Float32List(1 * inputSize * inputSize);
      for (var y = 0; y < inputSize; y++) {
        for (var x = 0; x < inputSize; x++) {
          final srcX = (x * srcW / inputSize).toInt().clamp(0, srcW - 1);
          final srcY = (y * srcH / inputSize).toInt().clamp(0, srcH - 1);
          final idx = (srcY * srcW + srcX) * 3;
          if (idx + 2 < faceRgb.length) {
            input[y * inputSize + x] = (0.299 * faceRgb[idx] +
                    0.587 * faceRgb[idx + 1] +
                    0.114 * faceRgb[idx + 2]) /
                255.0;
          }
        }
      }
      return input.reshape([1, inputSize, inputSize, 1]);
    }
  }

  /// Apply softmax to convert raw logits to probabilities.
  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(max);
    final exps = logits.map((l) => exp(l - maxLogit)).toList();
    final sumExps = exps.fold(0.0, (a, b) => a + b);
    return exps.map((e) => e / sumExps).toList();
  }

  double _computeValence(Map<String, double> s) {
    return (s['happy']! * 1.0 +
            s['surprised']! * 0.3 -
            s['sad']! * 0.8 -
            s['angry']! * 0.9 -
            s['fear']! * 0.7 -
            s['disgust']! * 0.6)
        .clamp(-1.0, 1.0);
  }

  double _computeArousal(Map<String, double> s) {
    return (s['angry']! * 0.8 +
            s['surprised']! * 0.9 +
            s['fear']! * 0.7 +
            s['happy']! * 0.3 -
            s['neutral']! * 0.3 -
            s['sad']! * 0.4)
        .clamp(-1.0, 1.0);
  }

  double _faceQuality(Face face, int frameW, int frameH) {
    final area =
        face.boundingBox.width * face.boundingBox.height / (frameW * frameH);
    // Penalize very small or very large face detections
    final sizeScore = min(1.0, area * 10).clamp(0.3, 1.0);
    // Bonus for centered face
    final centerX = face.boundingBox.center.dx / frameW;
    final centerY = face.boundingBox.center.dy / frameH;
    final distFromCenter =
        sqrt(pow(centerX - 0.5, 2) + pow(centerY - 0.5, 2));
    final centerScore = (1.0 - distFromCenter).clamp(0.5, 1.0);
    return sizeScore * centerScore;
  }

  /// Heuristic fallback when TFLite model is not available.
  EmotionResult _heuristicFallback(Face face) {
    final smile = face.smilingProbability ?? 0.0;
    final leftEye = face.leftEyeOpenProbability ?? 0.5;
    final rightEye = face.rightEyeOpenProbability ?? 0.5;
    final eyeOpenness = (leftEye + rightEye) / 2.0;

    final scores = <String, double>{};
    scores['happy'] = smile;
    scores['surprised'] =
        eyeOpenness > 0.8 ? (eyeOpenness - 0.8) / 0.2 : 0.0;
    final moderateEyes =
        eyeOpenness >= 0.35 && eyeOpenness <= 0.75 ? 1.0 : 0.0;
    scores['neutral'] = (1.0 - smile) * moderateEyes * 0.85;
    final eyeDroop =
        eyeOpenness < 0.35 ? (0.35 - eyeOpenness) / 0.35 : 0.0;
    scores['sad'] = eyeDroop * (1.0 - smile) * 0.75;
    scores['angry'] = 0.0;
    scores['fear'] = 0.0;
    scores['disgust'] = 0.0;

    String dominant = 'neutral';
    double best = 0.0;
    scores.forEach((e, s) {
      if (s > best) {
        best = s;
        dominant = e;
      }
    });

    final total = scores.values.fold(0.0, (a, b) => a + b);
    final normalized = <String, double>{};
    scores.forEach((k, v) {
      normalized[k] = total > 0 ? v / total : (k == 'neutral' ? 1.0 : 0.0);
    });

    final sorted = scores.values.toList()..sort((a, b) => b.compareTo(a));
    final gapConfidence = sorted.length >= 2
        ? (sorted[0] - sorted[1]).clamp(0.0, 1.0)
        : sorted.first.clamp(0.0, 1.0);
    final combinedConfidence =
        (sorted[0] * 0.6 + gapConfidence * 0.4).clamp(0.0, 1.0);

    final emotion = combinedConfidence >= confidenceThreshold
        ? dominant
        : 'unknown';

    return EmotionResult(
      emotion: emotion,
      confidence: combinedConfidence,
      faceQuality: 0.5,
      scores: normalized,
      valence: _computeValence(normalized),
      arousal: _computeArousal(normalized),
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _modelLoaded = false;
  }
}

/// Result of on-device emotion classification.
class EmotionResult {
  const EmotionResult({
    required this.emotion,
    required this.confidence,
    required this.faceQuality,
    required this.scores,
    required this.valence,
    required this.arousal,
  });

  /// Emotion label, or "unknown" when confidence is below threshold.
  final String emotion;
  final double confidence;
  final double faceQuality;
  final Map<String, double> scores;
  final double valence;
  final double arousal;

  bool get isUnknown => emotion == 'unknown';
}
