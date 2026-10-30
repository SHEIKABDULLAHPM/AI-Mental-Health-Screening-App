"""Tests for the personalised wellness analysis used by the three app buttons."""

from app.core.wellness.analysis import _validate, build_analysis
from app.schemas.analysis import WellnessAnalysisRequest

METRICS = [
    {"key": "sleep_hours_avg", "label": "Sleep duration", "value": 6.1, "unit": "h"},
    {"key": "steps_avg", "label": "Daily steps", "value": 4200, "unit": "steps"},
    {"key": "stress_level", "label": "Stress level", "value": 72, "unit": "/100"},
    {"key": "wellness_score", "label": "Wellness score", "value": 54, "unit": "/100"},
]


def _request(**overrides):
    payload = {
        "type": "COMBINED",
        "window_days": 14,
        "metrics": METRICS,
        "patterns": ["Sleep duration is below your recent baseline."],
    }
    payload.update(overrides)
    return WellnessAnalysisRequest(**payload)


def test_first_analysis_says_there_is_no_baseline():
    result = build_analysis(_request())
    assert result.generated_by == "rules"
    assert "first stored analysis" in result.narrative
    assert "nothing to compare" in result.narrative or "nothing to compare against" in result.narrative


def test_comparison_drives_the_narrative():
    result = build_analysis(
        _request(
            comparison={
                "has_previous": True,
                "days_since_previous": 7,
                "overall": "MIXED",
                "improved": ["sleep consistency"],
                "declined": ["daily activity"],
            }
        )
    )
    assert "7 days ago" in result.narrative
    assert "sleep consistency" in result.narrative
    assert "daily activity" in result.narrative
    assert any("daily activity" in action for action in result.next_actions)


def test_low_sleep_and_activity_produce_targets():
    result = build_analysis(_request())
    categories = {rec.category for rec in result.recommendations}
    titles = " ".join(rec.title.lower() for rec in result.recommendations)
    assert "SLEEP" in categories
    assert "ACTIVITY" in categories
    assert "walk" in titles or "movement" in titles
    actions = " ".join(result.next_actions).lower()
    assert "seven to eight hours" in actions
    assert "steps" in actions


def test_missing_metrics_are_not_invented():
    result = build_analysis(
        _request(type="PHYSICAL", metrics=[], patterns=[], comparison={})
    )
    assert result.recommendations
    # With no numbers at all the engine must still avoid fabricated targets.
    assert not any("steps" in action.lower() for action in result.next_actions)
    assert result.focus_areas == ["keeping your current balance"]


def test_llm_wording_with_digits_is_rejected():
    assert (
        _validate(
            {
                "narrative": "You slept 6 hours last night.",
                "recommendations": [
                    {
                        "id": "a",
                        "title": "Rest more",
                        "description": "Try to sleep longer.",
                        "category": "SLEEP",
                    }
                ],
            }
        )
        is None
    )


def test_llm_wording_with_medical_claim_is_rejected():
    assert (
        _validate(
            {
                "narrative": "This suggests you have a sleep disorder.",
                "recommendations": [
                    {
                        "id": "a",
                        "title": "Rest more",
                        "description": "Try a wind-down routine.",
                        "category": "SLEEP",
                    }
                ],
            }
        )
        is None
    )


def test_valid_llm_wording_is_accepted():
    result = _validate(
        {
            "narrative": "Your sleep and movement are drifting apart from your usual routine.",
            "recommendations": [
                {
                    "id": "Wind Down",
                    "title": "Keep a repeatable wind-down",
                    "description": "Dim the lights and put screens away at the same time each night.",
                    "category": "sleep",
                }
            ],
        }
    )
    assert result is not None
    assert result.generated_by == "llm"
    assert result.recommendations[0].id == "llm_wind_down"
    assert result.recommendations[0].category == "SLEEP"
