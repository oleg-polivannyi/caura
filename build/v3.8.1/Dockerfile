FROM ghcr.io/caura-ai/caura-memclaw-core-api:v3.8.1

# Overlay our 3 local patches onto the upstream 3.8.1 runtime:
#   1) env-overridable OPENAI_CHAT_BASE_URL
#   2) allow custom embedding endpoint with dimensions=
#   3) json_schema -> json_object fallback on HTTP 400
COPY --chown=appuser:appuser app/ /app/
RUN find /app -name __pycache__ -type d -prune -exec rm -rf {} + || true
