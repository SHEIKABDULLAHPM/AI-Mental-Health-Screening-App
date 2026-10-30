/// Versioned model manifest for the seven-class ViT emotion model.
///
/// The manifest is the single source of truth for the model contract.
/// It is validated at startup and the model checksum is verified before
/// the interpreter is created. A manifest/model mismatch is a hard error,
/// never a silent fallback.
class FerManifest {
  const FerManifest({
    required this.modelId,
    required this.version,
    required this.architecture,
    required this.inputWidth,
    required this.inputHeight,
    required this.channels,
    required this.colorSpace,
    required this.normalization,
    required this.tensorLayout,
    required this.classes,
    required this.classmapVersion,
    required this.productionArtifact,
    required this.precision,
    required this.quantization,
    required this.checksum,
    required this.temperature,
    required this.minimumConfidence,
    required this.minimumMargin,
    required this.minFaceSizeRatio,
    required this.maxYawDeg,
    required this.maxPitchDeg,
    required this.minBrightness,
    required this.maxBrightness,
    required this.minContrast,
    required this.minSharpness,
    required this.temporalWindow,
    required this.minStableFrames,
    required this.minAgreement,
    required this.emaAlpha,
    required this.preprocessingVersion,
  });

  final String modelId;
  final String version;
  final String architecture;
  final int inputWidth;
  final int inputHeight;
  final int channels;
  final String colorSpace;
  final String normalization;
  final String tensorLayout;
  final List<String> classes;
  final String classmapVersion;
  final String productionArtifact;
  final String precision;
  final bool quantization;
  final String checksum;
  final double temperature;
  final double minimumConfidence;
  final double minimumMargin;
  final double minFaceSizeRatio;
  final double maxYawDeg;
  final double maxPitchDeg;
  final double minBrightness;
  final double maxBrightness;
  final double minContrast;
  final double minSharpness;
  final int temporalWindow;
  final int minStableFrames;
  final double minAgreement;
  final double emaAlpha;
  final String preprocessingVersion;

  int get inputSize => inputWidth; // square inputs only (validated)

  static Map<String, dynamic> _section(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v == null) return {};
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    throw FerManifestError('section "$key" must be an object');
  }

  static double _d(Map<String, dynamic> m, String key, double fallback) =>
      (m[key] as num?)?.toDouble() ?? fallback;
  static int _i(Map<String, dynamic> m, String key, int fallback) =>
      (m[key] as num?)?.toInt() ?? fallback;

  /// Parse + validate. Throws [FerManifestError] on any contract violation.
  factory FerManifest.parse(Map<String, dynamic> json) {
    String s(String k) {
      final v = json[k];
      if (v is! String || v.isEmpty) {
        throw FerManifestError('missing/invalid "$k"');
      }
      return v;
    }

    final classes = json['classes'];
    if (classes is! List ||
        classes.length != 7 ||
        classes.any((c) => c is! String)) {
      throw FerManifestError('manifest must define exactly 7 classes');
    }
    // Order is the model's id2label order and is load-bearing: the output
    // tensor index of the network IS this list position.
    const expected = [
      'anger',
      'disgust',
      'fear',
      'happy',
      'neutral',
      'sad',
      'surprise',
    ];
    for (var i = 0; i < 7; i++) {
      if (classes[i] != expected[i]) {
        throw FerManifestError(
            'class[$i] "${classes[i]}" != canonical "${expected[i]}"',);
      }
    }

    final w = _i(json, 'inputWidth', 0);
    final h = _i(json, 'inputHeight', 0);
    final ch = _i(json, 'channels', 0);
    // Production contract: square RGB NCHW inputs. 224x224x3 is the shipped
    // ViT artifact; smaller sizes (96/112/128/160/192) are allowed ONLY for
    // lightweight mobile FER artifacts (MobileNetV3/EfficientNet-Lite class)
    // that were TRAINED and EXPORTED for that resolution — never by resizing
    // or reinterpreting the 224 model. Anything else (48/64 legacy, non-3ch,
    // non-square) is still a hard error.
    const allowedSizes = {96, 112, 128, 160, 192, 224};
    if (w != h || ch != 3 || !allowedSizes.contains(w)) {
      throw FerManifestError(
          'unsupported input ${w}x${h}x$ch (contract is square RGB, '
          'size in $allowedSizes)',);
    }
    if (json['colorSpace'] != 'RGB' ||
        json['normalization'] != 'MEAN_STD_0.5' ||
        json['tensorLayout'] != 'NCHW') {
      throw FerManifestError('unsupported pixel contract');
    }

    final cal = _section(json, 'calibration');
    final qg = _section(json, 'qualityGate');
    final tf = _section(json, 'temporal');

    return FerManifest(
      modelId: s('modelId'),
      version: s('version'),
      architecture: s('architecture'),
      inputWidth: w,
      inputHeight: h,
      channels: ch,
      colorSpace: 'RGB',
      normalization: 'MEAN_STD_0.5',
      tensorLayout: 'NCHW',
      classes: List<String>.from(classes),
      classmapVersion: s('classmapVersion'),
      productionArtifact: s('productionArtifact'),
      precision: s('precision'),
      quantization: json['quantization'] == true,
      checksum: s('checksum'),
      temperature: _d(cal, 'temperature', 1.0),
      minimumConfidence: _d(json, 'minimumConfidence', 0.60),
      minimumMargin: _d(json, 'minimumMargin', 0.10),
      minFaceSizeRatio: _d(qg, 'minFaceSizeRatio', 0.02),
      maxYawDeg: _d(qg, 'maxYawDeg', 25.0),
      maxPitchDeg: _d(qg, 'maxPitchDeg', 20.0),
      minBrightness: _d(qg, 'minBrightness', 30.0),
      maxBrightness: _d(qg, 'maxBrightness', 225.0),
      minContrast: _d(qg, 'minContrast', 18.0),
      minSharpness: _d(qg, 'minSharpness', 12.0),
      temporalWindow: _i(tf, 'windowSize', 8),
      minStableFrames: _i(tf, 'minStableFrames', 4),
      minAgreement: _d(tf, 'minAgreement', 0.75),
      emaAlpha: _d(tf, 'emaAlpha', 0.5),
      preprocessingVersion: s('preprocessingVersion'),
    );
  }
}

class FerManifestError extends Error {
  FerManifestError(this.message);
  final String message;
  @override
  String toString() => 'FerManifestError: $message';
}
