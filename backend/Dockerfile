# ============================================================================
# MindEase backend - build & runtime image
# The Maven wrapper and .mvn are intentionally provided by the image so the
# project tree stays lean and reproducible (see .gitignore).
# ============================================================================
# ---------- Stage 1: build ----------
FROM maven:3.9.9-eclipse-temurin-21 AS builder
WORKDIR /build

# Cache-mounted ~/.m2 keeps downloads fast across rebuilds and tolerates
# transient registry/DNS blips by only fetching what is actually missing.
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -DskipTests dependency:go-offline

COPY src ./src
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -DskipTests clean package

# ---------- Stage 2: runtime ----------
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN apk add --no-cache curl

RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring

COPY --from=builder /build/target/mindease-backend-*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]