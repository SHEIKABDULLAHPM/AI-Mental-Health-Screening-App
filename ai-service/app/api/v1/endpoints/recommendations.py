from fastapi import APIRouter, Depends

from app.core.ratelimit import rate_limited
from app.core.recommendation import FallbackRecommender
from app.schemas.models import RecommendationRequest

router = APIRouter(dependencies=[Depends(rate_limited)])


@router.post("/generate", summary="Generate supportive guidance")
async def generate(payload: RecommendationRequest):
    recommender = FallbackRecommender()
    return recommender.recommend(payload.user_context, payload.evidence_chunks)