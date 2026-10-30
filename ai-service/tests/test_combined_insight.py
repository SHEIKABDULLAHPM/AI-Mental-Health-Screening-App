"""Tests for the combined mental + physical insight.

The endpoint must always return grounded text: a deterministic composer when
the LLM is unavailable, and strictly validated model output when it is. The
PHQ-9 item-9 escalation is deterministic and must survive either path.
"""

import asyncio
from fastapi.testclient import TestClient

from app.core.wellness import combined_insight
from app.core.wellness.combined_insight import deterministic_insight, generate_insight
from app.schemas.wellness import (
    CombinedInsightRequest,
    CombinedMentalInput,
    CombinedPhysicalInput,
    CombinedSuggestion,
    CoverageInput,
)


class FakeLLM:
    def __init__(self, payload=None, available=True):
        self.payload = payload
        self.available = available

    async def is_available(self):
        return self.available

    async def complete_json(self, system, user, schema, *, max_tokens=1024):
        return self.payload


def _request(safety_flag=False, sufficient=False):
    return CombinedInsightRequest(
        mental=CombinedMentalInput(
            wellness_score=54,
            stress_level="MODERATE",
            lifestyle_score=64,
            sleep_quality="FAIR",
            primary_focus="MOOD_SUPPORT",
            safety_flag=safety_flag,
            mood="happy",
            mood_trend="stable",
        ),
        physical=CombinedPhysicalInput(
            window_days=14,
            sufficient_data=sufficient,
            coverage=CoverageInput(
                activity_days=6,
                sleep_days=4,
                hydration_days=5,
                mood_checkins=3,
            ),
            pattern_ids=["sleep_below_baseline", "activity_below_baseline"],
            suggestions=[
                CombinedSuggestion(
                    title="Keep a repeatable wind-down",
                    description="Choose a short, repeatable wind-down before bed.",
                    category="SLEEP",
                )
            ],
        ),
    )


def test_deterministic_narrative_uses_only_supplied_aggregates():
    response = deterministic_insight(_request())

    assert response.generated_by == "rules"
    assert "supporting your mood" in response.narrative
    assert "6" in response.narrative and "14" in response.narrative
    assert "diagnosis" in response.narrative.lower()
    assert response.suggestions[0].title == "Keep a repeatable wind-down"


def test_deterministic_text_discloses_sparse_data():
    response = deterministic_insight(_request(sufficient=False))

    assert "not enough recent physical data" in response.narrative.lower()


def test_safety_escalation_is_appended_deterministically():
    response = deterministic_insight(_request(safety_flag=True))

    assert "self-harm" in response.narrative.lower()
    assert "crisis" in response.narrative.lower()
    assert any("trust" in item.description.lower() for item in response.suggestions)


def test_llm_unavailable_returns_deterministic_text():
    response = asyncio.run(generate_insight(_request(), FakeLLM(available=False)))

    assert response.generated_by == "rules"


def test_llm_output_is_used_when_grounded():
    payload = {
        "narrative": (
            "Your check-in shows moderate stress and mood support as the main focus. "
            "Across 14 days you logged activity on 6 days, so gentle consistency is a "
            "reasonable next step. This is guidance, not a diagnosis."
        ),
        "suggestions": [
            {
                "title": "Keep evenings calm",
                "description": "A short, repeatable wind-down can support steadier sleep.",
                "category": "SLEEP",
            }
        ],
    }

    response = asyncio.run(generate_insight(_request(), FakeLLM(payload)))

    assert response.generated_by == "llm"
    assert response.suggestions[0].title == "Keep evenings calm"


def test_llm_output_with_invented_number_is_rejected():
    payload = {
        "narrative": (
            "You walked 12000 steps every day and slept 9 hours, which is excellent. "
            "This is guidance, not a diagnosis."
        ),
        "suggestions": [
            {
                "title": "Walk more",
                "description": "Aim for a target each day.",
                "category": "ACTIVITY",
            }
        ],
    }

    response = asyncio.run(generate_insight(_request(), FakeLLM(payload)))

    assert response.generated_by == "rules"


def test_llm_diagnosis_language_is_rejected():
    payload = {
        "narrative": (
            "You have depression and a sleep disorder, so you should start medication "
            "right away. This is guidance, not a diagnosis."
        ),
        "suggestions": [
            {"title": "Rest", "description": "Take it easy.", "category": "SLEEP"}
        ],
    }

    response = asyncio.run(generate_insight(_request(), FakeLLM(payload)))

    assert response.generated_by == "rules"


def test_safety_escalation_survives_the_llm_path():
    payload = {
        "narrative": (
            "Your check-in shows moderate stress and mood support as the main focus. "
            "Across 14 days you logged activity on 6 days. This is guidance, not a "
            "diagnosis."
        ),
        "suggestions": [
            {"title": "Rest", "description": "Take it easy.", "category": "SLEEP"}
        ],
    }

    response = asyncio.run(generate_insight(_request(safety_flag=True), FakeLLM(payload)))

    assert response.generated_by == "llm"
    assert "self-harm" in response.narrative.lower()
    assert any("trust" in item.description.lower() for item in response.suggestions)


def test_safety_escalation_never_drops_outreach_when_cause_is_named():
    payload = {
        "narrative": (
            "You mentioned thoughts of self-harm, which sounds heavy. This is "
            "guidance, not a diagnosis."
        ),
        "suggestions": [
            {"title": "Rest", "description": "Take it easy.", "category": "SLEEP"}
        ],
    }

    response = asyncio.run(generate_insight(_request(safety_flag=True), FakeLLM(payload)))
    lower = response.narrative.lower()

    assert "reach out" in lower
    assert "emergency number" in lower or "crisis service" in lower
    # The cause is not repeated, but the action still is.
    assert lower.count("self-harm") == 1


def test_explicit_diagnosis_language_is_rejected_even_without_other_terms():
    payload = {
        "narrative": (
            "Your diagnosis is depression. Across 14 days you logged activity on "
            "6 days. This is guidance, not a diagnosis."
        ),
        "suggestions": [
            {"title": "Rest", "description": "Take it easy.", "category": "SLEEP"}
        ],
    }

    response = asyncio.run(generate_insight(_request(), FakeLLM(payload)))

    assert response.generated_by == "rules"


def test_http_endpoint_returns_combined_insight(monkeypatch):
    monkeypatch.setattr(
        combined_insight, "build_llm_client", lambda: FakeLLM(available=False)
    )
    client = TestClient(__import__("app.main", fromlist=["app"]).app)

    response = client.post(
        "/api/v1/wellness/combined-insight",
        json=_request().model_dump(),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["generated_by"] == "rules"
    assert body["narrative"]
    assert body["suggestions"]


def test_http_endpoint_requires_a_mental_block():
    client = TestClient(__import__("app.main", fromlist=["app"]).app)

    response = client.post("/api/v1/wellness/combined-insight", json={})

    assert response.status_code == 422
