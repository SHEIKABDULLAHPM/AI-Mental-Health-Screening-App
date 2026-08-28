# Synora Architecture

## System overview

```
                    ┌────────────────────────────────────────────┐
                    │              Flutter (Android)             │
                    │  features/*  (Clean Architecture)          │
                    └───────────────┬────────────────────────────┘
                                    │ HTTPS /api/v1 (+ OIDC tokens)
                                    ▼
                ┌───────────────────────────────────────────────┐
                │             Keycloak  (OIDC) ────────────────┐ │
                └───────────────┬──────────────────────────────┘ │
                                │ JWT                            │
                                ▼                                │
┌───────────────────────────────────────────────┐                │
│            Spring Boot Backend                │                │
│  /api/v1 · modules/*  feature-based           │                │
│  common/* error+logging · SecurityConfig      │                │
└───┬───────────┬───────────┬───────────┬───────┴────────────────┘
    │           │           │           │
    ▼           ▼           ▼           ▼
 MongoDB     Redis      RabbitMQ      MinIO
 (primary)   (cache)    (async AI      (files)
                         jobs)
    │                            │
    └────────────┬───────────────┘
                 ▼
           ┌──────────────────────────────┐
           │          AI Service          │   FastAPI
           │  emotion · risk · RAG · rec  │
           │  LLM (OpenAI-compatible)     │
           └──────────┬──────────────┬────┘
                      ▼              ▼
                  Qdrant         OpenAI/LLM
               (vector store)
```

### Networks
- `frontend` — reachable from the host: `backend`, `ai-service`, `keycloak`.
- `internal` — databases/queues/storage; **not published** to the host.
  `backend` and `ai-service` join `internal` to talk to infra.

### Data flow (screening → guidance)
1. User completes a questionnaire in Flutter.
2. `/api/v1/screenings` persists the result to MongoDB.
3. Backend enqueues an AI job on RabbitMQ (`ai_tasks`) and/or calls the AI
   service (`/api/v1/...`) directly.
4. AI service: risk assessment + emotion detection + RAG retrieval from Qdrant
   → LLM-grounded recommendations → response.
5. Content heavy artifacts (reports/images) are stored via MinIO.

## Backend module pattern (extend this)
Each feature lives under `modules/<feature>/` in four layers:

```
modules/<feature>/
├── api/          # Spring REST controllers (presentation)
├── application/  # use-case services (business rules)
├── domain/       # entities + repository interfaces (pure)
└── persistence/  # Spring Data adapters (infra)
```

Cross-cutting helpers live in `common/` (`api`, `error`, `logging`) and
integration config in `config/` (security, redis, rabbit, minio, http client).

Example already present: `modules/screening/*`.

## AI service module map
```
app/
├── api/v1/endpoints/   # screening, emotion, risk, rag, recommendations
├── core/               # engine abstractions + implementations
│   ├── emotion/  risk/  rag/  recommendation/  llm/
├── services/           # orchestration (ai_router) + MQ consumer
├── schemas/            # pydantic request/response models
└── config.py logging.py errors.py
```
Engines obey small protocol interfaces so providers can be swapped without
touching HTTP code.

## Adding a new backend feature
1. `modules/<feature>/domain` — entity + repository interface.
2. `modules/<feature>/persistence` — Spring Data adapter.
3. `modules/<feature>/application` — service/use-case.
4. `modules/<feature>/api` — REST controller under `/api/v1/<feature>`.
5. Rotate roles in Keycloak if it needs authorization.

## Adding a new AI capability
1. Add an interface in `ai-service/app/core/<capability>/`.
2. Implement + export in the module `__init__.py`.
3. Expose a pydantic schema + endpoint in `app/schemas` and `app/api/v1/endpoints/`.
4. Optionally wire into `app/services/ai_router.py` for composition.

## Configuration & secrets
Everything is env-driven; secrets come from the root `.env` (see
`.env.example`). No hardcoded credentials. Rotate through Docker secrets or a
vault in production.