"""Coach safety classification and wellness knowledge endpoints.

Safety classification uses keyword/pattern detection for fast, reliable screening.
Wellness RAG provides grounded knowledge from trusted sources.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.ratelimit import rate_limited
from app.schemas.coach import (
    SafetyClassificationRequest,
    SafetyClassificationResponse,
    WellnessRAGRequest,
    WellnessRAGResponse,
)

router = APIRouter(dependencies=[Depends(rate_limited)])

# ── Safety keyword sets ──────────────────────────────────────────────

_IMMEDIATE_DANGER = {
    "kill myself", "end my life", "suicide", "suicidal",
    "want to die", "going to die", "end it all",
    "hang myself", "overdose", "jump off",
    "cut my wrists", "slit my wrists", "no reason to live",
}

_HIGH_RISK = {
    "self harm", "self-harm", "hurt myself", "harm myself",
    "cut myself", "burn myself", "starve myself",
    "not worth living", "better off dead", "nobody would care",
    "can't go on", "can't take it anymore",
}

_CONCERNING = {
    "hopeless", "worthless", "helpless", "trapped",
    "no way out", "give up on life",
    "tired of living", "don't want to be here",
    "numb inside", "empty inside", "lost all hope",
}

# ── Wellness knowledge base (curated, trusted content) ───────────────

_WELLNESS_KNOWLEDGE: list[dict[str, str]] = [
    {
        "content": "Deep breathing exercises can help manage acute stress. Try the 4-7-8 technique: breathe in for 4 seconds, hold for 7, exhale for 8. Repeat 3-4 cycles.",
        "topic": "stress_management",
    },
    {
        "content": "Progressive muscle relaxation involves tensing and releasing each muscle group for 5-10 seconds. Start from your toes and work up to your head. This helps release physical tension associated with anxiety.",
        "topic": "anxiety_management",
    },
    {
        "content": "The 5-4-3-2-1 grounding technique helps during moments of anxiety: notice 5 things you see, 4 you can touch, 3 you hear, 2 you smell, and 1 you taste.",
        "topic": "grounding",
    },
    {
        "content": "Sleep hygiene tips: maintain a consistent sleep schedule, avoid screens 30 minutes before bed, keep your room cool and dark, limit caffeine after 2pm, and try a wind-down routine.",
        "topic": "sleep",
    },
    {
        "content": "Regular physical activity can improve mood and reduce anxiety. Even 10-15 minutes of walking can boost endorphins. Start small and build gradually.",
        "topic": "physical_activity",
    },
    {
        "content": "Mindfulness meditation involves focusing on the present moment without judgment. Start with 5 minutes daily, focusing on your breath. Apps and guided sessions can help beginners.",
        "topic": "mindfulness",
    },
    {
        "content": "Social connection is important for mental health. Even brief, positive interactions can improve wellbeing. Consider reaching out to a friend or family member, even with a short message.",
        "topic": "social_connection",
    },
    {
        "content": "Journaling can help process emotions. Try writing about your thoughts and feelings for 10-15 minutes. There are no rules — just write freely about what's on your mind.",
        "topic": "journaling",
    },
    {
        "content": "Setting small, achievable goals can help combat feelings of overwhelm. Break larger tasks into tiny steps and celebrate completing each one, no matter how small.",
        "topic": "goal_setting",
    },
    {
        "content": "Self-compassion involves treating yourself with the same kindness you would offer a friend. When you're struggling, acknowledge your pain without judgment and remind yourself that difficulty is part of being human.",
        "topic": "self_compassion",
    },
    {
        "content": "If you're feeling overwhelmed, try the STOP technique: Stop what you're doing, Take a breath, Observe your thoughts and feelings, Proceed with awareness.",
        "topic": "crisis_coping",
    },
    {
        "content": "Healthy boundaries help protect your mental energy. It's okay to say no to requests that drain you. Prioritizing your wellbeing is not selfish — it's necessary.",
        "topic": "boundaries",
    },
]


def _classify_safety(message: str) -> SafetyClassificationResponse:
    """Classify a message for safety concerns using keyword matching."""
    lower = message.lower().strip()
    keywords_matched: list[str] = []

    for kw in _IMMEDIATE_DANGER:
        if kw in lower:
            keywords_matched.append(kw)
            return SafetyClassificationResponse(
                state="IMMEDIATE_DANGER",
                confidence=0.95,
                keywords_matched=keywords_matched,
            )

    for kw in _HIGH_RISK:
        if kw in lower:
            keywords_matched.append(kw)
            return SafetyClassificationResponse(
                state="HIGH_RISK",
                confidence=0.85,
                keywords_matched=keywords_matched,
            )

    for kw in _CONCERNING:
        if kw in lower:
            keywords_matched.append(kw)

    if keywords_matched:
        return SafetyClassificationResponse(
            state="CONCERNING",
            confidence=0.70,
            keywords_matched=keywords_matched,
        )

    return SafetyClassificationResponse(
        state="NORMAL",
        confidence=0.90,
        keywords_matched=[],
    )


def _retrieve_wellness_knowledge(query: str, top_k: int = 3) -> WellnessRAGResponse:
    """Simple keyword-based wellness knowledge retrieval.

    In production, this would use vector similarity search with embeddings.
    For now, we use keyword matching against curated trusted content.
    """
    lower = query.lower()
    scored: list[tuple[float, dict[str, str]]] = []

    for entry in _WELLNESS_KNOWLEDGE:
        score = 0.0
        topic_words = entry["topic"].replace("_", " ").split()
        content_words = entry["content"].lower().split()

        for word in topic_words:
            if word in lower:
                score += 2.0

        for word in lower.split():
            if len(word) > 3 and word in " ".join(content_words):
                score += 0.5

        if score > 0:
            scored.append((score, entry))

    scored.sort(key=lambda x: x[0], reverse=True)
    top_results = scored[:top_k]

    if not top_results:
        # Return generic wellness content as fallback
        fallback = _WELLNESS_KNOWLEDGE[:top_k]
        return WellnessRAGResponse(
            query=query,
            chunks=[e["content"] for e in fallback],
            sources=[e["topic"] for e in fallback],
            relevance_threshold_met=False,
        )

    return WellnessRAGResponse(
        query=query,
        chunks=[e["content"] for _, e in top_results],
        sources=[e["topic"] for _, e in top_results],
        relevance_threshold_met=True,
    )


@router.post(
    "/safety/classify",
    summary="Classify user message for safety concerns",
    response_model=SafetyClassificationResponse,
)
async def classify_safety(payload: SafetyClassificationRequest):
    """Classify a user message for safety concerns (self-harm, crisis, etc.).

    Returns a safety state: NORMAL, CONCERNING, HIGH_RISK, or IMMEDIATE_DANGER.
    """
    return _classify_safety(payload.message)


@router.post(
    "/wellness/retrieve",
    summary="Retrieve wellness knowledge relevant to a query",
    response_model=WellnessRAGResponse,
)
async def retrieve_wellness_knowledge(payload: WellnessRAGRequest):
    """Retrieve trusted wellness knowledge relevant to the user's query.

    Uses keyword matching against curated content. Returns chunks with
    relevance scores and source topics.
    """
    return _retrieve_wellness_knowledge(payload.query, payload.top_k)
