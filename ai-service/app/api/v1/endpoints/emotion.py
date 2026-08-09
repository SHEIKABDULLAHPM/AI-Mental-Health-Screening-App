from fastapi import APIRouter

from app.core.emotion import RuleBasedEmotionEngine
from app.schemas.models import EmotionRequest

router = APIRouter()


@router.post("/analyze", summary="Detect emotion from free text")
async def analyze(payload: EmotionRequest):
    engine = RuleBasedEmotionEngine()
    return await engine.analyze(payload.text)