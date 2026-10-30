"""Tests for the physical-wellness insight recommendations.

The backend pattern engine owns detection; this service only phrases
already-validated patterns. These tests pin the safety properties: no invented
measurements, no restriction advice, attention-first ordering, and total
independence from any LLM.
"""

from app.core.wellness.physical_insights import recommend
from app.schemas.wellness import (
    CoverageInput,
    GoalInput,
    InsightPattern,
    PhysicalInsightRequest,
)


def _payload(
    patterns: list[InsightPattern] | None = None,
    existing: list[str] | None = None,
    activity_days: int = 10,
    sleep_days: int = 8,
) -> PhysicalInsightRequest:
    return PhysicalInsightRequest(
        window_days=14,
        coverage=CoverageInput(
            activity_days=activity_days,
            sleep_days=sleep_days,
            hydration_days=5,
            mood_checkins=6,
        ),
        patterns=patterns or [],
        existing_recommendations=existing or [],
        goals=GoalInput(hydration_target_ml=2000, sleep_target_minutes=480),
    )


def test_no_patterns_returns_general_grounding_only():
    response = recommend(_payload())

    assert len(response.recommendations) == 1
    rec = response.recommendations[0]
    assert rec.id == "general_grounding"
    assert rec.source == "AI_SERVICE"


def test_maps_detected_sleep_pattern_to_supportive_suggestion():
    response = recommend(
        _payload([InsightPattern(id="sleep_below_baseline", severity="ATTENTION")])
    )

    assert response.recommendations[0].id == "consistent_wind_down"
    assert response.recommendations[0].category == "SLEEP"


def test_attention_patterns_are_ordered_first():
    response = recommend(
        _payload(
            [
                InsightPattern(id="sleep_steady", severity="POSITIVE"),
                InsightPattern(id="activity_below_baseline", severity="ATTENTION"),
            ]
        )
    )

    assert response.recommendations[0].id == "light_movement"


def test_existing_rule_engine_recommendations_are_not_duplicated():
    response = recommend(
        _payload(
            [InsightPattern(id="sleep_below_baseline", severity="ATTENTION")],
            existing=["consistent_wind_down"],
        )
    )

    ids = [rec.id for rec in response.recommendations]
    assert "consistent_wind_down" not in ids
    # Still gives the user something rather than an empty list.
    assert ids


def test_recommendations_are_bounded():
    patterns = [
        InsightPattern(id=pattern_id, severity="ATTENTION")
        for pattern_id in [
            "sleep_below_baseline",
            "activity_below_baseline",
            "hydration_below_target",
            "mood_below_usual",
            "resting_hr_elevated",
        ]
    ]

    response = recommend(_payload(patterns))

    assert 1 <= len(response.recommendations) <= 3


def test_unknown_patterns_never_produce_guessed_advice():
    response = recommend(_payload([InsightPattern(id="made_up_pattern")]))

    assert [rec.id for rec in response.recommendations] == ["general_grounding"]


def test_no_restriction_or_diagnosis_language():
    patterns = [
        InsightPattern(id="sleep_below_baseline", severity="ATTENTION"),
        InsightPattern(id="mood_below_usual", severity="ATTENTION"),
        InsightPattern(id="hydration_below_target", severity="INFO"),
    ]
    response = recommend(_payload(patterns))

    text = " ".join(
        f"{rec.title} {rec.description}" for rec in response.recommendations
    ).lower()
    for banned in [
        "calorie",
        "cut back on food",
        "skip meals",
        "sleep restriction",
        "diagnose",
        "you have depression",
        "force yourself",
    ]:
        assert banned not in text
    # Supports seeking help without diagnosing.
    assert "professional" in text or "trust" in text


def test_sparse_coverage_is_disclosed():
    response = recommend(_payload(activity_days=0, sleep_days=0))

    assert response.note is not None
    assert "sparse" in response.note.lower()


def test_note_always_states_no_measurements_were_invented():
    response = recommend(_payload([InsightPattern(id="sleep_steady")]))

    assert response.note is not None
    assert "invented" in response.note.lower()


def test_request_schema_carries_no_identifiers_or_raw_text():
    fields = set(PhysicalInsightRequest.model_fields)
    assert fields == {
        "window_days",
        "coverage",
        "patterns",
        "existing_recommendations",
        "goals",
    }
    assert not any(
        banned in field.lower()
        for field in fields
        for banned in ("user", "device", "journal", "reading", "note")
    )


def test_http_endpoint_returns_structured_recommendations():
    from fastapi.testclient import TestClient

    from app.main import app

    client = TestClient(app)
    payload = {
        "window_days": 14,
        "coverage": {
            "activity_days": 9,
            "sleep_days": 7,
            "hydration_days": 4,
            "mood_checkins": 5,
        },
        "patterns": [
            {
                "id": "activity_below_baseline",
                "severity": "ATTENTION",
                "confidence": "MEDIUM",
                "summary": "Steps below baseline",
            }
        ],
        "existing_recommendations": [],
        "goals": {"hydration_target_ml": 2000, "sleep_target_minutes": 480},
    }

    response = client.post("/api/v1/wellness/physical-insights", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["recommendations"][0]["id"] == "light_movement"
    assert body["note"]


def test_http_endpoint_rejects_oversized_pattern_list():
    from fastapi.testclient import TestClient

    from app.main import app

    client = TestClient(app)
    payload = {
        "patterns": [
            {"id": f"p{i}", "severity": "INFO"} for i in range(25)
        ]
    }

    response = client.post("/api/v1/wellness/physical-insights", json=payload)

    assert response.status_code == 422
