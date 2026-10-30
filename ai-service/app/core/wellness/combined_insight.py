"""Combined mental + physical wellbeing insight.

The endpoint receives anonymised aggregates only: the deterministic mental
profile scores and the physical pattern-engine coverage. It returns one short
reflection that connects the two, plus small suggestions.

Design guarantees:
* the LLM is optional - a deterministic composer always produces grounded text;
* the LLM never sees journal text, identifiers, raw readings or notes;
* output is validated: no diagnosis/medication language and no number that was
  not supplied in the input;
* the PHQ-9 item-9 escalation is appended deterministically and is never
  delegated to a model.
"""

from __future__ import annotations

import re
from typing import Any

from app.core.llm.client import LLMClient, build_llm_client
from app.logging import get_logger
from app.schemas.wellness import (
    CombinedInsightRequest,
    CombinedInsightResponse,
    CombinedSuggestion,
)

log = get_logger(__name__)

_MAX_NARRATIVE = 1200
_MIN_NARRATIVE = 60
_BANNED_TERMS = (
    "diagnos",
    "prescrib",
    "medication",
    "dosage",
    "disorder",
    "you have depression",
    "you have anxiety",
    "cure",
)
_SAFETY_REASON = (
    "Because one of your answers mentioned thoughts of self-harm, please reach "
    "out to someone you trust today."
)
_SAFETY_OUTREACH = "Please reach out to someone you trust today."
_SAFETY_CRISIS = (
    "If you are in immediate danger, contact your local emergency number or a "
    "crisis service now."
)
_SAFETY_NOTE = f"{_SAFETY_REASON} {_SAFETY_CRISIS}"
_NOTE = (
    "Combines your own stored mental check-in with aggregated physical data. "
    "No measurement was invented and this is not a diagnosis."
)

_FOCUS_LABELS = {
    "STRESS_MANAGEMENT": "managing stress",
    "SLEEP": "restoring sleep",
    "MOOD_SUPPORT": "supporting your mood",
    "BALANCE": "keeping a balanced routine",
}
_STRESS_LABELS = {
    "LOW": "low",
    "MODERATE": "moderate",
    "HIGH": "high",
}
_SLEEP_LABELS = {
    "GOOD": "good",
    "FAIR": "fair",
    "POOR": "poor",
}
_PATTERN_LABELS = {
    "sleep_below_baseline": "sleep running below your own baseline",
    "activity_below_baseline": "activity running below your own baseline",
    "hydration_below_target": "hydration below your usual target",
    "mood_below_usual": "mood below your usual range",
    "mood_sleep_cooccurrence": "mood and sleep changing together",
    "resting_hr_elevated": "resting heart rate above your usual range",
    "hrv_below_baseline": "HRV below your usual baseline",
    "sleep_steady": "steady sleep",
    "no_pattern_detected": "no clear pattern yet",
}

_SUGGESTION_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "narrative": {"type": "STRING"},
        "suggestions": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "title": {"type": "STRING"},
                    "description": {"type": "STRING"},
                    "category": {"type": "STRING"},
                },
                "required": ["title", "description"],
            },
        },
    },
    "required": ["narrative", "suggestions"],
}

_SYSTEM_PROMPT = """You are Synora's wellbeing guide. Write one short reflection that connects a user's completed mental check-in with their own recent physical signals.

Rules:
- Use ONLY the aggregates supplied below. Never invent measurements, symptoms, history, or events.
- Never diagnose, never imply that one factor caused another, and never mention medication.
- Never claim when a mood, symptom or reading was recorded, and never call a stored value "today's".
- Do not restate questionnaire scores as numbers; you may mention how many days had data.
- Warm, plain language. The narrative must be 90-700 characters.
- Offer 2 or 3 small, low-risk suggestions. No calorie restriction, sleep restriction, fluid loading, or exercise targets.
- When safety_flag is true, explicitly encourage reaching out to a trusted person or a professional now.
- End with one reassurance that this is guidance, not a diagnosis.
"""


