#!/usr/bin/env bash
# Last-resort rollback of memclaw-api to the known-good v5 image.
set -euo pipefail
kubectl -n memclaw set image deployment/memclaw-api api=memclaw-core-api:v5
kubectl -n memclaw rollout status deployment/memclaw-api --timeout=300s
kubectl -n memclaw get pods -l app=memclaw-api -o wide
