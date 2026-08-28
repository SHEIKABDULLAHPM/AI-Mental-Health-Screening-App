"""FastAPI application factory and lifespan wiring."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.config import settings
from app.core.rag import QdrantVectorStore
from app.logging import get_logger, setup_logging

log = get_logger(__name__)

PLACEHOLDER_KEY = "change-me-dev-internal-key"


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_logging(settings.log_level)
    _validate_startup_settings()
    if settings.rag_enabled:
        _validate_rag_collection()
    try:
        from app.services.mq_consumer import start_consumer
        start_consumer()  # background RabbitMQ worker
    except Exception:
        log.warning("consumer_will_retry", exc_info=True)
    yield


def _validate_startup_settings() -> None:
    """Fail fast on insecure or unusable configuration (no baked-in secrets)."""
    if not settings.internal_api_key:
        raise RuntimeError(
            "AI_INTERNAL_API_KEY is not configured. The AI service cannot call "
            "the backend's internal endpoints without it."
        )
    if settings.app_env != "development" and settings.internal_api_key == PLACEHOLDER_KEY:
        raise RuntimeError(
            "AI_INTERNAL_API_KEY must be set to a strong, unique secret outside "
            "development. The placeholder 'change-me-dev-internal-key' is rejected."
        )
    if settings.llm_provider.lower() == "gemini" and not settings.gemini_api_key:
        log.warning("GEMINI_API_KEY_unset_llm_calls_will_fail")
    if not settings.backend_internal_url:
        raise RuntimeError("BACKEND_INTERNAL_URL is not configured.")


def _validate_rag_collection() -> None:
    """Ensure the RAG knowledge base is seeded before accepting jobs."""
    try:
        store = QdrantVectorStore()
        if store._collection_empty():  # noqa: SLF001
            raise RuntimeError(
                "RAG collection is empty. Run the rag-seed step (docker compose up) "
                "to populate the knowledge base, or set RAG_ENABLED=false."
            )
        log.info("rag_collection_ready", collection=store._collection)
        store.warm()  # pre-load the embedding model so the first job is fast
    except RuntimeError:
        raise
    except Exception as exc:
        log.warning("rag_validation_failed", error=str(exc))
        # Don't fail startup on transient Qdrant issues; the consumer will retry


def create_app() -> FastAPI:
    app = FastAPI(
        title="Synora AI Service",
        version="0.1.0",
        description="Emotion, risk, RAG and recommendation endpoints for Synora.",
        lifespan=lifespan,
    )

    apply_cors(app)

    app.include_router(api_router, prefix="/api/v1")

    @app.get("/health", tags=["ops"])
    async def health() -> dict:
        return {
            "status": "ok",
            "app": settings.app_name,
            "environment": settings.app_env,
        }

    return app


def apply_cors(app: FastAPI) -> None:
    """Configure CORS from settings. Cross-origin access is denied unless an
    allow-list or regex is configured explicitly - never a bare wildcard."""
    origins = [o.strip() for o in settings.cors_allowed_origins if o and o.strip() != "*"]
    regex = settings.cors_allow_origin_regex.strip()
    if not origins and not regex:
        log.info("cors_disabled_no_configured_origins")
        return
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_origin_regex=regex or None,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type", "X-Internal-Api-Key"],
        allow_credentials=False,
        max_age=3600,
    )


app = create_app()