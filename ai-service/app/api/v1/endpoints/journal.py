"""Journal text analysis endpoint.

Uses the existing NLP text analyzer for emotion/sentiment detection,
then generates a reflection prompt and emotional themes summary.
This is for personal reflection support — NOT clinical diagnosis.
"""

from fastapi import APIRouter, Depends

from app.core.mood.text_analyzer import get_text_analyzer
from app.core.ratelimit import rate_limited
from app.schemas.journal import JournalAnalysisRequest, JournalAnalysisResponse

router = APIRouter(dependencies=[Depends(rate_limited)])

# Emotion → reflection prompt templates
_REFLECTION_PROMPTS: dict[str, str] = {
    "joy": "You are experiencing joy. What brought this positive feeling today?",
    "sadness": "It seems you may be feeling low. Take a moment to acknowledge your feelings — they are valid.",
    "anger": "There may be some frustration or anger present. What triggered this emotion?",
    "fear": "Anxiety or worry appears to be present. What is weighing on your mind?",
    "surprise": "Something unexpected may have happened. How are you processing this?",
    "disgust": "There may be something troubling you deeply. What is on your mind?",
    "neutral": "Take a moment to reflect on your day. What stands out to you?",
    "unknown": "Reflect on how you are feeling right now. What is on your mind?",
}

# Emotion → emotional themes
_THEMES: dict[str, str] = {
    "joy": "happiness, gratitude, contentment",
    "sadness": "melancholy, loss, vulnerability",
    "anger": "frustration, irritation, conflict",
    "fear": "anxiety, worry, uncertainty",
    "surprise": "novelty, change, awareness",
    "disgust": "aversion, discomfort, boundaries",
    "neutral": "calm, balance, stability",
    "unknown": "reflection, self-awareness",
}


def _generate_reflection(emotion: str, sentiment: str, text: str) -> str:
    """Generate a context-aware reflection prompt."""
    base = _REFLECTION_PROMPTS.get(emotion, _REFLECTION_PROMPTS["unknown"])

    # Enhance with sentiment context
    if sentiment == "positive":
        return f"{base} You seem to be in a positive place right now."
    elif sentiment == "negative":
        return f"{base} Remember, it is okay to feel this way. Be gentle with yourself."
    return base


def _generate_summary(emotion: str, sentiment: str, themes: str, text: str) -> str:
    """Generate a concise summary of the journal entry's emotional content.
    Uses the detected signals to produce a brief, useful overview."""
    emotion_label = emotion.replace("_", " ")
    sentiment_label = sentiment.replace("_", " ")

    # Build a concise 1-2 sentence summary from the detected signals
    parts = []

    if sentiment_label == "positive":
        parts.append(f"This entry reflects a {emotion_label} tone")
    elif sentiment_label == "negative":
        parts.append(f"This entry reflects a {emotion_label} tone")
    else:
        parts.append(f"This entry has a {emotion_label} quality")

    if themes:
        parts.append(f"with themes of {themes}")

    # Add a brief contextual note based on entry length
    word_count = len(text.split())
    if word_count > 100:
        parts.append("in a detailed reflection")
    elif word_count > 30:
        parts.append("in a thoughtful reflection")
    else:
        parts.append("in a brief reflection")

    return ". ".join(parts) + "."


@router.post(
    "/analyze",
    summary="Analyze journal text for emotion and reflection",
    response_model=JournalAnalysisResponse,
)
async def analyze(payload: JournalAnalysisRequest):
    """Analyze journal text for emotion, sentiment, themes, and reflection prompt.

    Uses pretrained NLP models for emotion/sentiment detection.
    Results are for personal reflection support only — NOT clinical diagnosis.
    """
    analyzer = get_text_analyzer()
    result = analyzer.analyze(payload.text)

    emotion = result.get("emotion", "unknown")
    sentiment = result.get("sentiment", "neutral")
    emotion_confidence = result.get("emotion_confidence", 0.0)
    sentiment_confidence = result.get("sentiment_confidence", 0.0)

    # Generate themes, summary, and reflection
    themes = _THEMES.get(emotion, _THEMES["unknown"])
    summary = _generate_summary(emotion, sentiment, themes, payload.text)
    reflection = _generate_reflection(emotion, sentiment, payload.text)

    # If confidence is very low, mark as LOW_CONFIDENCE
    status = "COMPLETED"
    if emotion_confidence < 0.2 and sentiment_confidence < 0.2:
        status = "LOW_CONFIDENCE"

    return JournalAnalysisResponse(
        status=status,
        emotion=emotion,
        emotionConfidence=round(emotion_confidence, 4),
        sentiment=sentiment,
        sentimentConfidence=round(sentiment_confidence, 4),
        emotionalThemes=themes,
        summary=summary,
        reflectionPrompt=reflection,
    )
