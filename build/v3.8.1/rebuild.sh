#!/usr/bin/env bash
# Rebuild memclaw-core-api:v3.8.1 = upstream core-api:v3.8.1 + our 3 local patches,
# then import it into the k3s containerd image store. Run ON THE HOST
# (root@ne.enpire.ru). No registry push (registry.enpire.ru is unreachable);
# the k3s containerd import is the delivery path.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"     # build/v3.8.1

BASE=${BASE:-ghcr.io/caura-ai/caura-memclaw-core-api:v3.8.1}
NEW=${NEW:-memclaw-core-api:v3.8.1}

echo "[*] building $NEW from $BASE (context: $HERE)"
docker build -f "$HERE/Dockerfile" -t "$NEW" "$HERE"

echo "[*] verifying all 3 local patches are present in the new image"
CID=$(docker create "$NEW")
mkdir -p /tmp/v381-verify
docker cp "$CID:/app/common/llm/constants.py"            /tmp/v381-verify/constants.py   >/dev/null
docker cp "$CID:/app/common/embedding/_registry.py"       /tmp/v381-verify/registry.py    >/dev/null
docker cp "$CID:/app/common/llm/providers/openai.py"      /tmp/v381-verify/openai.py      >/dev/null
docker rm "$CID" >/dev/null
fail=0
grep -q 'os.environ.get("OPENAI_CHAT_BASE_URL"' /tmp/v381-verify/constants.py && echo "    OK 0001 OPENAI_CHAT_BASE_URL env override" || { echo "    FAIL 0001" >&2; fail=1; }
grep -q '# *if base_url and send_dimensions:'    /tmp/v381-verify/registry.py  && echo "    OK 0002 embedding guard disabled"        || { echo "    FAIL 0002" >&2; fail=1; }
grep -q 'retrying with json_object'              /tmp/v381-verify/openai.py    && echo "    OK 0003 json_schema->json_object fallback"|| { echo "    FAIL 0003" >&2; fail=1; }
[ "$fail" -eq 0 ] || exit 1

echo "[*] importing into k3s containerd (namespace k8s.io)"
docker save "$NEW" | ctr -n k8s.io images import -

echo "[*] memclaw images now in containerd:"
ctr -n k8s.io images ls -q | grep -E 'memclaw-core-(api|storage-api)' || true
echo "[*] done. Deploy with build/deploy.sh (memclaw-api) — see MIGRATION-v3.8.1.md"
