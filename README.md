# MindEase — AI-Based Mental Health Screening and Support

A Flutter application for evidence-based mental health screening (PHQ-9, GAD-7, PSS, WHO-5) with AI-driven wellness guidance. It runs entirely client-side; there is no backend service.

## Run with Docker

The project is fully containerized. A single `web` service builds the Flutter app and serves it with nginx.

### Prerequisites

- Docker Engine 24+ with Docker Compose v2 (`docker compose version`)

### Quick start

```bash
# 1. Configure environment (optional)
cp .env.example .env

# 2. Build and start
docker compose up -d --build

# 3. Verify
docker compose ps
```

Open <http://localhost:8080>. The container is healthy when `docker compose ps` shows `healthy` (the container self-checks `/healthz`).

### Stopping and rebuilding

```bash
docker compose down          # stop and remove the container/network
docker compose up -d --build # rebuild after code changes
```

### Configuration (.env)

| Variable             | Default | Description                                      |
| -------------------- | ------- | ------------------------------------------------ |
| `WEB_PORT`           | `8080`  | Host port mapped to the container's nginx (80).  |
| `WEB_APP_BASE_PATH`  | `/`     | Deploy path prefix, e.g. `/mindease/` under a sub-path. |
| `FLUTTER_WEB_USE_SKIA`| `true`  | Force the Skia renderer for Flutter web.          |

### Details

- **Multi-stage build**: `ghcr.io/cirruslabs/flutter:stable` builds the web bundle; `nginx:1.27-alpine` serves it.
- **Non-root runtime**: the container drops to the `nginx` user and runs with a read-only root filesystem (`tmpfs` for `/tmp`).
- **Restart policy**: `unless-stopped`; anonymous volumes persist nginx cache/run state.
- **SPA routing**: unknown routes fall back to `index.html`.
- **Healthcheck**: `GET /healthz` returns `200` when the app is serving.
