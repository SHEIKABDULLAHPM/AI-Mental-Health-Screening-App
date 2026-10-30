"""Mood analysis endpoints.

Provides text emotion/sentiment analysis, camera facial affect processing,
server-side face-emotion inference (TFLite), multimodal mood fusion, and
safety detection.

On-device classification (Flutter + ML Kit) remains the real-time path; the
/face endpoint offers server-side inference of the same face crops with the
production vit_fer_fp16.tflite (ViT-B/16) model without changing that flow.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.config import settings
from app.core.mood.face_emotion import FaceEmotionError, get_face_emotion_analyzer
from app.core.mood.fusion import MultimodalFusionEngine
from app.core.mood.text_analyzer import get_text_analyzer
from app.core.ratelimit import rate_limited
from app.logging import get_logger
from app.schemas.mood import (
    CameraObservationRequest,
    CameraObservationResponse,
    FaceEmotionResponse,
    MoodAnalysisRequest,
    MoodAnalysisResponse,
    SafetyResult,
    TextAnalysisRequest,
    TextAnalysisResponse,
)

log = get_logger(__name__)

router = APIRouter(dependencies=[Depends(rate_limited)])

_fusion = MultimodalFusionEngine()

# Canonical vit-fer-7 classes, identical to the Flutter client and the Spring
# backend. The server never invents a model identity: the client-reported
# version is validated and echoed (see analyze_camera). The 8-class synora-fer
# names (contempt/happiness/sadness) are gone -- the ViT cannot emit them.
_CANONICAL_EMOTIONS = frozenset({
    "anger", "disgust", "fear", "happy", "neutral", "sad", "surprise",
})

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
    """Re-label and re-weight a structured on-device observation.

    No vision runs here: the phone already classified the face. The server
    maps the canonical emotion to a mood, recomputes confidence from the
    reported scores (scaled by face quality and frame count — the client
    value is an input, not the verdict), and echoes the client's model
    version after validation. Unknown/quality-gated frames map to a
    neutral, zero-confidence observation instead of a forced emotion.
    """
    reported_version = payload.model_version.strip() or "unknown"

    if not payload.face_detected or payload.dominant_emotion.lower() == "unknown":
        return CameraObservationResponse(
            emotion="unknown",
            confidence=0.0,
            suggested_mood="okay",
            face_quality=round(min(payload.face_quality, 1.0), 4),
            frames_analyzed=payload.frames_analyzed,
            model_version=reported_version,
        )

    # Exactly the canonical vocabulary -- no legacy aliases, so the AI
    # service, the Flutter client and the Spring backend cannot disagree.
    emotion_to_mood = {
        "happy": "happy",
        "neutral": "calm",
        "sad": "low",
        "anger": "stressed",
        "surprise": "okay",
        "fear": "stressed",
        "disgust": "low",
    }

    dominant = payload.dominant_emotion.lower()
    if dominant not in _CANONICAL_EMOTIONS and dominant not in emotion_to_mood:
        return CameraObservationResponse(
            emotion="unknown",
            confidence=0.0,
            suggested_mood="okay",
            face_quality=round(min(payload.face_quality, 1.0), 4),
            frames_analyzed=payload.frames_analyzed,
            model_version=reported_version,
        )
    suggested_mood = emotion_to_mood.get(dominant, "okay")

    quality_factor = min(payload.face_quality, 1.0)
    frame_factor = min(payload.frames_analyzed / 10.0, 1.0)
    base_confidence = payload.emotion_scores.get(dominant, 0.5)
    if payload.calibrated_confidence is not None:
        base_confidence = min(base_confidence, payload.calibrated_confidence)
    base_confidence = min(max(base_confidence, 0.0), 1.0)
    combined_confidence = min(base_confidence * (0.6 + 0.2 * quality_factor + 0.2 * frame_factor), 1.0)

    return CameraObservationResponse(
        emotion=dominant,
        confidence=round(combined_confidence, 4),
        suggested_mood=suggested_mood,
        face_quality=round(payload.face_quality, 4),
        frames_analyzed=payload.frames_analyzed,
        model_version=reported_version,
    )


_ALLOWED_IMAGE_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})

# Controlled error codes mapped to client-safe HTTP statuses. Internal
# details (paths, tracebacks) are never exposed.
_FACE_ERROR_STATUS = {
    "invalid_image": 400,
    "face_too_small": 422,
    "poor_quality": 422,
    "model_missing": 503,
    "model_unavailable": 503,
    "model_load_failed": 503,
    "runtime_missing": 503,
    "inference_failed": 503,
    "invalid_output": 503,
}


@router.post(
    "/face",
    response_model=FaceEmotionResponse,
    summary="Classify a face-crop image with vit_fer_fp16.tflite (ViT-B/16)",
)
async def analyze_face(file: UploadFile = File(description="Face-crop image (JPEG/PNG/WebP)")) -> FaceEmotionResponse:  # noqa: B008
    """Server-side facial emotion classification.

    Face detection stays on-device: the client sends the already-detected
    face crop. The server preprocesses, runs TFLite inference, validates the
    output, and returns the structured result. Low-confidence predictions
    return emotion="uncertain" instead of a forced label. The validated
    result plugs directly into the existing fusion engine.
    """
    if not settings.emotion_enabled:
        raise HTTPException(status_code=503, detail="Face emotion analysis is disabled")
    if file.content_type not in _ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail="Unsupported image format. Use JPEG, PNG, or WebP.",
        )
    try:
        image_bytes = await file.read()
    except Exception:
        raise HTTPException(status_code=400, detail="Image could not be read")
    max_bytes = int(settings.emotion_max_image_mb * 1024 * 1024)
    if not image_bytes or len(image_bytes) > max_bytes:
        raise HTTPException(status_code=400, detail="Invalid image payload")

    try:
        analyzer = get_face_emotion_analyzer()
        result = analyzer.predict(image_bytes)
    except FaceEmotionError as exc:
        # Never log image bytes; never expose internals to the client.
        log.warning("face_emotion_failed", code=exc.code)
        status = _FACE_ERROR_STATUS.get(exc.code, 503)
        raise HTTPException(status_code=status, detail=str(exc))
    except Exception:
        log.warning("face_emotion_failed", code="unexpected", exc_info=True)
        raise HTTPException(status_code=503, detail="Face emotion analysis failed")
    return FaceEmotionResponse(**result.to_response())


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
        ai_suggested_mood=fusion_result.get("ai_suggested_mood"),
        fused_emotion=fusion_result["fused_emotion"],
        confidence=fusion_result["confidence"],
        sources_used=fusion_result["sources_used"],
        manual_mood=fusion_result["manual_mood"],
        text_analysis=text_result,
        camera_analysis=camera_result,
        needs_confirmation=fusion_result["needs_confirmation"],
        safety=safety,
    )
