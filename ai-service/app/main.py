"""FastAPI application factory and lifespan wiring."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.config import settings
from app.logging import get_logger, setup_logging

log = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_logging(settings.log_level)
    try:
        from app.services.mq_consumer import start_consumer
        start_consumer()  # background RabbitMQ worker
    except Exception:  # noqa: BLE001
        log.warning("consumer_will_retry", exc_info=True)
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title="MindEase AI Service",
        version="0.1.0",
        description="Emotion, risk, RAG and recommendation endpoints for MindEase.",
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(api_router, prefix="/api/v1")

    @app.get("/health", tags=["ops"])
    async def health() -> dict:
        return {
            "status": "ok",
            "app": settings.app_name,
            "environment": settings.app_env,
        }

    return app


app = create_app()