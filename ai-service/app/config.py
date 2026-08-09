from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Centralized, env-driven configuration for the AI service."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "mindease-ai"
    app_env: str = "development"
    host: str = "0.0.0.0"
    port: int = 8000
    log_level: str = "INFO"

    # LLM provider
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"

    # RAG / vector store
    qdrant_url: str = "http://qdrant:6333"
    qdrant_collection: str = "mindease_chunks"
    embedding_model: str = "sentence-transformers/all-MiniLM-L6-v2"

    # Messaging
    rabbitmq_host: str = "rabbitmq"
    rabbitmq_port: int = 5672
    rabbitmq_username: str = "mindease"
    rabbitmq_password: str = "change-me"
    ai_tasks_queue: str = "ai_tasks"

    # Cache
    redis_uri: str = "redis://:change-me@redis:6379"


settings = Settings()