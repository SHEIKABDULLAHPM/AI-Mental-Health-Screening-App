"""LLM abstraction. Provider-agnostic to ease swapping Gemini / OpenAI models."""
import abc
from typing import Any

from app.config import settings


class LLMClient(abc.ABC):
    """Minimal contract for text-generation backends."""

    @abc.abstractmethod
    async def complete(self, system: str, user: str, *, max_tokens: int = 512) -> str:
        ...

    @abc.abstractmethod
    async def complete_json(
        self, system: str, user: str, schema: dict[str, Any], *, max_tokens: int = 1024
    ) -> dict[str, Any]:
        """Returns a JSON object conforming to `schema` (provider enforces it)."""
        ...

    @abc.abstractmethod
    async def is_available(self) -> bool:
        ...


def build_llm_client() -> LLMClient:
    from app.core.llm.gemini_client import GeminiLLMClient
    from app.core.llm.openai_client import OpenAILLMClient

    if settings.llm_provider.lower() == "openai":
        return OpenAILLMClient()
    return GeminiLLMClient()
