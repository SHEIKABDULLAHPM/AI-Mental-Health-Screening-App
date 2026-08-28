# ============================================================================
# MindEase - dev-only mailcatcher.
# A tiny SMTP server + web inbox so the forgot-password flow can be exercised
# end-to-end in local development WITHOUT a real mail server.
#
# Built from the public python:3-alpine image (no external registry access needed
# beyond the default library index). Lives only in the dev overlay, so it is
# never present in production/base. It stores messages in memory and never
# relays mail outside the local Docker network.
# ============================================================================
FROM python:3-alpine
WORKDIR /app
COPY server.py /app/server.py
ENV PYTHONUNBUFFERED=1
EXPOSE 1025 8025
CMD ["python3", "/app/server.py"]
