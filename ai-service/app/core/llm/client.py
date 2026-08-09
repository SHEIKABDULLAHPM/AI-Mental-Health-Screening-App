"""LLM abstraction. Provider-agnostic to ease swapping OpenAI / local models."""
import abc


class LLMClient(abc.ABC):
    """Minimal contract for text-generation backends."""

    @abc.abstractmethod
    async def complete(self, system: str, user: str, *, max_tokens: int = 512) -> str:
        ...

    @abc.abstractmethod
    async def is_available(self) -> bool:
        ...