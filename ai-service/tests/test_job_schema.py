"""Unit tests for the AI-job schema validation and prompt building."""
import pytest
from pydantic import ValidationError

from app.core.prompts import SYSTEM_PROMPT, build_screening_prompt
from app.schemas.job import AiInsightResult, ScreeningScoresInput

VALID_SCORES = {
    "phq9": 15,
    "gad7": 12,
    "pss10": 17,
    "who5": 11,
    "wellnessScore": 42,
    "stressLevel": "HIGH",
    "lifestyleScore": 55,
    "sleepQuality": "FAIR",
    "primaryFocus": "STRESS_MANAGEMENT",
}


def test_screening_scores_valid():
    scores = ScreeningScoresInput(**VALID_SCORES)
    assert scores.who_percent == 44


def test_screening_scores_who_percent_clamped():
    scores = ScreeningScoresInput(**{**VALID_SCORES, "who5": 0})
    assert scores.who_percent == 0


def test_screening_scores_out_of_range_rejected():
    with pytest.raises(ValidationError):
        ScreeningScoresInput(**{**VALID_SCORES, "phq9": 99})


def test_screening_scores_unknown_field_rejected():
    with pytest.raises(ValidationError):
        ScreeningScoresInput(**{**VALID_SCORES, "extra": "nope"})


def test_insight_valid():
    result = AiInsightResult(
        aiInsight="You have been managing a lot lately, and that is okay.",
        evidenceSources=["mindfullness-practices"],
    )
    assert result.evidenceSources == ["mindfullness-practices"]


def test_insight_rejects_diagnosis():
    with pytest.raises(ValidationError):
        AiInsightResult(aiInsight="You are suffering from clinical depression.")


def test_insight_rejects_diagnosis_variants():
    # Rephrased diagnostic claims must also be rejected, not just the exact
    # previously listed phrases.
    for text in [
        "It seems you have anxiety, consider resting.",
        "Your signs point to generalized anxiety disorder.",
        "This looks like clinical depression developing.",
        "My diagnosis: you are stressed.",
    ]:
        with pytest.raises(ValidationError):
            AiInsightResult(aiInsight=text)


def test_insight_rejects_blank():
    with pytest.raises(ValidationError):
        AiInsightResult(aiInsight="   ")


def test_insight_too_short():
    with pytest.raises(ValidationError):
        AiInsightResult(aiInsight="Hi.")


def test_prompt_embeds_version_and_scores():
    scores = ScreeningScoresInput(**VALID_SCORES)
    system, user = build_screening_prompt(scores, [])
    assert "MindEase" in system
    assert "PHQ-9 total: 15 / 27" in user
    assert "STRESS_MANAGEMENT" in user


def test_camera_fields_optional_and_backward_compatible():
    scores = ScreeningScoresInput(**VALID_SCORES)
    assert scores.cameraEmotion is None
    assert scores.signalAgreement is None
    with_camera = ScreeningScoresInput(
        **{
            **VALID_SCORES,
            "onboardingMood": "happy",
            "cameraEmotion": "sad",
            "cameraConfidence": 0.55,
            "cameraModelVersion": "vit-fer-7",
            "signalAgreement": "differs",
        }
    )
    assert with_camera.cameraEmotion == "sad"
    assert with_camera.signalAgreement == "differs"


def test_camera_confidence_out_of_range_rejected():
    with pytest.raises(ValidationError):
        ScreeningScoresInput(**{**VALID_SCORES, "cameraConfidence": 1.5})


def test_prompt_includes_camera_signal_qualitatively():
    scores = ScreeningScoresInput(
        **{
            **VALID_SCORES,
            "onboardingMood": "happy",
            "moodHistoryCount": 4,
            "cameraEmotion": "sad",
            "cameraConfidence": 0.55,
            "signalAgreement": "differs",
        }
    )
    _, user = build_screening_prompt(scores, [])
    assert "sadness" in user
    assert "differs from what they reported" in user
    assert "self-report stays primary" in user
    assert "0.55" not in user


def test_prompt_agree_camera_acknowledged():
    scores = ScreeningScoresInput(
        **{
            **VALID_SCORES,
            "onboardingMood": "low",
            "cameraEmotion": "sad",
            "cameraConfidence": 0.9,
            "signalAgreement": "agree",
        }
    )
    _, user = build_screening_prompt(scores, [])
    assert "lines up with what they reported" in user
    assert "high confidence" in user


def test_prompt_suppresses_absent_or_unknown_camera():
    for extra in [
        {},
        {"cameraEmotion": "unknown", "signalAgreement": "noSignal"},
        {"cameraEmotion": "happy", "signalAgreement": "noSignal"},
    ]:
        scores = ScreeningScoresInput(
            **{**VALID_SCORES, "onboardingMood": "calm", **extra}
        )
        _, user = build_screening_prompt(scores, [])
        assert "camera check-in detected" not in user
