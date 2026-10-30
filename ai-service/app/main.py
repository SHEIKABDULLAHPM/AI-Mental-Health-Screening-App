"""FastAPI application factory and lifespan wiring."""

import hmac
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

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
    if settings.emotion_enabled:
        from app.core.mood.face_emotion import warmup_face_emotion_analyzer

        if warmup_face_emotion_analyzer():
            log.info("face_emotion_model_ready", version=settings.emotion_model_version)
        else:
            # Non-fatal: the /face endpoint returns 503 while every existing
            # flow (on-device /camera, text, fusion) keeps working.
            log.warning("face_emotion_model_unavailable_at_startup")
    _warmup_text_analyzer()
    try:
        from app.services.mq_consumer import start_consumer
        start_consumer()  # background RabbitMQ worker
    except Exception:
        log.warning("consumer_will_retry", exc_info=True)
    yield


def _text_analyzer_status() -> str:
    """Report whether the text NLP models are warm or degraded to rules."""
    try:
        from app.core.mood.text_analyzer import get_text_analyzer

        analyzer = get_text_analyzer()
        if getattr(analyzer, "_emotion_pipeline", None) is None:
            return "rule-based"
        return "transformer"
    except Exception:
        return "unavailable"


def _warmup_text_analyzer() -> None:
    """Load the text emotion/sentiment models before serving traffic.

    Without this the first /mood/analyze request paid the full transformer
    load (~5 minutes on a cold cache), which always exceeded the backend's
    30 s timeout and silently dropped the user's reflection text.
    Non-fatal: the analyzer degrades to rule-based scoring on its own.
    """
    try:
        from app.core.mood.text_analyzer import warmup_text_analyzer

        engine = warmup_text_analyzer()
        log.info("text_models_ready", engine=engine)
    except Exception:
        log.warning("text_models_unavailable_at_startup", exc_info=True)


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
        description="Mood, risk, RAG and recommendation endpoints for Synora.",
        lifespan=lifespan,
    )

    apply_cors(app)
    apply_inbound_auth(app)

    app.include_router(api_router, prefix="/api/v1")

    @app.get("/health", tags=["ops"])
    async def health() -> dict:
        emotion_status = "disabled"
        if settings.emotion_enabled:
            try:
                from app.core.mood.face_emotion import get_face_emotion_analyzer

                emotion_status = (
                    "loaded"
                    if get_face_emotion_analyzer().loaded
                    else "unavailable"
                )
            except Exception:
                emotion_status = "unavailable"
        return {
            "status": "ok",
            "app": settings.app_name,
            "environment": settings.app_env,
            "emotion_model": emotion_status,
            "text_analyzer": _text_analyzer_status(),
        }

    return app


def apply_inbound_auth(app: FastAPI) -> None:
    """Require the shared internal key on every /api/v1 route when enabled.

    The AI service holds no user identity of its own: it is an internal
    dependency of the Spring backend. Binding it to 127.0.0.1 only protects
    development; in a container network any peer could otherwise invoke
    analysis endpoints directly. /health stays unauthenticated so probes and
    the compose healthcheck keep working.
    """

    class InboundKeyMiddleware(BaseHTTPMiddleware):
        async def dispatch(self, request: Request, call_next):
            if settings.inbound_auth_required and request.url.path.startswith(
                "/api/v1"
            ):
                supplied = request.headers.get("X-Internal-Api-Key", "")
                expected = settings.internal_api_key
                if not expected or not hmac.compare_digest(supplied, expected):
                    return JSONResponse(
                        status_code=401,
                        content={"detail": "Invalid or missing internal API key."},
                    )
            return await call_next(request)

    app.add_middleware(InboundKeyMiddleware)


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