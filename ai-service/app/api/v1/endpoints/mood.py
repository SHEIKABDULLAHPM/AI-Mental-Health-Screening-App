"""Mood analysis endpoints.

Provides text emotion/sentiment analysis, camera facial affect processing,
multimodal mood fusion, and safety detection.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.core.mood.fusion import MultimodalFusionEngine
from app.core.mood.text_analyzer import get_text_analyzer
from app.core.ratelimit import rate_limited
from app.logging import get_logger
from app.schemas.mood import (
    CameraObservationRequest,
    CameraObservationResponse,
    MoodAnalysisRequest,
    MoodAnalysisResponse,
    SafetyResult,
    TextAnalysisRequest,
    TextAnalysisResponse,
)

log = get_logger(__name__)

router = APIRouter(dependencies=[Depends(rate_limited)])

_fusion = MultimodalFusionEngine()

_CAMERA_MODEL_VERSION = "mediapipe-face-landmarker-v0.10"

# Crisis keywords for safety detection in mood notes
_CRISIS_KEYWORDS = [
    "kill myself", "end my life", "want to die", "suicide",
    "self harm", "hurt myself", "end it all", "no reason to live",
    "better off dead", "not worth living", "plan to end",
    "overdose", "cutting myself", "hang myself",
    "want to disappear", "wish i was dead", "give up on life",
    "cant go on", "cant take it anymore", "nothing matters",
]

_ELEVATED_RISK_KEYWORDS = [
    "hopeless", "worthless", "trapped", "burden",
    "no hope", "helpless", "cantcope", "cant cope",
    "isolated", "alone", "nobody cares",
    "severe depression", "cant sleep", "nightmares",
    "panic", "anxiety attack", "cant breathe",
]


def _check_safety(text: str | None) -> SafetyResult:
    """Check text for crisis-related content."""
    if not text or not text.strip():
        return SafetyResult()

    lower = text.lower().strip()

    for kw in _CRISIS_KEYWORDS:
        if kw in lower:
            return SafetyResult(
                flag=True,
                level="crisis",
                message="We noticed something concerning in what you shared. Your safety matters to us.",
                resources={
                    "helpline": "988 Suicide & Crisis Lifeline: Call or text 988",
                    "crisisText": "Crisis Text Line: Text HOME to 741741",
                    "international": "International Association for Suicide Prevention: https://www.iasp.info/resources/Crisis_Centres/",
                    "message": "If you are in immediate danger, please call your local emergency number.",
                },
            )

    for kw in _ELEVATED_RISK_KEYWORDS:
        if kw in lower:
            return SafetyResult(
                flag=True,
                level="elevated",
                message="It sounds like you may be going through a difficult time. Support is available if you need it.",
                resources={
                    "helpline": "988 Suicide & Crisis Lifeline: Call or text 988",
                    "crisisText": "Crisis Text Line: Text HOME to 741741",
                    "message": "You are not alone. Reaching out for support is a sign of strength.",
                },
            )

    return SafetyResult()


@router.post(
    "/text",
    response_model=TextAnalysisResponse,
    summary="Analyze mood note text for emotion and sentiment",
)
async def analyze_text(payload: TextAnalysisRequest) -> TextAnalysisResponse:
    """Analyze a user's mood note using pretrained NLP models.

    Returns emotion category, sentiment polarity, and confidence scores.
    This is a wellness-support signal, NOT a clinical diagnosis.
    """
    try:
        analyzer = get_text_analyzer()
        result = analyzer.analyze(payload.text)
        return TextAnalysisResponse(**result)
    except Exception as exc:
        log.warning("text_mood_analysis_failed", error=str(exc))
        raise HTTPException(status_code=503, detail="Text analysis temporarily unavailable")


@router.post(
    "/camera",
    response_model=CameraObservationResponse,
    summary="Process structured camera facial affect observation",
)
async def analyze_camera(payload: CameraObservationRequest) -> CameraObservationResponse:
    """Process a structured camera observation from on-device face analysis."""
    if not payload.face_detected:
        return CameraObservationResponse(
            emotion="neutral",
            confidence=0.0,
            suggested_mood="okay",
            face_quality=0.0,
            frames_analyzed=payload.frames_analyzed,
            model_version=_CAMERA_MODEL_VERSION,
        )

    emotion_to_mood = {
        "happy": "happy",
        "joy": "happy",
        "neutral": "calm",
        "sad": "low",
        "sadness": "low",
        "angry": "stressed",
        "anger": "stressed",
        "surprise": "okay",
        "surprised": "okay",
        "fear": "stressed",
        "disgust": "low",
        "contempt": "low",
    }

    dominant = payload.dominant_emotion.lower()
    suggested_mood = emotion_to_mood.get(dominant, "okay")

    quality_factor = min(payload.face_quality, 1.0)
    frame_factor = min(payload.frames_analyzed / 10.0, 1.0)
    base_confidence = payload.emotion_scores.get(dominant, 0.5)
    combined_confidence = min(base_confidence * (0.6 + 0.2 * quality_factor + 0.2 * frame_factor), 1.0)

    return CameraObservationResponse(
        emotion=dominant,
        confidence=round(combined_confidence, 4),
        suggested_mood=suggested_mood,
        face_quality=round(payload.face_quality, 4),
        frames_analyzed=payload.frames_analyzed,
        model_version=_CAMERA_MODEL_VERSION,
    )


@router.post(
    "/analyze",
    response_model=MoodAnalysisResponse,
    summary="Multimodal mood analysis combining manual, text, and camera sources",
)
async def analyze_mood(payload: MoodAnalysisRequest) -> MoodAnalysisResponse:
    """Fuse manual mood selection with optional text and camera AI observations.

    Uses a deterministic weighted fusion strategy with safety detection.
    """
    text_result = None
    camera_result = None

    if payload.text_observation:
        try:
            analyzer = get_text_analyzer()
            raw = analyzer.analyze(payload.text_observation.text)
            text_result = TextAnalysisResponse(**raw)
        except Exception as exc:
            log.warning("text_analysis_in_fusion_failed", error=str(exc))

    if payload.camera_observation:
        camera_result = await analyze_camera(payload.camera_observation)

    fusion_result = _fusion.fuse(
        manual_mood=payload.manual_mood,
        manual_emotion=payload.manual_emotion,
        text_analysis=text_result.model_dump() if text_result else None,
        camera_analysis=camera_result.model_dump() if camera_result else None,
    )

    # Safety detection on user-provided text
    note_text = payload.text_observation.text if payload.text_observation else None
    safety = _check_safety(note_text)

    return MoodAnalysisResponse(
        fused_mood=fusion_result["fused_mood"],
        fused_emotion=fusion_result["fused_emotion"],
        confidence=fusion_result["confidence"],
        sources_used=fusion_result["sources_used"],
        manual_mood=fusion_result["manual_mood"],
        text_analysis=text_result,
        camera_analysis=camera_result,
        needs_confirmation=fusion_result["needs_confirmation"],
        safety=safety,
    )
