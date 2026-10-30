"""Versioned prompt construction for screening insight generation.

The prompt receives only anonymized deterministic scores (never raw answers
or personal identifiers) plus grounded evidence chunks. A version tag is
embedded so prompt changes are auditable and reproducible.
"""
from app.config import settings
from app.schemas.job import ScreeningScoresInput

SYSTEM_PROMPT = """You are MindEase, an empathic mental-wellbeing guide embedded in a screening app.

Your job: turn a completed, deterministic wellbeing analysis into a short,
human insight the user reads right after screening. You are NOT a doctor and
must never diagnose, judge, or alarm. Frame everything as gentle guidance.

Rules:
- Speak directly to the user using "you".
- Be warm, concrete and actionable (1-3 small suggestions tied to the focus).
- Never mention scores as numbers. Describe tendencies in plain language.
- Always close with one reassurance sentence.
- The primary focus and all metrics are authoritative - never contradict them.
- When onboarding mood context is provided, acknowledge it briefly in plain
  language (the self-reported mood is primary; trends are background only).
  When it is absent, never invent mood history or trends.
- When a camera signal is provided, mention it at most briefly as supporting
  context (it is never proof of a mental state and never overrides the
  self-report). When absent, never invent camera data.
- Use only the provided trusted evidence to support suggestions.
"""


def _scores_block(scores: ScreeningScoresInput) -> str:
    return (
        "Deterministic analysis (authoritative, never contradict):\n"
        f"- PHQ-9 total: {scores.phq9} / 27\n"
        f"- GAD-7 total: {scores.gad7} / 21\n"
        f"- PSS-10 total: {scores.pss10} / 40\n"
        f"- WHO-5 total: {scores.who5} / 25 (wellbeing percent {scores.who_percent}%)\n"
        f"- Composite wellness score: {scores.wellnessScore} / 100\n"
        f"- Stress level: {scores.stressLevel}\n"
        f"- Lifestyle score: {scores.lifestyleScore} / 100\n"
        f"- Sleep quality: {scores.sleepQuality}\n"
        f"- Primary focus: {scores.primaryFocus}"
    )


def _evidence_block(evidence: list[str]) -> str:
    if not evidence:
        return "Trusted evidence: (none provided - rely on general wellbeing guidance)."
    lines = "\n".join(f"- {chunk}" for chunk in evidence)
    return f"Trusted evidence you may draw from:\n{lines}"


_MOOD_LABELS = {
    "very_happy": "a very positive current mood",
    "happy": "a positive current mood",
    "calm": "a calm current mood",
    "okay": "a neutral current mood",
    "low": "a low current mood",
    "stressed": "a stressed current mood",
}

_TREND_LABELS = {
    "improving": "trending upward compared with their own recent check-ins",
    "declining": "trending downward compared with their own recent check-ins",
    "stable": "fairly consistent compared with their own recent check-ins",
    "fluctuating": "varying quite a bit across recent check-ins",
}


_CAMERA_LABELS = {
    "anger": "anger",
    "disgust": "disgust",
    "fear": "fear",
    "happy": "happiness",
    "neutral": "a neutral expression",
    "sad": "sadness",
    "surprise": "surprise",
}

_AGREEMENT_LABELS = {
    "agree": "which lines up with what they reported",
    "close": "which is close to what they reported",
    "differs": "which differs from what they reported - the self-report stays primary",
}


def _camera_block(scores: ScreeningScoresInput) -> str:
    """Qualitative camera supporting signal. Only structured, server-derived
    data is rendered (emotion label, qualitative confidence band, agreement
    verdict) — never raw frames, never numbers, never a diagnosis."""
    emotion = (scores.cameraEmotion or "").strip().lower()
    agreement = (scores.signalAgreement or "").strip().lower()
    if not emotion or emotion == "unknown" or agreement in ("", "nosignal"):
        return ""
    label = _CAMERA_LABELS.get(emotion, emotion)
    parts = [f"- A brief camera check-in detected {label}"]
    conf = scores.cameraConfidence
    if conf is not None:
        band = (
            "with high confidence"
            if conf >= 0.7
            else "with moderate confidence"
            if conf >= 0.4
            else "but with low confidence"
        )
        parts[0] = f"{parts[0]} {band}"
    verdict = _AGREEMENT_LABELS.get(agreement)
    if verdict:
        parts.append(f"  ({verdict}).")
    parts.append(
        "Treat this as background context only: facial expression is not "
        "proof of a mental state and never overrides the self-report."
    )
    return "\n".join(parts)


def _mood_block(scores: ScreeningScoresInput) -> str:
    """Qualitative mood context for the LLM. Never emits numeric scores and
    never invents history: when no trend/history is available the block says
    so plainly instead of guessing."""
    if not scores.has_mood_context:
        return "Onboarding mood: (not provided)."
    mood_id = (scores.onboardingMood or "").strip()
    mood_phrase = _MOOD_LABELS.get(mood_id, "their current mood as reported")
    parts = [f"- The user reported {mood_phrase} during onboarding."]
    if scores.onboardingMoodEmotion and scores.onboardingMoodEmotion.strip():
        parts.append(f"- They described feeling '{scores.onboardingMoodEmotion.strip()}'.")
    direction = (scores.moodTrendDirection or "").strip().lower()
    count = scores.moodHistoryCount or 0
    if direction and direction != "unknown" and count >= 3:
        trend_phrase = _TREND_LABELS.get(direction, direction)
        parts.append(
            f"- Their own recent check-ins ({count} entries) suggest mood has been "
            f"{trend_phrase}. Treat this as background context, not a diagnosis."
        )
    elif count and count > 0:
        parts.append(
            "- There are only a few previous check-ins, so no reliable mood "
            "trend can be inferred yet."
        )
    else:
        parts.append("- No previous mood check-in history is available.")
    parts.append(
        "- The self-reported mood above is the primary signal; any trend is "
        "supporting context only."
    )
    if scores.moodTrendDescription and direction and direction != "unknown" and count >= 3:
        parts.append(f"- Trend note: {scores.moodTrendDescription.strip()}")
    return "Onboarding mood context (authoritative, never contradict):\n" + "\n".join(parts)


def build_screening_prompt(
    scores: ScreeningScoresInput, evidence: list[str]
) -> tuple[str, str]:
    """Returns (system, user) prompt for the structured insight generation."""
    mood_block = _mood_block(scores)
    camera_block = _camera_block(scores)
    if camera_block:
        mood_block = f"{mood_block}\n{camera_block}"
    user = (
        f"Prompt version: {settings.prompt_version}\n\n"
        f"{_scores_block(scores)}\n\n"
        f"{mood_block}\n\n"
        f"{_evidence_block(evidence)}\n\n"
        "Write the aiInsight field now, keeping the primary focus "
        f"(\"{scores.primaryFocus}\") at the heart of your suggestions. "
        "Where onboarding mood context is available, acknowledge it briefly "
        "in plain language without repeating any numbers."
    )
    return SYSTEM_PROMPT, user
