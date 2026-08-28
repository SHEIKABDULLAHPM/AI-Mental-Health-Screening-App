"""Multimodal mood fusion engine.

Combines manual mood selection, text NLP analysis, and camera facial affect
into a single structured observation using an explicit deterministic
fusion strategy.

Fusion weights (manual mood is authoritative):
  - Manual mood selection:   0.50  (user intent)
  - Text NLP analysis:      0.25  (linguistic signal)
  - Camera facial affect:   0.25  (physiological signal)

If only two sources are available, weights are re-normalised.
If only manual mood is provided, no AI observation is generated.

The user's confirmed mood always overrides AI suggestions.

Low-confidence handling:
  - If combined confidence < 0.30, returns fused_emotion="unknown"
  - Camera analysis uses valence/arousal when available (more accurate
    than simple mood mapping)
"""

from __future__ import annotations

from typing import Any

from app.logging import get_logger

log = get_logger(__name__)

# Mood → numeric valence for weighted averaging (-1.0 negative … +1.0 positive)
_MOOD_VALENCE: dict[str, float] = {
    "very_happy": 1.0,
    "happy": 0.7,
    "calm": 0.3,
    "okay": 0.0,
    "low": -0.5,
    "stressed": -0.8,
}

_VALENCE_TO_MOOD = [
    (0.75, "very_happy"),
    (0.45, "happy"),
    (0.10, "calm"),
    (-0.20, "okay"),
    (-0.55, "low"),
    (-1.01, "stressed"),
]

_SENTIMENT_VALENCE: dict[str, float] = {
    "positive": 0.7,
    "neutral": 0.0,
    "negative": -0.7,
}

# Low-confidence threshold — below this, return "unknown" emotion
_LOW_CONFIDENCE_THRESHOLD = 0.30


def _valence_to_mood(valence: float) -> str:
    for threshold, mood in _VALENCE_TO_MOOD:
        if valence >= threshold:
            return mood
    return "stressed"


class MultimodalFusionEngine:
    """Deterministic fusion of mood sources into a combined observation."""

    def fuse(
        self,
        *,
        manual_mood: str | None = None,
        manual_emotion: str | None = None,
        text_analysis: dict[str, Any] | None = None,
        camera_analysis: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Fuse available sources into a combined mood observation.

        Returns a dict with:
          - fused_mood: str
          - fused_emotion: str
          - confidence: float (0.0–1.0)
          - sources_used: list[str]
          - manual_mood: str | None  (preserved)
          - text_analysis: dict | None (preserved)
          - camera_analysis: dict | None (preserved)
          - needs_confirmation: bool
        """
        sources: list[str] = []
        valences: list[float] = []
        weights: list[float] = []

        # ── Manual mood (weight 0.50) ──
        if manual_mood and manual_mood in _MOOD_VALENCE:
            sources.append("MANUAL")
            valences.append(_MOOD_VALENCE[manual_mood])
            weights.append(0.50)

        # ── Text analysis (weight 0.25) ──
        if text_analysis and text_analysis.get("emotion") not in (None, "unknown"):
            emo_conf = text_analysis.get("emotion_confidence", 0)
            if emo_conf > 0.1:
                sources.append("TEXT")
                text_sent = text_analysis.get("sentiment", "neutral")
                valences.append(_SENTIMENT_VALENCE.get(text_sent, 0.0))
                weights.append(0.25)

        # ── Camera analysis (weight 0.25) ──
        # Prefer valence/arousal when available (more accurate than mood mapping)
        if camera_analysis and camera_analysis.get("confidence", 0) > 0.2:
            cam_emotion = camera_analysis.get("emotion", "unknown")
            if cam_emotion not in (None, "unknown"):
                sources.append("CAMERA")

                # Use camera valence if available (from facial affect model)
                # None means the camera model didn't produce a valence score;
                # 0.0 is a valid neutral valence and should be used as-is.
                cam_valence = camera_analysis.get("valence")
                if cam_valence is not None:
                    valences.append(float(cam_valence))
                else:
                    # Fallback to mood mapping
                    cam_mood = camera_analysis.get("suggested_mood", "okay")
                    valences.append(_MOOD_VALENCE.get(cam_mood, 0.0))
                weights.append(0.25)

        # ── No sources → neutral default ──
        if not sources:
            return {
                "fused_mood": "okay",
                "fused_emotion": "unknown",
                "confidence": 0.0,
                "sources_used": [],
                "manual_mood": manual_mood,
                "text_analysis": text_analysis,
                "camera_analysis": camera_analysis,
                "needs_confirmation": True,
            }

        # ── Weighted fusion ──
        total_weight = sum(weights)
        weighted_valence = sum(v * w for v, w in zip(valences, weights)) / total_weight
        fused_mood = _valence_to_mood(weighted_valence)

        # Confidence = average of contributing confidences × source coverage
        # Only count sources that actually contributed to the fusion
        confidences: list[float] = []
        if "MANUAL" in sources:
            confidences.append(0.9)  # manual is high confidence by definition
        if "TEXT" in sources and text_analysis:
            confidences.append(text_analysis.get("emotion_confidence", 0.5))
        if "CAMERA" in sources and camera_analysis:
            confidences.append(camera_analysis.get("confidence", 0.5))

        avg_confidence = sum(confidences) / len(confidences) if confidences else 0.0
        coverage_bonus = len(sources) / 3.0  # up to 1.0 when all 3 sources
        combined_confidence = min(avg_confidence * (0.7 + 0.3 * coverage_bonus), 1.0)

        # Determine fused emotion from text or camera
        # Return "unknown" when confidence is too low
        fused_emotion = "unknown"
        if combined_confidence >= _LOW_CONFIDENCE_THRESHOLD:
            if text_analysis and text_analysis.get("emotion") not in (None, "unknown"):
                fused_emotion = text_analysis["emotion"]
            elif camera_analysis and camera_analysis.get("emotion") not in (None, "unknown"):
                fused_emotion = camera_analysis["emotion"]
            elif manual_emotion:
                fused_emotion = manual_emotion

        # ── Disagreement detection ──
        # If manual mood and AI suggestion differ significantly, flag for confirmation
        needs_confirmation = False
        if manual_mood and fused_mood != manual_mood:
            manual_val = _MOOD_VALENCE.get(manual_mood, 0.0)
            if abs(manual_val - weighted_valence) > 0.4:
                needs_confirmation = True

        # Low confidence always needs confirmation
        if combined_confidence < _LOW_CONFIDENCE_THRESHOLD:
            needs_confirmation = True

        log.info(
            "mood_fusion_complete",
            sources=sources,
            fused_mood=fused_mood,
            fused_emotion=fused_emotion,
            confidence=round(combined_confidence, 4),
            needs_confirmation=needs_confirmation,
        )

        return {
            "fused_mood": fused_mood,
            "fused_emotion": fused_emotion,
            "confidence": round(combined_confidence, 4),
            "sources_used": sources,
            "manual_mood": manual_mood,
            "text_analysis": text_analysis,
            "camera_analysis": camera_analysis,
            "needs_confirmation": needs_confirmation,
        }
