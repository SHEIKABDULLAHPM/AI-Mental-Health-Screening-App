/// Structured result + status taxonomy for the on-device emotion model.
///
/// Statuses distinguish "no prediction possible" from "prediction made",
/// so the UI can coach the user instead of showing a forced emotion.
enum FerStatus {
  noFace('NO_FACE'),
  multipleFaces('MULTIPLE_FACES'),
  faceTooSmall('FACE_TOO_SMALL'),
  faceTooBlurry('FACE_TOO_BLURRY'),
  faceOccluded('FACE_OCCLUDED'),
  badLighting('BAD_LIGHTING'),
  badPose('BAD_POSE'),
  processing('PROCESSING'),
  ready('READY'),
  predicted('PREDICTED'),
  uncertain('UNCERTAIN');

  const FerStatus(this.wire);
  final String wire;

  bool get isTerminal => this == predicted || this == uncertain;
  bool get isQualityGate =>
      this == faceTooSmall ||
      this == faceTooBlurry ||
      this == faceOccluded ||
      this == badLighting ||
      this == badPose;
}

/// Canonical 7-class order. Must match FerManifest.classes exactly, and is
/// the network's id2label order, so index N here == output tensor index N.
const List<String> kFerClasses = [
  'anger',
  'disgust',
  'fear',
  'happy',
  'neutral',
  'sad',
  'surprise',
];

/// User-facing name for each canonical class.
///
/// Kept beside [kFerClasses] and asserted complete by the test suite: the
/// previous build carried an 8-class display map ('happiness', 'sadness',
/// 'contempt') that silently fell through to the raw model id once the model
/// changed, leaving users looking at a bare "happy" instead of "Happiness".
const Map<String, String> kFerDisplayNames = {
  'anger': 'Anger',
  'disgust': 'Disgust',
  'fear': 'Fear',
  'happy': 'Happiness',
  'neutral': 'Neutral',
  'sad': 'Sadness',
  'surprise': 'Surprise',
};

/// Display name for a canonical class, or the id itself if unmapped.
String ferDisplayName(String canonical) =>
    kFerDisplayNames[canonical] ?? canonical;

class FerResult {
  const FerResult({
    required this.emotion,
    required this.scores,
    required this.calibratedConfidence,
    required this.rawTopProbability,
    required this.margin,
    required this.faceQuality,
    required this.status,
    required this.modelId,
    required this.modelVersion,
    required this.preprocessingVersion,
    required this.valence,
    required this.arousal,
    required this.framesAnalyzed,
    this.delegate = 'cpu',
    this.latencyMs = 0,
    this.qualityDetails = const {},
    this.timings = const {},
  });

  /// Canonical emotion id, or 'unknown' when [status] is not [FerStatus.predicted].
  final String emotion;
  final Map<String, double> scores;
  final double calibratedConfidence;
  final double rawTopProbability;
  final double margin;
  final double faceQuality;
  final FerStatus status;
  final String modelId;
  final String modelVersion;
  final String preprocessingVersion;
  final double valence;
  final double arousal;
  final int framesAnalyzed;
  final String delegate;
  final int latencyMs;
  final Map<String, double> qualityDetails;

  /// Per-stage pipeline timings in milliseconds (profiling only).
  /// Keys: align, preprocess, inference, decode. Absent/empty when the frame
  /// never reached inference (quality-gated). Defaults to empty so existing
  /// call sites and tests are unaffected.
  final Map<String, int> timings;

  bool get isUnknown => emotion == 'unknown';

  /// Payload for FeatureApi.analyzeMood cameraObservation.
  ///
  /// Legacy keys are preserved byte-for-byte so existing backend parsing
  /// keeps working; versioned keys are additive (backend ignores unknown
  /// fields, and the new emotion-events endpoint validates them).
  Map<String, dynamic> toMap() => {
        'dominantEmotion': emotion,
        'emotionScores': scores,
        'faceDetected': status != FerStatus.noFace,
        'faceCount': 1,
        'faceQuality': faceQuality,
        'valence': valence,
        'arousal': arousal,
        'framesAnalyzed': framesAnalyzed,
        'status': status.wire,
        'calibratedConfidence': calibratedConfidence,
        'modelId': modelId,
        'modelVersion': modelVersion,
        'preprocessingVersion': preprocessingVersion,
        'delegate': delegate,
        'processingLatencyMs': latencyMs,
      };
}
