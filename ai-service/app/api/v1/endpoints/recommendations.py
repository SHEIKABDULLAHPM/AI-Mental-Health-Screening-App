from fastapi import APIRouter

from app.core.recommendation import FallbackRecommender
from app.schemas.models import RecommendationRequest

router = APIRouter()


@router.post("/generate", summary="Generate supportive guidance")
async def generate(payload: RecommendationRequest):
    recommender = FallbackRecommender()
    return recommender.recommend(payload.user_context, payload.evidence_chunks)