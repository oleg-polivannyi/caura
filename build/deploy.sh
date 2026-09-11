#!/usr/bin/env bash
# Switch the memclaw-api deployment to the patched image and raise the LLM
# request timeout. Run ON THE HOST (root@ne.enpire.ru).
set -euo pipefail

NS=${NS:-memclaw}
DEPLOY=${DEPLOY:-memclaw-api}
IMG=${IMG:-memclaw-core-api:v6}

echo "[*] deploying $IMG to $NS/$DEPLOY"
kubectl -n "$NS" set image deployment/"$DEPLOY" api="$IMG"

# The Polza deepseek route is highly variable on large content — measured
# 22s..>120s for a ~1.5KB memory (and >120s for ~2.5KB) — while the code
# default is 25s (common/llm/constants.py OPENAI_REQUEST_TIMEOUT_SECONDS).
# Extraction runs as a background task, so this does not block the write
# response. 240s gives headroom for the slow tail; very large memories can
# still time out and degrade to the non-fatal fake fallback.
kubectl -n "$NS" set env deployment/"$DEPLOY" OPENAI_REQUEST_TIMEOUT_SECONDS=240

kubectl -n "$NS" rollout status deployment/"$DEPLOY" --timeout=300s
kubectl -n "$NS" get pods -l app="$DEPLOY" -o wide
echo "[*] image now:"; kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
