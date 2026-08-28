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
