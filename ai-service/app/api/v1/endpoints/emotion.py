from fastapi import APIRouter, Depends

from app.core.emotion import RuleBasedEmotionEngine
from app.core.ratelimit import rate_limited
from app.schemas.models import EmotionRequest

router = APIRouter(dependencies=[Depends(rate_limited)])


@router.post("/analyze", summary="Detect emotion from free text")
async def analyze(payload: EmotionRequest):
    engine = RuleBasedEmotionEngine()
    return await engine.analyze(payload.text)