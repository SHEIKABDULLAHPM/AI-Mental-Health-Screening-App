/// Canonical 7-class -> user-facing emotion tag mapping, v2.
///
/// Versioned and explicit: every canonical class has a documented target.
/// [kMoodEmotions] has no slot for disgust, so disgust shares the 'Irritated'
/// presentation slot; the canonical class is ALWAYS preserved in
/// emotionScores and the backend emotion event, and the tag is a
/// user-editable default — never a silent class drop.
///
/// v2 changes from v1: the model now emits `happy`/`sad` (it previously
/// emitted `happiness`/`sadness`) and has no `contempt` class at all.
const String kCameraEmotionMappingVersion = 'camera-emotion-map-v2';

const Map<String, String> kCanonicalToTag = {
  'happy': 'Hopeful',
  'sad': 'Sad',
  'neutral': 'Content',
  'surprise': 'Overwhelmed',
  'anger': 'Irritated',
  'fear': 'Anxious',
  'disgust': 'Irritated', // shared slot; canonical kept in scores/event
};

/// Map a canonical emotion id to a display tag. Returns null for
/// 'unknown' (no pre-fill) — the only null case, by design.
String? mapCanonicalToTag(String canonical) {
  if (canonical == 'unknown') return null;
  final tag = kCanonicalToTag[canonical.toLowerCase()];
  assert(tag != null, 'unmapped canonical emotion: $canonical');
  return tag;
}

/// Canonical emotion -> mood-scale id. Mirrors the server fusion table
/// (AI-service MultimodalFusionEngine mood map) so the onboarding UI
/// interprets the camera signal exactly the way the backend fuses it:
/// happy->happy, neutral->calm, sad->low, anger/fear->stressed,
/// surprise->okay, disgust->low. Returns null for 'unknown'.
String? mapCanonicalToMood(String canonical) {
  switch (canonical.toLowerCase()) {
    case 'happy':
      return 'happy';
    case 'neutral':
      return 'calm';
    case 'sad':
      return 'low';
    case 'anger':
    case 'fear':
      return 'stressed';
    case 'surprise':
      return 'okay';
    case 'disgust':
      return 'low';
    default:
      return null;
  }
}

/// Mood-scale valence. Mirrors the server fusion valence table so local
/// agreement math can never drift from backend fusion:
/// very_happy 1.0, happy 0.7, calm 0.3, okay 0.0, low -0.5, stressed -0.8.
double moodValence(String moodId) {
  switch (moodId) {
    case 'very_happy':
      return 1.0;
    case 'happy':
      return 0.7;
    case 'calm':
      return 0.3;
    case 'okay':
      return 0.0;
    case 'low':
      return -0.5;
    case 'stressed':
      return -0.8;
    default:
      return 0.0;
  }
}

/// How a camera signal relates to the user's self-reported mood.
///
/// Presentation-only interpretation for the onboarding UI: the authoritative
/// fusion (weights, gating, needs_confirmation) stays in the backend. The
/// self-report is ALWAYS primary — [differs] never overrides it, it only
/// explains that the supporting signal disagrees.
enum CameraAgreement {
  /// No usable camera signal (absent, unknown, or below-confidence).
  noSignal,

  /// Camera maps to the same mood the user selected.
  agree,

  /// Adjacent on the valence scale (<= 0.3 apart): consistent, not identical.
  close,

  /// Genuinely different signal: keep the user mood, note the disagreement.
  differs,
}

/// Deterministic agreement between a self-reported [userMoodId] and a stable
/// camera emotion.
///
/// - [cameraEmotion] 'unknown'/unmapped or [cameraConfidence] below
///   [confidenceFloor] (default 0.30, the fusion gate neighborhood) yields
///   [CameraAgreement.noSignal]: the UI falls back to self-report only.
/// - Otherwise the canonical emotion is mapped to the mood scale and compared
///   by valence distance: 0 -> agree, <= 0.3 -> close, else differs.
CameraAgreement cameraAgreement({
  required String userMoodId,
  required String cameraEmotion,
  required double cameraConfidence,
  double confidenceFloor = 0.30,
}) {
  final mapped = mapCanonicalToMood(cameraEmotion);
  if (mapped == null || cameraConfidence < confidenceFloor) {
    return CameraAgreement.noSignal;
  }
  if (mapped == userMoodId) return CameraAgreement.agree;
  final distance =
      (moodValence(mapped) - moodValence(userMoodId)).abs();
  if (distance <= 0.3) return CameraAgreement.close;
  return CameraAgreement.differs;
}
