from typing import Any, Dict


class AIError(Exception):
    """Base error surfaced by the AI service."""

    status_code = 500
    code = "AI_ERROR"

    def __init__(self, message: str, details: Dict[str, Any] | None = None):
        super().__init__(message)
        self.message = message
        self.details = details or {}

    def to_dict(self) -> Dict[str, Any]:
        return {"code": self.code, "message": self.message, "details": self.details}


class LLMError(AIError):
    status_code = 502
    code = "LLM_UNAVAILABLE"


class EmbeddingError(AIError):
    status_code = 500
    code = "EMBEDDING_FAILED"


class RAGSearchError(AIError):
    status_code = 500
    code = "RAG_SEARCH_FAILED"