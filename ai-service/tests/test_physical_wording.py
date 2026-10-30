"""Tests for optional LLM wording on the physical insight endpoint.

The deterministic rule table remains the source of truth. The model may only
re-word suggestions for patterns that were actually detected, and unsafe or
ungrounded output must be discarded.
"""

import asyncio

from app.core.wellness.physical_insights import recommend, recommend_with_llm
from app.schemas.wellness import (
    CoverageInput,
    GoalInput,
    InsightPattern,
    PhysicalInsightRequest,
)


class FakeLLM:
    def __init__(self, payload=None, available=True):
        self.payload = payload
        self.available = available

    async def is_available(self):
        return self.available

    async def complete_json(self, system, user, schema, *, max_tokens=1024):
        return self.payload


def _payload(patterns=None, existing=None):
    return PhysicalInsightRequest(
        window_days=14,
        coverage=CoverageInput(
            activity_days=9, sleep_days=7, hydration_days=4, mood_checkins=5
        ),
        patterns=patterns
        if patterns is not None
        else [InsightPattern(id="sleep_below_baseline", severity="ATTENTION")],
        existing_recommendations=existing or [],
        goals=GoalInput(hydration_target_ml=2000, sleep_target_minutes=480),
    )


def test_unavailable_llm_returns_rule_suggestions():
    response = asyncio.run(recommend_with_llm(_payload(), FakeLLM(available=False)))

    assert response.generated_by == "rules"
    assert response.recommendations[0].id == "consistent_wind_down"


def test_grounded_wording_is_used():
    payload = {
        "recommendations": [
            {
                "id": "sleep_below_baseline",
                "title": "Protect your wind-down",
                "description": "A calm, repeatable evening routine can support rest.",
                "category": "SLEEP",
            }
        ]
    }

    response = asyncio.run(recommend_with_llm(_payload(), FakeLLM(payload)))

    assert response.generated_by == "llm"
    assert response.recommendations[0].id == "llm_sleep_below_baseline"
    assert "invented" in (response.note or "").lower()


def test_wording_for_undetected_pattern_is_rejected():
    payload = {
        "recommendations": [
            {
                "id": "hydration_below_target",
                "title": "Drink more",
                "description": "Add water to your routine.",
                "category": "HYDRATION",
            }
        ]
    }

    response = asyncio.run(recommend_with_llm(_payload(), FakeLLM(payload)))

    assert response.generated_by == "rules"


def test_wording_with_invented_numbers_is_rejected():
    payload = {
        "recommendations": [
            {
                "id": "sleep_below_baseline",
                "title": "Sleep 9 hours",
                "description": "Aim for a fixed 9 hour target every night.",
                "category": "SLEEP",
            }
        ]
    }

    response = asyncio.run(recommend_with_llm(_payload(), FakeLLM(payload)))

    assert response.generated_by == "rules"


def test_wording_with_restriction_or_diagnosis_is_rejected():
    payload = {
        "recommendations": [
            {
                "id": "sleep_below_baseline",
                "title": "Fix your disorder",
                "description": "Cut calories and force yourself to sleep.",
                "category": "SLEEP",
            }
        ]
    }

    response = asyncio.run(recommend_with_llm(_payload(), FakeLLM(payload)))

    assert response.generated_by == "rules"


def test_no_patterns_never_calls_the_model():
    class ExplodingLLM:
        async def is_available(self):
            raise AssertionError("model must not be consulted without patterns")

    response = asyncio.run(recommend_with_llm(_payload(patterns=[]), ExplodingLLM()))

    assert response.generated_by == "rules"
    assert response.recommendations[0].id == "general_grounding"


def test_deterministic_recommendation_labels_itself_as_rules():
    response = recommend(_payload())

    assert response.generated_by == "rules"
