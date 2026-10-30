from fastapi import APIRouter

from app.api.v1.endpoints import (
    analysis,
    coach,
    journal,
    mood,
    rag,
    recommendations,
    risk,
    screening,
    wellness,
)

api_router = APIRouter()
api_router.include_router(screening.router, prefix="/screening", tags=["screening"])
api_router.include_router(mood.router, prefix="/mood", tags=["mood"])
api_router.include_router(journal.router, prefix="/journal", tags=["journal"])
api_router.include_router(risk.router, prefix="/risk", tags=["risk"])
api_router.include_router(rag.router, prefix="/rag", tags=["rag"])
api_router.include_router(recommendations.router, prefix="/recommendations", tags=["recommendations"])
api_router.include_router(coach.router, prefix="/coach", tags=["coach"])
api_router.include_router(wellness.router, prefix="/wellness", tags=["wellness"])
api_router.include_router(analysis.router, prefix="/analysis", tags=["analysis"])