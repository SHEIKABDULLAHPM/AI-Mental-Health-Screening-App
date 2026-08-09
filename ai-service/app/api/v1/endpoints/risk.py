from fastapi import APIRouter

from app.core.risk import HeuristicRiskAssessor
from app.schemas.models import RiskRequest

router = APIRouter()


@router.post("/assess", summary="Assess clinical risk level")
async def assess(payload: RiskRequest):
    assessor = HeuristicRiskAssessor()
    return await assessor.assess(payload.screening_score, payload.contextual_flags)