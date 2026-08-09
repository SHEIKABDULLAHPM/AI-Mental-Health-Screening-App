from fastapi import APIRouter

from app.schemas.models import ScreeningRequest
from app.services.ai_router import ai_router

router = APIRouter()


@router.post("/analyze", summary="Analyze a completed screening")
async def analyze(payload: ScreeningRequest):
    result = await ai_router.analyze_screening(
        {
            "scores": {"phq9": float(sum(payload.answers.values()))},
            "contextual_flags": [],
        }
    )
    return {"user_id": payload.user_id, "questionnaire_type": payload.questionnaire_type, "result": result}