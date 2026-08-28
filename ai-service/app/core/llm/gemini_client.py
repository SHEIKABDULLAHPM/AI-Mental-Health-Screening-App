"""Gemini-backed LLM implementation using the public REST API.

Uses the v1beta `generateContent` endpoint with `responseMimeType:
application/json` and an inline `responseSchema` so the model returns
structured JSON that is then strictly validated by the caller.
"""
import asyncio
import json
from typing import Any

import httpx

from app.config import settings
from app.core.llm.client import LLMClient
from app.errors import LLMError
from app.logging import get_logger

log = get_logger(__name__)

_GENERATE_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
)


class GeminiLLMClient(LLMClient):
    def __init__(self) -> None:
        if not settings.gemini_api_key:
            log.warning("gemini_api_key_unset")
        self._api_key = settings.gemini_api_key
        self._model = settings.gemini_model
        self._timeout = httpx.Timeout(60.0, connect=10.0)

    def _url(self) -> str:
        return _GENERATE_URL.format(model=self._model)

    def _headers(self) -> dict[str, str]:
        return {"x-goog-api-key": self._api_key}

    async def _generate(self, system: str, user: str, *,
                        max_tokens: int, schema: dict[str, Any] | None) -> str:
        if not self._api_key:
            raise LLMError("GEMINI_API_KEY is not configured on the AI service.")

        generation_config: dict[str, Any] = {
            "temperature": 0.3,
            "maxOutputTokens": max_tokens,
            "thinkingConfig": {"thinkingBudget": 0},
        }
        if schema is not None:
            generation_config["responseMimeType"] = "application/json"
            generation_config["responseSchema"] = schema

        payload = {
            "contents": [
                {"role": "user", "parts": [{"text": system}, {"text": user}]},
            ],
            "generationConfig": generation_config,
        }

        # Transient failures (flaky DNS, timeouts, 5xx, 429) are retried with
        # backoff; permanent 4xx errors fail immediately.
        attempts = max(1, settings.max_llm_attempts)
        last_error: str | None = None
        for attempt in range(attempts):
            try:
                async with httpx.AsyncClient(timeout=self._timeout) as client:
                    response = await client.post(
                        self._url(), headers=self._headers(), json=payload
                    )
                if response.status_code == 200:
                    break
                last_error = f"Gemini returned HTTP {response.status_code}."
                if response.status_code < 500 and response.status_code != 429:
                    log.error("gemini_http_error", status=response.status_code,
                              body=response.text[:500])
                    raise LLMError(last_error)
                log.warning("gemini_transient_error", status=response.status_code,
                            attempt=attempt + 1)
            except httpx.HTTPError as exc:
                last_error = f"Gemini call failed: {exc}"
                log.warning("gemini_transient_failure", error=str(exc), attempt=attempt + 1)
            if attempt < attempts - 1:
                await asyncio.sleep(settings.callback_backoff_seconds * (attempt + 1))
        else:
            log.error("gemini_call_failed_after_retries", error=last_error)
            raise LLMError(last_error or "Gemini call failed.")

        try:
            data = response.json()
            text = data["candidates"][0]["content"]["parts"][0].get("text", "")
        except (KeyError, IndexError, TypeError) as exc:
            log.error("gemini_malformed_response", body=response.text[:500])
            raise LLMError("Gemini returned an unexpected response shape.") from exc

        return (text or "").strip()

    async def complete(self, system: str, user: str, *, max_tokens: int = 512) -> str:
        return await self._generate(system, user, max_tokens=max_tokens, schema=None)

    async def complete_json(
        self, system: str, user: str, schema: dict[str, Any], *, max_tokens: int = 1024
    ) -> dict[str, Any]:
        text = await self._generate(system, user, max_tokens=max_tokens, schema=schema)
        parsed = _extract_json_object(text)
        if parsed is None:
            log.error("gemini_json_invalid", snippet=text[:500])
            raise LLMError("Gemini returned invalid JSON.")
        return parsed

    async def is_available(self) -> bool:
        return bool(self._api_key)


def _extract_json_object(text: str) -> dict[str, Any] | None:
    """Extract a JSON object from the model text, tolerating markdown fences."""
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = stripped.strip("`")
        if stripped.startswith("json"):
            stripped = stripped[4:]
        stripped = stripped.strip()
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        start, end = stripped.find("{"), stripped.rfind("}")
        if start < 0 or end <= start:
            return None
        try:
            parsed = json.loads(stripped[start : end + 1])
        except json.JSONDecodeError:
            return None
    if not isinstance(parsed, dict):
        return None
    return parsed
