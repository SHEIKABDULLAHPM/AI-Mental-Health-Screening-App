from fastapi import APIRouter, Depends, HTTPException

from app.core.rag import QdrantVectorStore
from app.core.ratelimit import rate_limited
from app.schemas.models import RAGQueryRequest

router = APIRouter(dependencies=[Depends(rate_limited)])
_store = None


def _get_store() -> QdrantVectorStore:
    global _store
    if _store is None:
        _store = QdrantVectorStore()  # may raise if Qdrant is down
    return _store


@router.post("/retrieve", summary="Retrieve evidence chunks by query")
async def retrieve(payload: RAGQueryRequest):
    try:
        chunks = _get_store().search(payload.query, top_k=5)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {"query": payload.query, "chunks": chunks}