# Synora — AI Mental Health Screening & Support Guidance

A full-stack, containerized platform for evidence-based mental health
screening with AI-driven, evidence-grounded support guidance.

- **Mobile app:** Flutter (Android) — feature-based Clean Architecture
- **Backend:** Spring Boot 3 (modular, `/api/v1` versioned)
- **AI service:** Python/FastAPI (emotion, risk, RAG, recommendation, LLM)
- **Data:** MongoDB · Redis · RabbitMQ · Qdrant · MinIO
- **Auth:** Keycloak (OIDC)

Everything runs through **Docker Compose**. Nothing is installed on the host
except Docker; databases and internal services are kept off the public
interface.

---

## Quick start (one command)

```bash
cp .env.example .env        # then edit real secrets inside .env
docker compose up -d --build
```

The root `docker-compose.yml` is the default entry point; it merges the shared
base definitions with the development overlay and reads `docker/.env`
automatically. Or use the helper: `./scripts/start.sh`.

> The `.env.example` ships with **dev-only placeholders**. Never use them in
> production. For production run from the root:
> `docker compose -f docker-compose.prod.yml up -d --build`.

## Verify everything is healthy

```bash
docker compose ps
```

All services should report `healthy` (every container ships a health check).
Spot-check the API:

```bash
curl http://localhost:8080/actuator/health          # backend + infra health
curl http://localhost:8000/api/v1/risk/assess \     # AI service (dev-only, 127.0.0.1)
  -H 'Content-Type: application/json' \
  -d '{"screening_score":{"phq9":20},"contextual_flags":["hopeless"]}'
```

## Service matrix

| Service     | Container         | Host port (dev)        | Notes                              |
| ----------- | ----------------- | ---------------------- | ---------------------------------- |
| Backend API | `mindease-backend`| `localhost:8080`      | Spring Boot, `/api/v1`, `/actuator`|
| AI service  | `mindease-ai-service`| `localhost:8000`    | FastAPI, `/api/v1`, `/health`      |
| Keycloak    | `mindease-keycloak`| `localhost:8081`      | Admin console at `/admin`          |
| MongoDB     | `mindease-mongo`  | dev-only `127.0.0.1:27017` | primary database                 |
| Redis       | `mindease-redis`  | dev-only `127.0.0.1:6379` | cache                            |
| RabbitMQ    | `mindease-rabbitmq`| dev-only `5672/15672`  | async/AI jobs                      |
| Qdrant      | `mindease-qdrant` | dev-only `127.0.0.1:6333` | RAG vector store                 |
| MinIO       | `mindease-minio`  | dev-only `9000/9001`    | object storage                     |

**Security:** MongoDB, Redis, RabbitMQ, Qdrant and MinIO are *not* published on
the `internal` Docker network. Dev-only debug ports are bound strictly to
`127.0.0.1`; the production overlay exposes none of them. Only the backend and
Keycloak are reachable from the host; the AI service has **no host-published
port in production** (it is reached internally over the Docker networks, and on
`127.0.0.1` only in the dev overlay).

## Stop

```bash
docker compose down
# add -v to also delete named volumes (data):
docker compose down -v
```

## Rebuild after code changes

```bash
docker compose up -d --build        # or ./scripts/rebuild.sh
```

## View logs

```bash
docker compose logs -f backend ai-service
```

## Environments & secrets

- Root `.env` carries all configuration; copy from `.env.example` and change
  every `change-me-*` value. `GEMINI_API_KEY` (for the default Gemini provider)
  and the shared `AI_INTERNAL_API_KEY` secret are both required - the backend
  refuses to start with a blank/placeholder internal key outside the dev/test
  profiles.
- Each service folder also ships a `.env.example` (see `ai-service/.env.example`).
- Never commit the real `.env` (ignored by `.gitignore`).

| File            | Purpose                                                    |
|-----------------|------------------------------------------------------------|
| `docker-compose.yml` | Default dev entry: merges `base` + `dev`.              |
| `docker-compose.prod.yml` | Prod entry: merges `base` + `prod`.                 |
| `docker/compose.base.yml` | Shared definitions. Never run alone.                  |
| `docker/compose.dev.yml`  | Dev: debug ports on `127.0.0.1`, debug logging.       |
| `docker/compose.prod.yml` | Prod: no infra ports, resource limits, restart policies. |

## Folder map

```
├── app/                  # Flutter mobile client
├── backend/              # Spring Boot API (feature modules)
├── ai-service/           # FastAPI AI/RAG/LLM service
├── docker/               # base/dev/prod compose + assets
├── docs/                 # architecture notes
└── scripts/              # host-side helpers
```

## Documentation

- See [docs/architecture.md](docs/architecture.md) for the full architecture,
  data flow and extension guide.