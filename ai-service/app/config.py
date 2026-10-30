import json

from pydantic import Field
from pydantic_settings import (
    BaseSettings,
    EnvSettingsSource,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)


class _LenientEnvSource(EnvSettingsSource):
    """Env source that tolerates empty/comma-separated values for list fields."""

    def decode_complex_value(self, field_name, field, value):
        try:
            return super().decode_complex_value(field_name, field, value)
        except (json.JSONDecodeError, ValueError):
            if field_name in ("cors_allowed_origins", "emotion_labels") and isinstance(
                value, str
            ):
                return [p.strip() for p in value.split(",") if p.strip()]
            raise


class Settings(BaseSettings):
    """Centralized, env-driven configuration for the AI service."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls,
        init_settings,
        env_settings,
        dotenv_settings,
        file_secret_settings,
    ):
        return (
            init_settings,
            _LenientEnvSource(settings_cls),
            dotenv_settings,
            file_secret_settings,
        )

    app_name: str = "mindease-ai"
    app_env: str = "development"
    host: str = "0.0.0.0"
    port: int = 8000
    log_level: str = "INFO"

    # Cross-origin policy. Cross-origin access is denied unless origins or a
    # regex are configured explicitly - never "*".
    cors_allowed_origins: list[str] = []
    cors_allow_origin_regex: str = ""

    # Inbound authentication for /api/v1. Enabled in deployed environments so
    # only the backend (which holds the shared key) can call the service.
    # /health stays public for orchestrator probes.
    inbound_auth_required: bool = Field(
        default=False, validation_alias="AI_INBOUND_AUTH_REQUIRED"
    )

    # Throttling for the /api/v1 endpoints (per client IP).
    rate_limit_enabled: bool = True
    rate_limit_per_minute: int = 120

    # LLM provider ("gemini" or "openai")
    llm_provider: str = "gemini"
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.5-flash"
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    llm_max_tokens: int = 4096

    # Backend callback (internal endpoints, X-Internal-Api-Key auth)
    backend_internal_url: str = "http://backend:8080/api/v1/internal"
    # Required - no safe default. Must match the backend's AI_INTERNAL_API_KEY.
    internal_api_key: str = Field(default="", validation_alias="AI_INTERNAL_API_KEY")
    callback_timeout_seconds: float = 15.0
    callback_attempts: int = 3
    callback_backoff_seconds: float = 2.0

    # AI job processing
    max_llm_attempts: int = 3
    prompt_version: str = "1.0"

    # RAG / vector store
    qdrant_url: str = "http://qdrant:6333"
    qdrant_collection: str = "mindease_chunks"
    embedding_model: str = "sentence-transformers/all-MiniLM-L6-v2"
    rag_top_k: int = 5
    rag_enabled: bool = True

    # Messaging
    rabbitmq_host: str = "rabbitmq"
    rabbitmq_port: int = 5672
    rabbitmq_username: str = "mindease"
    rabbitmq_password: str = "change-me"
    ai_tasks_queue: str = "ai_tasks"

    # Server-side facial emotion inference (vit_fer_fp16.tflite, ViT-B/16).
    #
    # emotion_labels MUST stay in the model's own id2label order. This is NOT
    # the FER2013 order: positions 5/6 are neutral, sad here. Reordering
    # silently mislabels three of seven classes with no runtime error.
    # Same vocabulary and ordering as the Flutter client and Spring backend.
    emotion_enabled: bool = True
    emotion_model_path: str = "app/models/vit_fer_fp16.tflite"
    emotion_model_version: str = "vit-fer-7"
    emotion_labels: list[str] = [
        "anger",
        "disgust",
        "fear",
        "happy",
        "neutral",
        "sad",
        "surprise",
    ]
    # Gates mirror the on-device pipeline (0.60 / 0.10) and are justified by
    # the 175-image validation replay: 90.3% single-frame emission with all
    # seven classes reachable. Do not lower these to raise hit counts.
    emotion_confidence_threshold: float = 0.6
    emotion_margin_threshold: float = 0.10
    emotion_normalization: str = "mean_std_0.5"  # mean_std_0.5 [-1,1] | div255 [0,1]
    emotion_threads: int = 2
    emotion_max_image_mb: float = 5.0


settings = Settings()