def _deterministic_narrative(payload: CombinedInsightRequest) -> str:
    mental = payload.mental
    physical = payload.physical
    focus = _FOCUS_LABELS.get(mental.primary_focus, "your overall wellbeing")
    stress = _STRESS_LABELS.get(mental.stress_level, "your reported")
    sleep = _SLEEP_LABELS.get(mental.sleep_quality, "your reported")
    coverage = physical.coverage

    parts = [
        f"Your recent check-in points to {stress} stress with {focus} as the main focus, "
        f"and your reported sleep quality is {sleep}.",
    ]
    if physical.sufficient_data:
        parts.append(
            f"Over the last {physical.window_days} days you logged activity on "
            f"{coverage.activity_days} days, sleep on {coverage.sleep_days} nights, "
            f"hydration on {coverage.hydration_days} days and {coverage.mood_checkins} "
            f"mood check-in(s)."
        )
        if physical.pattern_ids:
            labels = [
                _PATTERN_LABELS.get(pattern_id, pattern_id.replace("_", " "))
                for pattern_id in physical.pattern_ids[:3]
            ]
            parts.append("What stands out from your own data: " + ", ".join(labels) + ".")
    else:
        parts.append(
            f"There is not enough recent physical data yet to describe a mind-body "
            f"pattern: activity on {coverage.activity_days} of the last "
            f"{physical.window_days} days and sleep on {coverage.sleep_days} nights."
        )
    parts.append(
        "Small, repeatable habits are a reasonable next step, and gentle consistency "
        "matters more than any single day. This is guidance, not a diagnosis."
    )
    return " ".join(parts)


def _fallback_suggestions(payload: CombinedInsightRequest) -> list[CombinedSuggestion]:
    if payload.physical.suggestions:
        return [
            CombinedSuggestion(
                title=item.title,
                description=item.description,
                category=item.category,
            )
            for item in payload.physical.suggestions[:3]
        ]
    return [
        CombinedSuggestion(
            title="A brief grounding pause",
            description=(
                "When you have a moment, try five slow breaths and notice what you "
                "can see, hear and feel. Keep logging so patterns can emerge."
            ),
            category="MINDFULNESS",
        )
    ]


def _allowed_numbers(payload: CombinedInsightRequest) -> set[str]:
    coverage = payload.physical.coverage
    return {
        str(payload.physical.window_days),
        str(coverage.activity_days),
        str(coverage.sleep_days),
        str(coverage.hydration_days),
        str(coverage.mood_checkins),
    }


def _numbers_are_grounded(text: str, allowed: set[str]) -> bool:
    return all(number in allowed for number in re.findall(r"\d+", text))


def _validate_llm_output(
    raw: dict[str, Any], payload: CombinedInsightRequest
) -> CombinedInsightResponse | None:
    narrative = str(raw.get("narrative") or "").strip()
    lowered = narrative.lower()
    if not (_MIN_NARRATIVE <= len(narrative) <= _MAX_NARRATIVE):
        return None
    # "This is guidance, not a diagnosis" is the required reassurance; strip
    # only that exact negation before checking for diagnostic claims.
    screened = lowered.replace("not a medical diagnosis", "").replace(
        "not a diagnosis", ""
    )
    if any(term in screened for term in _BANNED_TERMS):
        return None
    if not _numbers_are_grounded(narrative, _allowed_numbers(payload)):
        return None

    suggestions: list[CombinedSuggestion] = []
    for item in raw.get("suggestions") or []:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "").strip()
        description = str(item.get("description") or "").strip()
        category = str(item.get("category") or "WELLNESS").strip().upper()
        if not title or not description or len(title) > 120 or len(description) > 600:
            continue
        text = f"{title} {description}".lower()
        if any(term in text for term in _BANNED_TERMS):
            continue
        if not _numbers_are_grounded(f"{title} {description}", _allowed_numbers(payload)):
            continue
        suggestions.append(
            CombinedSuggestion(
                title=title,
                description=description,
                category=category[:32],
            )
        )
        if len(suggestions) >= 3:
            break

    if not suggestions:
        return None

    return CombinedInsightResponse(
        narrative=narrative,
        suggestions=suggestions,
        generated_by="llm",
        note=_NOTE,
    )


