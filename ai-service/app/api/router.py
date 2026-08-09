from fastapi import APIRouter

from app.api.v1.endpoints import emotion, rag, recommendations, risk, screening

api_router = APIRouter()
api_router.include_router(screening.router, prefix="/screening", tags=["screening"])
api_router.include_router(emotion.router, prefix="/emotion", tags=["emotion"])
api_router.include_router(risk.router, prefix="/risk", tags=["risk"])
api_router.include_router(rag.router, prefix="/rag", tags=["rag"])
api_router.include_router(recommendations.router, prefix="/recommendations", tags=["recommendations"])