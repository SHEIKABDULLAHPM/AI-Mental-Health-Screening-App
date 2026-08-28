"""Pytest bootstrap: configure the AI service for offline unit tests.

Environment must be set before `app.config.settings` is instantiated, so this
runs at conftest import time (pytest imports conftest before test modules).
Structlog is routed through the stdlib logging system so that pytest's
`caplog` fixture can assert on structured-log events.
"""
import logging
import os

import structlog

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("AI_INTERNAL_API_KEY", "test-internal-key")
os.environ.setdefault("RATE_LIMIT_ENABLED", "true")
os.environ.setdefault("RATE_LIMIT_PER_MINUTE", "120")
os.environ.setdefault("QDRANT_URL", "http://localhost:6333")
os.environ.setdefault("RABBITMQ_HOST", "localhost")
os.environ.setdefault("RABBITMQ_PORT", "5672")

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.KeyValueRenderer(),
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=False,
)

logging.basicConfig(level=logging.INFO, stream=os.devnull, force=True)