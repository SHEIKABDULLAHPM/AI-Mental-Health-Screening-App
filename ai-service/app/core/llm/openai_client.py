"""OpenAI-backed LLM implementation."""
from openai import AsyncOpenAI

from app.config import settings
from app.core.llm.client import LLMClient
from app.errors import LLMError
from app.logging import get_logger

log = get_logger(__name__)


class OpenAILLMClient(LLMClient):
    def __init__(self) -> None:
        self._client = AsyncOpenAI(api_key=settings.openai_api_key)
        self._model = settings.openai_model

    async def complete(self, system: str, user: str, *, max_tokens: int = 512) -> str:
        try:
            response = await self._client.chat.completions.create(
                model=self._model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                max_tokens=max_tokens,
                temperature=0.4,
            )
            return (response.choices[0].message.content or "").strip()
        except Exception as exc:  # noqa: BLE001
            log.error("llm_complete_failed", error=str(exc))
            raise LLMError(f"LLM call failed: {exc}") from exc

    async def is_available(self) -> bool:
        try:
            await self._client.models.retrieve(self._model)
            return True
        except Exception:  # noqa: BLE001
            return False


def build_llm_client() -> LLMClient:
    if not settings.openai_api_key or settings.openai_api_key.startswith("sk-change"):
        return OpenAILLMClient()  # still returns error responses if unset
    return OpenAILLMClient()