def _user_block(payload: CombinedInsightRequest) -> str:
    mental = payload.mental
    physical = payload.physical
    coverage = physical.coverage
    return (
        "Mental check-in (authoritative):\n"
        f"- wellness score: {mental.wellness_score}/100\n"
        f"- stress level: {mental.stress_level}\n"
        f"- lifestyle score: {mental.lifestyle_score}/100\n"
        f"- sleep quality: {mental.sleep_quality}\n"
        f"- primary focus: {mental.primary_focus}\n"
        f"- safety_flag: {str(mental.safety_flag).lower()}\n"
        "\n"
        "Physical aggregates (authoritative):\n"
        f"- window: {physical.window_days} days\n"
        f"- activity days: {coverage.activity_days}\n"
        f"- sleep nights: {coverage.sleep_days}\n"
        f"- hydration days: {coverage.hydration_days}\n"
        f"- mood check-ins: {coverage.mood_checkins}\n"
        f"- sufficient data for a pattern: {str(physical.sufficient_data).lower()}\n"
        f"- detected pattern ids: {', '.join(physical.pattern_ids) or 'none'}\n"
        f"- existing safe suggestions: "
        f"{'; '.join(item.title for item in physical.suggestions) or 'none'}\n"
    )


def _apply_safety(
    response: CombinedInsightResponse, payload: CombinedInsightRequest
) -> CombinedInsightResponse:
    if not payload.mental.safety_flag:
        return response
    narrative = response.narrative
    lower = narrative.lower()
    mentions_cause = any(
        term in lower
        for term in ("self-harm", "self harm", "harming yourself", "suicid")
    )
    advises_outreach = any(
        term in lower
        for term in ("reach out", "someone you trust", "trusted person",
                     "crisis", "emergency")
    )
    has_crisis_line = any(
        term in lower
        for term in ("emergency number", "crisis service", "crisis line",
                     "helpline")
    )
    additions = []
    if not advises_outreach:
        # Keep the actionable request even if the model already named the
        # cause; repeat the cause only when the model did not name it.
        additions.append(_SAFETY_OUTREACH if mentions_cause else _SAFETY_REASON)
    if not has_crisis_line:
        additions.append(_SAFETY_CRISIS)
    if additions:
        narrative = f"{narrative} {' '.join(additions)}"
    suggestions = list(response.suggestions)
    if not any("trust" in item.description.lower() for item in suggestions):
        suggestions = [
            CombinedSuggestion(
                title="Reach out today",
                description=(
                    "Tell someone you trust how you are feeling, or contact a local "
                    "crisis service. You do not have to carry this alone."
                ),
                category="SUPPORT",
            ),
            *suggestions,
        ][:3]
    return CombinedInsightResponse(
        narrative=narrative,
        suggestions=suggestions,
        generated_by=response.generated_by,
        note=response.note,
    )


def deterministic_insight(payload: CombinedInsightRequest) -> CombinedInsightResponse:
    return _apply_safety(
        CombinedInsightResponse(
            narrative=_deterministic_narrative(payload),
            suggestions=_fallback_suggestions(payload),
            generated_by="rules",
            note=_NOTE,
        ),
        payload,
    )


async def generate_insight(
    payload: CombinedInsightRequest, llm: LLMClient | None = None
) -> CombinedInsightResponse:
    """LLM narrative when available, deterministic grounded text otherwise."""

    fallback = deterministic_insight(payload)
    client = llm
    if client is None:
        try:
            client = build_llm_client()
        except Exception:  # noqa: BLE001
            return fallback

    try:
        if not await client.is_available():
            return fallback
        raw = await client.complete_json(
            _SYSTEM_PROMPT,
            _user_block(payload),
            _SUGGESTION_SCHEMA,
            max_tokens=900,
        )
        validated = _validate_llm_output(raw, payload)
        if validated is None:
            log.warning("combined_insight_validation_fallback")
            return fallback
        return _apply_safety(validated, payload)
    except Exception as exc:  # noqa: BLE001
        log.warning("combined_insight_llm_unavailable", error=str(exc)[:200])
        return fallback
