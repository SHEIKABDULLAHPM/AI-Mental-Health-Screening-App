FROM python:3.12-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    APP_PORT=8000

WORKDIR /app

# System deps for sentence-transformers / tokenizers
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
# sentence-transformers pulls in the CUDA-enabled torch wheel (~2 GB of NVIDIA
# libs) by default even on CPU-only hosts. Install the CPU torch build first so
# the image stays small and the Docker build is fast; `pip install -r` then
# skips the already-satisfied torch dependency.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --index-url https://download.pytorch.org/whl/cpu \
        --extra-index-url https://pypi.org/simple "torch>=2.2,<3" \
    && pip install -r requirements.txt

COPY app ./app
COPY scripts ./scripts
# The production emotion model (app/models/vit_fer_fp16.tflite, ViT-B/16
# fp16, ~172 MB) ships inside the image via `COPY app` above;
# EMOTION_MODEL_PATH defaults to app/models/vit_fer_fp16.tflite. No extra
# packages beyond requirements.txt (ai-edge-litert + pillow + numpy) are
# needed. NOTE: this file dominates the image size -- see
# docs/fer-migration.md section 8 for the packaging options.
# Pre-download every Hugging Face model the service loads so RAG *and* mood
# text analysis are fast on first use and work without runtime network access
# (the models are cached in the image under HF_HOME instead of being fetched
# from HuggingFace per boot). Without this the first /mood/analyze request
# blocked for minutes on two ~500 MB transformer downloads and always
# exceeded the backend's 30 s timeout, silently dropping the user's note.
ARG EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG EMOTION_MODEL=j-hartmann/emotion-english-distilroberta-base
ARG SENTIMENT_MODEL=cardiffnlp/twitter-roberta-base-sentiment-latest
ENV HF_HOME=/app/model-cache
# Xet-backed downloads stalled for minutes inside BuildKit on this host even
# though plain HTTP downloads were fast. Plain HTTP keeps the image build
# deterministic; the baked model files are identical either way.
ENV HF_HUB_DISABLE_XET=1
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('$EMBEDDING_MODEL')" \
    && python -c "\
from transformers import pipeline; \
pipeline('text-classification', model='$EMOTION_MODEL', top_k=None, truncation=True); \
pipeline('text-classification', model='$SENTIMENT_MODEL', top_k=None, truncation=True)" \
    && rm -rf /app/model-cache/models--*/.cache 2>/dev/null || true

RUN useradd --create-home --shell /bin/bash ai \
    && chown -R ai:ai /app
USER ai

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=5 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health').status==200 else 1)"

CMD ["sh", "-c", "uvicorn app.main:app --host ${APP_HOST:-0.0.0.0} --port ${APP_PORT:-8000}"]