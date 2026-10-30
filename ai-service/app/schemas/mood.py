"""Request/response schemas for mood analysis endpoints."""

from __future__ import annotations

from pydantic import BaseModel, Field


# ── Text Analysis ────────────────────────────────────────────────────

class TextAnalysisRequest(BaseModel):
    """Analyze a mood note for emotion and sentiment."""

    text: str = Field(min_length=1, max_length=5000, description="Mood note text to analyze")


class TextAnalysisResponse(BaseModel):
    source: str = "TEXT"
    emotion: str
    emotion_confidence: float = Field(ge=0.0, le=1.0)
    sentiment: str
    sentiment_confidence: float = Field(ge=0.0, le=1.0)
    suggested_mood: str
    model_version: str


# ── Camera Facial Affect ─────────────────────────────────────────────

class CameraObservationRequest(BaseModel):
    """Structured camera facial affect observation (processed on-device).

    The server performs NO vision inference: it re-labels, re-weights and
    fuses the on-device result. model_version is the CLIENT's model
    identity, echoed back after validation — never asserted by the server.
    """

    dominant_emotion: str = Field(
        description="Dominant facial emotion detected (canonical synora-fer class or unknown)"
    )
    emotion_scores: dict[str, float] = Field(
        default_factory=dict,
        description="Per-emotion confidence scores (0.0-1.0)"
    )
    face_detected: bool = True
    face_count: int = Field(default=1, ge=0, le=1)
    face_quality: float = Field(default=0.8, ge=0.0, le=1.0, description="Face quality score")
    valence: float = Field(default=0.0, ge=-1.0, le=1.0, description="Facial affect valence")
    arousal: float = Field(default=0.0, ge=-1.0, le=1.0, description="Facial affect arousal")
    frames_analyzed: int = Field(default=1, ge=1, description="Number of frames analyzed")
    status: str = Field(
        default="PREDICTED",
        description="On-device event status (PREDICTED, UNCERTAIN, or quality-gate status)",
    )
    calibrated_confidence: float | None = Field(
        default=None, ge=0.0, le=1.0,
        description="Device calibrated confidence; re-weighted server-side, never trusted raw",
    )
    model_version: str = Field(
        default="unknown",
        min_length=1,
        max_length=64,
        description="On-device model version reported by the client",
    )


class CameraObservationResponse(BaseModel):
    source: str = "CAMERA"
    emotion: str
    confidence: float = Field(ge=0.0, le=1.0)
    suggested_mood: str
    face_quality: float
    frames_analyzed: int
    model_version: str


# ── Server-side Face Emotion (TFLite) ────────────────────────────────────

class FaceEmotionResponse(BaseModel):
    """Structured server-side facial emotion classification result.

    Extends the camera response contract with per-class probabilities so the
    existing fusion engine and clients keep working unchanged.
    """

    source: str = "CAMERA"
    emotion: str
    confidence: float = Field(ge=0.0, le=1.0)
    # Top-1 minus top-2 probability. Reported so a client can apply the same
    # ambiguity rule the server used; an emotion is only named when BOTH the
    # confidence and this margin clear their thresholds.
    margin: float = Field(default=0.0, ge=0.0, le=1.0)
    probabilities: dict[str, float] = Field(default_factory=dict)
    suggested_mood: str
    model_version: str
    analysis_version: str = "2.0"


# ── Safety ───────────────────────────────────────────────────────────

class SafetyResult(BaseModel):
    flag: bool = False
    level: str = "none"
    message: str | None = None
    resources: dict[str, str] | None = None


# ── Multimodal Fusion ────────────────────────────────────────────────

class MoodAnalysisRequest(BaseModel):
    """Full multimodal mood analysis."""

    manual_mood: str = Field(
        min_length=1,
        description="User's manually selected mood ID (e.g. happy, calm, low)"
    )
    manual_emotion: str | None = Field(default=None, description="User's selected emotion tag")
    text_observation: TextAnalysisRequest | None = Field(
        default=None, description="Text note analysis result"
    )
    camera_observation: CameraObservationRequest | None = Field(
        default=None, description="Camera facial affect observation"
    )


class MoodAnalysisResponse(BaseModel):
    """Structured multimodal mood analysis result."""

    fused_mood: str = Field(
        description="The mood of record. Equals the user's manual selection "
        "when one was provided; the AI read is never substituted for it."
    )
    ai_suggested_mood: str | None = Field(
        default=None,
        description="Mood implied by the weighted AI blend. Reported "
        "separately from fused_mood so disagreement stays visible.",
    )
    fused_emotion: str
    confidence: float = Field(ge=0.0, le=1.0)
    sources_used: list[str]
    manual_mood: str | None
    text_analysis: TextAnalysisResponse | None
    camera_analysis: CameraObservationResponse | None
    needs_confirmation: bool
    model_version: str = "multimodal-fusion-v1"
    safety: SafetyResult | None = None
