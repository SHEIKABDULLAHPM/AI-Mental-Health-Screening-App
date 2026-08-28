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


def build_screening_prompt(
    scores: ScreeningScoresInput, evidence: list[str]
) -> tuple[str, str]:
    """Returns (system, user) prompt for the structured insight generation."""
    user = (
        f"Prompt version: {settings.prompt_version}\n\n"
        f"{_scores_block(scores)}\n\n"
        f"{_evidence_block(evidence)}\n\n"
        "Write the aiInsight field now, keeping the primary focus "
        f"(\"{scores.primaryFocus}\") at the heart of your suggestions."
    )
    return SYSTEM_PROMPT, user
