# syntax=docker/dockerfile:1

# ------------------------------------------------------------------
# Stage 1: build the Flutter web app
# ------------------------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:stable AS build

ENV FLUTTER_SUPPRESS_ANALYTICS=true

# Accept analytics terms so non-interactive commands never prompt.
WORKDIR /app

# Cache dependency resolution separately from app source.
COPY pubspec.yaml ./
RUN flutter pub get

COPY . .

# Allow deploying under a non-root base path via WEB_APP_BASE_PATH (e.g. /mindease/).
ARG WEB_APP_BASE_PATH=/
ENV FLUTTER_WEB_USE_SKIA=true

RUN flutter build web \
    --release \
    --base-href=${WEB_APP_BASE_PATH} \
    --dart-define=FLUTTER_WEB_USE_SKIA=${FLUTTER_WEB_USE_SKIA}

# ------------------------------------------------------------------
# Stage 2: serve the static build with nginx
# ------------------------------------------------------------------
FROM nginx:1.27-alpine AS web

# curl used by the compose healthcheck
RUN apk add --no-cache curl

COPY nginx/nginx.conf /etc/nginx/nginx.conf

COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1:80/healthz >/dev/null || exit 1

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]
